-- APIIS 志愿者管理 — 一次性应用全部迁移（SQL Editor 便捷版，仅用于全新项目）
-- 已部署的库请只跑新迁移。pg_cron 见 pg_cron_setup.sql；邮件见 email_setup.sql；建超管见 make_admin.sql。

-- ===== 20260617090000_initial_schema.sql =====
-- APIIS 志愿者管理 — 初始 schema（表、约束、索引）
-- 函数/触发器见 ..._functions_triggers.sql；RLS 策略见 ..._rls_policies.sql

create extension if not exists pgcrypto with schema extensions;

-- profiles：用户资料，1:1 关联 auth.users
create table public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  full_name  text not null default '',
  role       text not null default 'volunteer' check (role in ('admin', 'volunteer')),
  phone      text,
  created_at timestamptz not null default now()
);

-- cohorts：学期 / 期次
create table public.cohorts (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  start_date date,
  end_date   date,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

-- groups：Zoom 小组
create table public.groups (
  id          uuid primary key default gen_random_uuid(),
  cohort_id   uuid not null references public.cohorts (id) on delete cascade,
  name        text not null,
  zoom_link   text,
  meeting_day text,                       -- 上课日，如 'Monday'
  created_at  timestamptz not null default now()
);

-- students：学员
create table public.students (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.groups (id) on delete cascade,
  full_name  text not null,
  email      text,
  created_at timestamptz not null default now()
);

-- assignments：小组 ↔ 志愿者 分配关系
create table public.assignments (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups (id) on delete cascade,
  volunteer_id uuid not null references public.profiles (id) on delete cascade,
  assigned_at  timestamptz not null default now(),
  unique (group_id, volunteer_id)
);

-- attendance_records：出勤与表现记录（核心表）
create table public.attendance_records (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups (id) on delete cascade,
  student_id   uuid not null references public.students (id) on delete cascade,
  volunteer_id uuid references public.profiles (id) on delete set null,  -- 填写人
  session_date date not null,
  attended     boolean not null default false,
  video_on     boolean not null default false,
  contributed  boolean not null default false,
  notes        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  -- 一个学员在某次课只有一条记录 → 支持「存在则更新」的 upsert
  unique (student_id, session_date)
);

-- availability：每周可用性回馈
create table public.availability (
  id            uuid primary key default gen_random_uuid(),
  volunteer_id  uuid not null references public.profiles (id) on delete cascade,
  week_start_date date not null,          -- 该周的周一日期
  is_available  boolean,                  -- null = 尚未回复
  responded_at  timestamptz,
  created_at    timestamptz not null default now(),
  unique (volunteer_id, week_start_date)
);

-- coverage_requests：补位请求
create table public.coverage_requests (
  id             uuid primary key default gen_random_uuid(),
  group_id       uuid not null references public.groups (id) on delete cascade,
  week_start_date date not null,
  reason         text,
  status         text not null default 'open' check (status in ('open', 'covered')),
  covered_by     uuid references public.profiles (id) on delete set null,
  created_at     timestamptz not null default now(),
  unique (group_id, week_start_date)
);

-- notifications：站内通知
create table public.notifications (
  id           uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  type         text not null check (type in ('weekly_check', 'coverage_request', 'general')),
  title        text not null,
  body         text,
  is_read      boolean not null default false,
  related_id   uuid,                      -- 关联的 coverage_request 等（保持灵活，不加 FK）
  created_at   timestamptz not null default now()
);

-- 索引：RLS 子查询与常见过滤会用到
create index idx_groups_cohort           on public.groups (cohort_id);
create index idx_students_group          on public.students (group_id);
create index idx_assignments_volunteer   on public.assignments (volunteer_id);
create index idx_assignments_group       on public.assignments (group_id);
create index idx_attendance_group        on public.attendance_records (group_id);
create index idx_attendance_student      on public.attendance_records (student_id);
create index idx_attendance_session_date on public.attendance_records (session_date);
create index idx_availability_volunteer  on public.availability (volunteer_id);
create index idx_availability_week       on public.availability (week_start_date);
create index idx_coverage_status         on public.coverage_requests (status);
create index idx_coverage_week           on public.coverage_requests (week_start_date);
create index idx_notifications_recipient on public.notifications (recipient_id);


-- ===== 20260617090100_functions_triggers.sql =====
-- APIIS 志愿者管理 — 辅助函数与触发器

-- 当前用户是否 admin。
-- SECURITY DEFINER + 固定 search_path：以函数属主(postgres，具 BYPASSRLS)身份读取，
-- 因此即便在 profiles 自身的 RLS 策略中调用也不会触发递归。
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;

-- 当前用户是否被分配到某小组（含补位产生的临时分配）。
create or replace function public.is_assigned_to_group(p_group_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.assignments
    where group_id = p_group_id and volunteer_id = (select auth.uid())
  );
$$;

-- 新用户注册时自动创建 profile（默认志愿者；可由 user metadata 指定 role/full_name/phone）。
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, role, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'role', 'volunteer'),
    new.raw_user_meta_data ->> 'phone'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 维护 attendance_records.updated_at
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_attendance_updated_at
  before update on public.attendance_records
  for each row execute function public.set_updated_at();

-- 防止非管理员修改自己的 role（防止越权提权）。
create or replace function public.guard_profile_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.role is distinct from old.role) and not public.is_admin() then
    raise exception '只有管理员可以修改角色 (role)';
  end if;
  return new;
end;
$$;

create trigger trg_profiles_guard_role
  before update on public.profiles
  for each row execute function public.guard_profile_role();

-- 策略中会用到这两个辅助函数，确保 authenticated 可执行
grant execute on function public.is_admin() to anon, authenticated;
grant execute on function public.is_assigned_to_group(uuid) to anon, authenticated;


-- ===== 20260617090200_rls_policies.sql =====
-- APIIS 志愿者管理 — 启用 RLS 并定义策略
-- 角色：admin（管理员，全权）、volunteer（志愿者，按分配/归属受限）
-- anon（未登录）无任何策略 → 默认拒绝。

alter table public.profiles           enable row level security;
alter table public.cohorts            enable row level security;
alter table public.groups             enable row level security;
alter table public.students           enable row level security;
alter table public.assignments        enable row level security;
alter table public.attendance_records enable row level security;
alter table public.availability       enable row level security;
alter table public.coverage_requests  enable row level security;
alter table public.notifications      enable row level security;

-- ============================== profiles ==============================
create policy "profiles_select_self_or_admin" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or public.is_admin());

create policy "profiles_update_self_or_admin" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()) or public.is_admin())
  with check (id = (select auth.uid()) or public.is_admin());
-- 注：role 的变更由 guard_profile_role 触发器限制为「仅管理员」。

create policy "profiles_insert_admin" on public.profiles
  for insert to authenticated
  with check (public.is_admin());
-- 注：常规注册由 handle_new_user 触发器(SECURITY DEFINER)插入，不经过此策略。

create policy "profiles_delete_admin" on public.profiles
  for delete to authenticated
  using (public.is_admin());

-- ============================== cohorts ==============================
create policy "cohorts_select_all_auth" on public.cohorts
  for select to authenticated using (true);
create policy "cohorts_admin_write" on public.cohorts
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ============================== groups ==============================
-- 所有登录用户可读（补位征集、分配展示都需要）；仅管理员可写。
create policy "groups_select_all_auth" on public.groups
  for select to authenticated using (true);
create policy "groups_admin_write" on public.groups
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ============================== students ==============================
-- 管理员全权；志愿者只能读自己被分配小组的学员。
create policy "students_select_assigned_or_admin" on public.students
  for select to authenticated
  using (public.is_admin() or public.is_assigned_to_group(group_id));
create policy "students_admin_write" on public.students
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ============================== assignments ==============================
-- 管理员增删改查；志愿者只能读自己的分配。
create policy "assignments_select_self_or_admin" on public.assignments
  for select to authenticated
  using (public.is_admin() or volunteer_id = (select auth.uid()));
create policy "assignments_admin_write" on public.assignments
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
-- 注：志愿者「认领补位」所需的自助分配将在 Phase 4 用 SECURITY DEFINER 的 RPC 实现。

-- ============================== attendance_records ==============================
-- 志愿者可读写自己被分配小组的记录；删除仅管理员。
create policy "attendance_select_assigned_or_admin" on public.attendance_records
  for select to authenticated
  using (public.is_admin() or public.is_assigned_to_group(group_id));

create policy "attendance_insert_assigned" on public.attendance_records
  for insert to authenticated
  with check (
    public.is_admin()
    or (public.is_assigned_to_group(group_id) and volunteer_id = (select auth.uid()))
  );

create policy "attendance_update_assigned" on public.attendance_records
  for update to authenticated
  using (public.is_admin() or public.is_assigned_to_group(group_id))
  with check (
    public.is_admin()
    or (public.is_assigned_to_group(group_id) and volunteer_id = (select auth.uid()))
  );

create policy "attendance_delete_admin" on public.attendance_records
  for delete to authenticated using (public.is_admin());

-- ============================== availability ==============================
-- 志愿者只能读写自己的；管理员可查看全部（汇总）。
create policy "availability_select_self_or_admin" on public.availability
  for select to authenticated
  using (public.is_admin() or volunteer_id = (select auth.uid()));

create policy "availability_insert_self" on public.availability
  for insert to authenticated
  with check (volunteer_id = (select auth.uid()));

create policy "availability_update_self" on public.availability
  for update to authenticated
  using (volunteer_id = (select auth.uid()))
  with check (volunteer_id = (select auth.uid()));

create policy "availability_admin_write" on public.availability
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ============================== coverage_requests ==============================
-- 志愿者可读 open（或自己认领过）的请求；可把 open 改为 covered 并认领。管理员全权。
create policy "coverage_select_open_or_own_or_admin" on public.coverage_requests
  for select to authenticated
  using (
    public.is_admin()
    or status = 'open'
    or covered_by = (select auth.uid())
  );

create policy "coverage_update_claim" on public.coverage_requests
  for update to authenticated
  using (public.is_admin() or status = 'open')
  with check (
    public.is_admin()
    or (status = 'covered' and covered_by = (select auth.uid()))
  );

create policy "coverage_admin_write" on public.coverage_requests
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ============================== notifications ==============================
-- 仅本人可读/改/删自己的通知（符合「只能被本人读取」，管理员也不例外）。
create policy "notifications_select_own" on public.notifications
  for select to authenticated
  using (recipient_id = (select auth.uid()));

create policy "notifications_update_own" on public.notifications
  for update to authenticated
  using (recipient_id = (select auth.uid()))
  with check (recipient_id = (select auth.uid()));

create policy "notifications_delete_own" on public.notifications
  for delete to authenticated
  using (recipient_id = (select auth.uid()));

create policy "notifications_insert_admin" on public.notifications
  for insert to authenticated
  with check (public.is_admin());
-- 注：Edge Function 以 service_role 运行，绕过 RLS 批量写入通知（Phase 4）。


-- ===== 20260618093000_classes_and_contribution.sql =====
-- 迁移：4 个真实班级 + 各自的小组；评估改为单一 Contribution(0-3)
-- 说明：沿用 cohorts 表作为「班级(class)」层级；前端 UI 以 "Class" 呈现。
-- 本迁移可在已部署的库上安全运行一次。

-- 1) 移除初期的测试期次（级联删除 Group A/B/C 及其学员/出勤/分配）
delete from public.cohorts where id = '00000000-0000-0000-0000-0000000000c1';

-- 2) attendance_records：评估从「出席/视频/贡献」三个布尔，改为单一 contribution 分数
--    (0-3，可空 = 未评估)
alter table public.attendance_records
  drop column if exists attended,
  drop column if exists video_on,
  drop column if exists contributed,
  add column if not exists contribution smallint check (contribution >= 0 and contribution <= 3);

-- 3) groups 增加 (cohort_id, name) 唯一约束（防重名 + 支持幂等导入）
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'groups_cohort_name_unique') then
    alter table public.groups add constraint groups_cohort_name_unique unique (cohort_id, name);
  end if;
end $$;

-- 4) 四个班级
insert into public.cohorts (id, name, is_active) values
  ('00000000-0000-0000-0000-0000000060a0', 'MMin 6P Monday Morning',  true),
  ('00000000-0000-0000-0000-0000000060b0', 'MMin 6L Tuesday Night',   true),
  ('00000000-0000-0000-0000-0000000070a0', 'MMin 7P Tuesday Morning', true),
  ('00000000-0000-0000-0000-0000000070b0', 'MMin 7L Monday Night',    true)
on conflict (id) do nothing;

-- 5) 各班级的小组 Group 1..N（共 28+43+21+64 = 156 个）
insert into public.groups (cohort_id, name, meeting_day)
select c.cid, 'Group ' || g, c.day
from (values
  ('00000000-0000-0000-0000-0000000060a0'::uuid, 28, 'Monday'),
  ('00000000-0000-0000-0000-0000000060b0'::uuid, 43, 'Tuesday'),
  ('00000000-0000-0000-0000-0000000070a0'::uuid, 21, 'Tuesday'),
  ('00000000-0000-0000-0000-0000000070b0'::uuid, 64, 'Monday')
) as c(cid, n, day)
cross join lateral generate_series(1, c.n) as g
on conflict (cohort_id, name) do nothing;


-- ===== 20260618100000_phase4_scheduling.sql =====
-- Phase 4：每周可用性提醒 + 补位调度（数据库层）
-- 站内通知/可用性/补位全部用 SQL 函数实现，由 pg_cron 定时调用（见 pg_cron_setup.sql）。
-- 短信由可选的 Edge Function 处理（见 supabase/functions/）。

-- ============================== 应用设置（单行）==============================
create table if not exists public.app_settings (
  id                boolean primary key default true,
  reminders_enabled boolean not null default true,
  term_break_start  date,
  term_break_end    date,
  updated_at        timestamptz not null default now(),
  constraint app_settings_singleton check (id)
);
insert into public.app_settings (id) values (true) on conflict (id) do nothing;

alter table public.app_settings enable row level security;

create policy "app_settings_read_auth" on public.app_settings
  for select to authenticated using (true);
create policy "app_settings_admin_write" on public.app_settings
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ============================== 辅助：下周一日期 ==============================
create or replace function public.next_week_monday()
returns date
language sql
stable
set search_path = ''
as $$
  select (date_trunc('week', now()) + interval '7 days')::date;
$$;

-- ============================== 每周可用性检查 ==============================
-- 为每位志愿者创建下周 availability(null) + weekly_check 站内通知。
-- 跳过 term break；可被 pg_cron(无 auth 上下文) 或管理员手动调用。
create or replace function public.run_weekly_availability_check()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  wk date := public.next_week_monday();
  s  public.app_settings;
  n  integer := 0;
begin
  -- 手动触发限管理员；cron（auth.uid() 为 null）放行
  if (select auth.uid()) is not null and not public.is_admin() then
    raise exception '只有管理员可手动运行';
  end if;

  select * into s from public.app_settings where id;
  if s.reminders_enabled is distinct from true then
    return 0;
  end if;
  -- 下周落在 term break 内 → 不提醒
  if s.term_break_start is not null and s.term_break_end is not null
     and wk between s.term_break_start and s.term_break_end then
    return 0;
  end if;

  insert into public.availability (volunteer_id, week_start_date, is_available)
  select p.id, wk, null
  from public.profiles p
  where p.role = 'volunteer'
  on conflict (volunteer_id, week_start_date) do nothing;

  insert into public.notifications (recipient_id, type, title, body)
  select p.id, 'weekly_check', 'Are you available next week?',
         'Please confirm whether you can supervise during the week of '
           || to_char(wk, 'YYYY-MM-DD') || '.'
  from public.profiles p
  where p.role = 'volunteer';

  get diagnostics n = row_count;
  return n;
end;
$$;

-- ============================== 汇总缺人 + 补位征集 ==============================
-- 找出下周不可用志愿者负责的小组 → 建 open 补位请求 → 给全体志愿者推通知。
create or replace function public.run_summarize_coverage()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  wk date := public.next_week_monday();
  n  integer := 0;
begin
  if (select auth.uid()) is not null and not public.is_admin() then
    raise exception '只有管理员可手动运行';
  end if;

  insert into public.coverage_requests (group_id, week_start_date, reason, status)
  select distinct a.group_id, wk, 'Assigned volunteer unavailable', 'open'
  from public.availability av
  join public.assignments a on a.volunteer_id = av.volunteer_id
  where av.week_start_date = wk and av.is_available = false
  on conflict (group_id, week_start_date) do nothing;

  if exists (
    select 1 from public.coverage_requests
    where week_start_date = wk and status = 'open'
  ) then
    insert into public.notifications (recipient_id, type, title, body)
    select p.id, 'coverage_request', 'Coverage needed',
           'Some groups need coverage for the week of '
             || to_char(wk, 'YYYY-MM-DD') || '. Can you help?'
    from public.profiles p
    where p.role = 'volunteer';
  end if;

  select count(*) into n
  from public.coverage_requests
  where week_start_date = wk and status = 'open';
  return n;
end;
$$;

-- ============================== 志愿者认领补位 ==============================
-- 原子操作：open → covered（记录认领人）+ 建立临时分配。
create or replace function public.claim_coverage(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  req public.coverage_requests;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  select * into req from public.coverage_requests where id = p_request_id for update;
  if not found then
    raise exception 'Coverage request not found';
  end if;
  if req.status <> 'open' then
    raise exception 'This request is already covered';
  end if;

  update public.coverage_requests
    set status = 'covered', covered_by = uid
    where id = p_request_id;

  insert into public.assignments (group_id, volunteer_id)
    values (req.group_id, uid)
    on conflict (group_id, volunteer_id) do nothing;
end;
$$;

-- ============================== 授权 ==============================
-- 内部已做角色校验：手动触发限管理员、认领需登录。
grant execute on function public.run_weekly_availability_check() to authenticated;
grant execute on function public.run_summarize_coverage() to authenticated;
grant execute on function public.claim_coverage(uuid) to authenticated;


-- ===== 20260618110000_email_reminders.sql =====
-- Phase 4：Email 提醒（pg_net + Resend，无需 Edge Function/CLI）
-- 站内通知不变；这里增加「发邮件」能力。
-- Resend 的 API key / 发件人 / App URL 存放在 Supabase Vault（见 email_setup.sql）。

-- pg_net（本地无此扩展时忽略，便于 Docker 校验函数逻辑）
do $$ begin
  execute 'create extension if not exists pg_net';
exception when others then
  raise notice 'pg_net not available here (ok for local test): %', sqlerrm;
end $$;

-- 通用发信：从 Vault 读 Resend 配置；未配置则跳过（不报错，站内通知照常）。
-- 不授予普通用户执行权限——仅供下面的 SECURITY DEFINER 函数内部调用。
create or replace function public.app_send_email(p_to text, p_subject text, p_html text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  api_key    text;
  from_email text;
begin
  select decrypted_secret into api_key    from vault.decrypted_secrets where name = 'resend_api_key';
  select decrypted_secret into from_email from vault.decrypted_secrets where name = 'resend_from_email';
  if api_key is null or from_email is null or p_to is null then
    return; -- 未配置 Resend → 跳过发信
  end if;
  perform net.http_post(
    url     := 'https://api.resend.com/emails',
    headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'),
    body    := jsonb_build_object('from', from_email, 'to', p_to, 'subject', p_subject, 'html', p_html)
  );
end;
$$;

-- ---------- 重建 run_weekly_availability_check：新增 p_send_email ----------
-- 默认 false：管理员手动「Run now」只建站内通知、不发邮件；cron 传 true 才发邮件。
drop function if exists public.run_weekly_availability_check();
create or replace function public.run_weekly_availability_check(p_send_email boolean default false)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  wk      date := public.next_week_monday();
  s       public.app_settings;
  n       integer := 0;
  app_url text;
  r       record;
begin
  if (select auth.uid()) is not null and not public.is_admin() then
    raise exception '只有管理员可手动运行';
  end if;

  select * into s from public.app_settings where id;
  if s.reminders_enabled is distinct from true then return 0; end if;
  if s.term_break_start is not null and s.term_break_end is not null
     and wk between s.term_break_start and s.term_break_end then
    return 0;
  end if;

  insert into public.availability (volunteer_id, week_start_date, is_available)
  select p.id, wk, null from public.profiles p where p.role = 'volunteer'
  on conflict (volunteer_id, week_start_date) do nothing;

  insert into public.notifications (recipient_id, type, title, body)
  select p.id, 'weekly_check', 'Are you available next week?',
         'Please confirm whether you can supervise during the week of ' || to_char(wk, 'YYYY-MM-DD') || '.'
  from public.profiles p where p.role = 'volunteer';
  get diagnostics n = row_count;

  if p_send_email then
    select decrypted_secret into app_url from vault.decrypted_secrets where name = 'app_url';
    for r in
      select u.email, p.full_name from public.profiles p
      join auth.users u on u.id = p.id
      where p.role = 'volunteer' and u.email is not null
    loop
      perform public.app_send_email(
        r.email,
        'APIIS — Are you available next week?',
        '<p>Hi ' || coalesce(r.full_name, '') || ',</p>'
          || '<p>Please confirm whether you can supervise during the week of <b>'
          || to_char(wk, 'YYYY-MM-DD') || '</b>.</p>'
          || case when app_url is not null then '<p><a href="' || app_url || '">Open APIIS Volunteer</a></p>' else '' end
      );
    end loop;
  end if;

  return n;
end;
$$;

-- ---------- 重建 run_summarize_coverage：新增 p_send_email ----------
drop function if exists public.run_summarize_coverage();
create or replace function public.run_summarize_coverage(p_send_email boolean default false)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  wk       date := public.next_week_monday();
  n        integer := 0;
  app_url  text;
  r        record;
  has_open boolean;
begin
  if (select auth.uid()) is not null and not public.is_admin() then
    raise exception '只有管理员可手动运行';
  end if;

  insert into public.coverage_requests (group_id, week_start_date, reason, status)
  select distinct a.group_id, wk, 'Assigned volunteer unavailable', 'open'
  from public.availability av
  join public.assignments a on a.volunteer_id = av.volunteer_id
  where av.week_start_date = wk and av.is_available = false
  on conflict (group_id, week_start_date) do nothing;

  select exists (
    select 1 from public.coverage_requests where week_start_date = wk and status = 'open'
  ) into has_open;

  if has_open then
    insert into public.notifications (recipient_id, type, title, body)
    select p.id, 'coverage_request', 'Coverage needed',
           'Some groups need coverage for the week of ' || to_char(wk, 'YYYY-MM-DD') || '. Can you help?'
    from public.profiles p where p.role = 'volunteer';

    if p_send_email then
      select decrypted_secret into app_url from vault.decrypted_secrets where name = 'app_url';
      for r in
        select u.email, p.full_name from public.profiles p
        join auth.users u on u.id = p.id
        where p.role = 'volunteer' and u.email is not null
      loop
        perform public.app_send_email(
          r.email,
          'APIIS — Coverage needed',
          '<p>Hi ' || coalesce(r.full_name, '') || ',</p>'
            || '<p>Some groups need coverage for the week of <b>'
            || to_char(wk, 'YYYY-MM-DD') || '</b>. Can you help?</p>'
            || case when app_url is not null then '<p><a href="' || app_url || '">Open APIIS Volunteer</a></p>' else '' end
        );
      end loop;
    end if;
  end if;

  select count(*) into n from public.coverage_requests where week_start_date = wk and status = 'open';
  return n;
end;
$$;

grant execute on function public.run_weekly_availability_check(boolean) to authenticated;
grant execute on function public.run_summarize_coverage(boolean) to authenticated;


-- ===== 20260618120000_volunteer_activity.sql =====
-- Phase 5+：志愿者出席/活跃度报表（只读聚合，管理员专用）
-- 不新增录入数据：出席从「该志愿者填过的出勤记录」推导；补位从 coverage_requests.covered_by。

create or replace function public.admin_volunteer_activity()
returns table (
  volunteer_id      uuid,
  full_name         text,
  assigned_groups   bigint,
  sessions_recorded bigint, -- 推导出席：填过出勤的不同 (小组, 上课日) 数
  last_active       date,   -- 最近一次填出勤的日期
  coverage_count    bigint  -- 帮别人补位的次数
)
language sql
security definer
set search_path = ''
as $$
  select
    p.id,
    p.full_name,
    (select count(*) from public.assignments a where a.volunteer_id = p.id),
    (select count(distinct (ar.group_id, ar.session_date))
       from public.attendance_records ar where ar.volunteer_id = p.id),
    (select max(ar.session_date)
       from public.attendance_records ar where ar.volunteer_id = p.id),
    (select count(*) from public.coverage_requests cr where cr.covered_by = p.id)
  from public.profiles p
  where p.role = 'volunteer'
    and public.is_admin()   -- 非管理员调用返回空集
  order by p.full_name;
$$;

grant execute on function public.admin_volunteer_activity() to authenticated;


-- ===== 20260618130000_admin_create_volunteer.sql =====
-- Phase 5+：管理员创建志愿者账号（供 App 内「导入志愿者」调用）
-- SECURITY DEFINER + is_admin 守门；沿用 seed 的 auth.users + identities 建号方式。
-- search_path 含 extensions：crypt/gen_salt 在 Supabase(extensions) 与本地(public) 都能解析。

create or replace function public.admin_create_volunteer(
  p_email     text,
  p_full_name text,
  p_phone     text,
  p_password  text
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  uid uuid;
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;
  if p_email is null or btrim(p_email) = '' or p_password is null or p_password = '' then
    raise exception 'email and password are required';
  end if;
  if exists (select 1 from auth.users where lower(email) = lower(btrim(p_email))) then
    raise exception 'A user with email % already exists', p_email;
  end if;

  uid := gen_random_uuid();

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data, is_super_admin,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
    lower(btrim(p_email)), crypt(p_password, gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}',
    jsonb_build_object('full_name', coalesce(p_full_name, ''), 'role', 'volunteer', 'phone', p_phone),
    false, '', '', '', ''
  );

  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (
    gen_random_uuid(), uid, uid::text,
    jsonb_build_object('sub', uid::text, 'email', lower(btrim(p_email))),
    'email', now(), now(), now()
  );

  -- 触发器通常已建 profile；这里 upsert 确保姓名/电话/角色正确
  insert into public.profiles (id, full_name, role, phone)
  values (uid, coalesce(p_full_name, ''), 'volunteer', p_phone)
  on conflict (id) do update
    set full_name = excluded.full_name, role = 'volunteer', phone = excluded.phone;

  return uid;
end;
$$;

grant execute on function public.admin_create_volunteer(text, text, text, text) to authenticated;


-- ===== 20260618140000_student_email_unique.sql =====
-- 学生以 email 为唯一基准（姓名可能重名）。
-- 允许多个 NULL（历史/无邮箱数据），非空 email 唯一。
-- 注意：若已有重复的非空 email，加约束会失败 —— 需先人工去重再跑本迁移。

-- 统一小写，避免大小写造成的“假重复”
update public.students set email = lower(email)
 where email is not null and email <> lower(email);

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'students_email_unique') then
    alter table public.students add constraint students_email_unique unique (email);
  end if;
end $$;


-- ===== 20260618150000_volunteer_import_and_delete.sql =====
-- 志愿者：导入(可带小组分配，幂等) + 删除

-- 取代旧的 admin_create_volunteer
drop function if exists public.admin_create_volunteer(text, text, text, text);

-- 幂等导入：邮箱不存在则建号；已存在则复用并更新姓名/电话；可选地分配到某小组。
create or replace function public.admin_import_volunteer(
  p_email     text,
  p_full_name text,
  p_phone     text,
  p_password  text,
  p_group_id  uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  uid uuid;
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;
  if p_email is null or btrim(p_email) = '' then
    raise exception 'email is required';
  end if;

  select id into uid from auth.users where lower(email) = lower(btrim(p_email));

  if uid is null then
    if p_password is null or p_password = '' then
      raise exception 'password is required for a new volunteer';
    end if;
    uid := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data, is_super_admin,
      confirmation_token, recovery_token, email_change_token_new, email_change
    ) values (
      '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
      lower(btrim(p_email)), crypt(p_password, gen_salt('bf')),
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}',
      jsonb_build_object('full_name', coalesce(p_full_name, ''), 'role', 'volunteer', 'phone', p_phone),
      false, '', '', '', ''
    );
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), uid, uid::text,
            jsonb_build_object('sub', uid::text, 'email', lower(btrim(p_email))), 'email', now(), now(), now());
  end if;

  insert into public.profiles (id, full_name, role, phone)
  values (uid, coalesce(p_full_name, ''), 'volunteer', p_phone)
  on conflict (id) do update
    set full_name = excluded.full_name, role = 'volunteer', phone = excluded.phone;

  if p_group_id is not null then
    insert into public.assignments (group_id, volunteer_id)
    values (p_group_id, uid)
    on conflict (group_id, volunteer_id) do nothing;
  end if;

  return uid;
end;
$$;

-- 删除志愿者：删 auth.users → 级联删 profile/assignments/availability/notifications；
-- attendance/coverage 的引用置空。仅限删志愿者（不可删管理员）。
create or replace function public.admin_delete_volunteer(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;
  if not exists (select 1 from public.profiles where id = p_id and role = 'volunteer') then
    raise exception 'Not a volunteer';
  end if;
  delete from auth.users where id = p_id;
end;
$$;

grant execute on function public.admin_import_volunteer(text, text, text, text, uuid) to authenticated;
grant execute on function public.admin_delete_volunteer(uuid) to authenticated;


-- ===== 20260618160000_role_management.sql =====
-- 角色管理：放宽 guard_profile_role —— 仅拦截「已登录的非管理员」改 role。
-- 无 auth 上下文（SQL Editor / service_role / cron 等可信场景）允许改 role，
-- 以便用 SQL 给首个/超级管理员 bootstrap，且不影响 App 内的安全（登录的志愿者仍被拦）。

create or replace function public.guard_profile_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.role is distinct from old.role)
     and (select auth.uid()) is not null
     and not public.is_admin() then
    raise exception '只有管理员可以修改角色 (role)';
  end if;
  return new;
end;
$$;


-- ===== 20260618170000_user_management.sql =====
-- 用户管理：列表返回全部用户(志愿者+管理员)并带 role；删除可针对任意非自己用户。
-- 这样提升为管理员后仍可在列表里管理（降级/删除）。

-- 活跃度/列表：返回所有用户 + role（之前只返回 volunteer）
-- 返回类型变了，需先 drop 再建。
drop function if exists public.admin_volunteer_activity();
create or replace function public.admin_volunteer_activity()
returns table (
  volunteer_id      uuid,
  full_name         text,
  role              text,
  assigned_groups   bigint,
  sessions_recorded bigint,
  last_active       date,
  coverage_count    bigint
)
language sql
security definer
set search_path = ''
as $$
  select
    p.id,
    p.full_name,
    p.role,
    (select count(*) from public.assignments a where a.volunteer_id = p.id),
    (select count(distinct (ar.group_id, ar.session_date))
       from public.attendance_records ar where ar.volunteer_id = p.id),
    (select max(ar.session_date)
       from public.attendance_records ar where ar.volunteer_id = p.id),
    (select count(*) from public.coverage_requests cr where cr.covered_by = p.id)
  from public.profiles p
  where public.is_admin()
  order by p.full_name;
$$;

-- 删除用户：可删任意用户，但不能删自己（防止自锁）。
create or replace function public.admin_delete_volunteer(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;
  if p_id = (select auth.uid()) then
    raise exception 'You cannot delete your own account';
  end if;
  if not exists (select 1 from public.profiles where id = p_id) then
    raise exception 'User not found';
  end if;
  delete from auth.users where id = p_id;
end;
$$;

grant execute on function public.admin_volunteer_activity() to authenticated;
grant execute on function public.admin_delete_volunteer(uuid) to authenticated;


-- ===== 20260619090000_super_admin.sql =====
-- 三级角色：super_admin > admin > volunteer
--   super_admin：可任命/撤销 admin、删 admin 与 volunteer；不可被他人删/降级。
--   admin：日常管理 + 只能删 volunteer；不能改任何人角色、不能删 admin/super_admin。
-- is_admin() 同时认 admin 与 super_admin（现有 RLS/权限无需改动）。
-- 取代之前的 protected 方案。

-- 1) 先移除依赖 protected 的旧列表函数，再删列
drop function if exists public.admin_volunteer_activity();
alter table public.profiles drop column if exists protected;

-- 2) 角色取值放开到三种
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check check (role in ('super_admin', 'admin', 'volunteer'));

-- 3) is_admin 同时认 admin / super_admin
create or replace function public.is_admin()
returns boolean language sql security definer stable set search_path = '' as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role in ('admin', 'super_admin')
  );
$$;

-- 4) is_super_admin
create or replace function public.is_super_admin()
returns boolean language sql security definer stable set search_path = '' as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'super_admin'
  );
$$;
grant execute on function public.is_super_admin() to anon, authenticated;

-- 5) 角色守卫：仅 super_admin（或无 auth 的可信上下文）可改角色
create or replace function public.guard_profile_role()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (new.role is distinct from old.role)
     and (select auth.uid()) is not null
     and not public.is_super_admin() then
    raise exception '只有超级管理员可以修改角色 (role)';
  end if;
  return new;
end;
$$;

-- 6) 删除：admin 只能删 volunteer；super_admin 可删 admin/volunteer；任何人不可删 super_admin / 自己
create or replace function public.admin_delete_volunteer(p_id uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  target_role text;
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;
  if p_id = (select auth.uid()) then
    raise exception 'You cannot delete your own account';
  end if;
  select role into target_role from public.profiles where id = p_id;
  if target_role is null then
    raise exception 'User not found';
  end if;
  if target_role = 'super_admin' then
    raise exception 'A super admin cannot be deleted here';
  end if;
  if target_role = 'admin' and not public.is_super_admin() then
    raise exception 'Only a super admin can delete an admin';
  end if;
  delete from auth.users where id = p_id;
end;
$$;

-- 7) 重建列表函数（返回 role；不再有 protected）
create or replace function public.admin_volunteer_activity()
returns table (
  volunteer_id      uuid,
  full_name         text,
  role              text,
  assigned_groups   bigint,
  sessions_recorded bigint,
  last_active       date,
  coverage_count    bigint
)
language sql security definer set search_path = '' as $$
  select
    p.id, p.full_name, p.role,
    (select count(*) from public.assignments a where a.volunteer_id = p.id),
    (select count(distinct (ar.group_id, ar.session_date))
       from public.attendance_records ar where ar.volunteer_id = p.id),
    (select max(ar.session_date) from public.attendance_records ar where ar.volunteer_id = p.id),
    (select count(*) from public.coverage_requests cr where cr.covered_by = p.id)
  from public.profiles p
  where public.is_admin()
  order by p.full_name;
$$;
grant execute on function public.admin_volunteer_activity() to authenticated;

-- 8) 把 itsupport@apiis.org 设为 super_admin
update public.profiles p set role = 'super_admin'
from auth.users u
where u.id = p.id and lower(u.email) = 'itsupport@apiis.org';

-- ── 20260619100000_volunteer_email：志愿者列表增加 email 列（join auth.users） ──
drop function if exists public.admin_volunteer_activity();
create or replace function public.admin_volunteer_activity()
returns table (
  volunteer_id      uuid,
  full_name         text,
  email             text,
  role              text,
  assigned_groups   bigint,
  sessions_recorded bigint,
  last_active       date,
  coverage_count    bigint
)
language sql security definer set search_path = '' as $$
  select
    p.id, p.full_name, u.email::text, p.role,
    (select count(*) from public.assignments a where a.volunteer_id = p.id),
    (select count(distinct (ar.group_id, ar.session_date))
       from public.attendance_records ar where ar.volunteer_id = p.id),
    (select max(ar.session_date) from public.attendance_records ar where ar.volunteer_id = p.id),
    (select count(*) from public.coverage_requests cr where cr.covered_by = p.id)
  from public.profiles p
  join auth.users u on u.id = p.id
  where public.is_admin()
  order by p.full_name;
$$;
grant execute on function public.admin_volunteer_activity() to authenticated;




-- ===== 20260619110000_calendar_sessions：课程日历 + 提醒按日历跳过 break =====
-- 课程日历（按 Excel 排课表）：每套课程 0~66 周的上课日期。
-- 提醒系统据此判断「下周一是否真实上课日」，自动跳过所有 term break。

create table if not exists public.class_sessions (
  curriculum   text not null,
  week         int  not null,
  session_date date not null,
  primary key (curriculum, week),
  unique (curriculum, session_date)
);
create index if not exists class_sessions_date_idx on public.class_sessions (session_date);

alter table public.class_sessions enable row level security;
drop policy if exists "class_sessions_read_auth" on public.class_sessions;
create policy "class_sessions_read_auth" on public.class_sessions
  for select to authenticated using (true);
drop policy if exists "class_sessions_admin_write" on public.class_sessions;
create policy "class_sessions_admin_write" on public.class_sessions
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

insert into public.class_sessions (curriculum, week, session_date) values
  ('MMin 6', 0, '2025-02-03'),
  ('MMin 6', 1, '2025-02-10'),
  ('MMin 6', 2, '2025-02-17'),
  ('MMin 6', 3, '2025-02-24'),
  ('MMin 6', 4, '2025-03-03'),
  ('MMin 6', 5, '2025-03-10'),
  ('MMin 6', 6, '2025-03-17'),
  ('MMin 6', 7, '2025-03-24'),
  ('MMin 6', 8, '2025-04-07'),
  ('MMin 6', 9, '2025-04-14'),
  ('MMin 6', 10, '2025-04-21'),
  ('MMin 6', 11, '2025-04-28'),
  ('MMin 6', 12, '2025-05-05'),
  ('MMin 6', 13, '2025-05-12'),
  ('MMin 6', 14, '2025-05-19'),
  ('MMin 6', 15, '2025-05-26'),
  ('MMin 6', 16, '2025-06-02'),
  ('MMin 6', 17, '2025-06-09'),
  ('MMin 6', 18, '2025-06-30'),
  ('MMin 6', 19, '2025-07-07'),
  ('MMin 6', 20, '2025-07-14'),
  ('MMin 6', 21, '2025-07-21'),
  ('MMin 6', 22, '2025-07-28'),
  ('MMin 6', 23, '2025-08-04'),
  ('MMin 6', 24, '2025-08-11'),
  ('MMin 6', 25, '2025-08-18'),
  ('MMin 6', 26, '2025-08-25'),
  ('MMin 6', 27, '2025-09-01'),
  ('MMin 6', 28, '2025-09-22'),
  ('MMin 6', 29, '2025-09-29'),
  ('MMin 6', 30, '2025-10-06'),
  ('MMin 6', 31, '2025-10-13'),
  ('MMin 6', 32, '2025-10-20'),
  ('MMin 6', 33, '2025-10-27'),
  ('MMin 6', 34, '2025-11-03'),
  ('MMin 6', 35, '2026-02-09'),
  ('MMin 6', 36, '2026-02-16'),
  ('MMin 6', 37, '2026-02-23'),
  ('MMin 6', 38, '2026-03-02'),
  ('MMin 6', 39, '2026-03-09'),
  ('MMin 6', 40, '2026-03-16'),
  ('MMin 6', 41, '2026-03-23'),
  ('MMin 6', 42, '2026-04-13'),
  ('MMin 6', 43, '2026-04-20'),
  ('MMin 6', 44, '2026-04-27'),
  ('MMin 6', 45, '2026-05-04'),
  ('MMin 6', 46, '2026-05-11'),
  ('MMin 6', 47, '2026-05-18'),
  ('MMin 6', 48, '2026-05-25'),
  ('MMin 6', 49, '2026-06-01'),
  ('MMin 6', 50, '2026-06-08'),
  ('MMin 6', 51, '2026-06-29'),
  ('MMin 6', 52, '2026-07-06'),
  ('MMin 6', 53, '2026-07-13'),
  ('MMin 6', 54, '2026-07-20'),
  ('MMin 6', 55, '2026-07-27'),
  ('MMin 6', 56, '2026-08-03'),
  ('MMin 6', 57, '2026-08-10'),
  ('MMin 6', 58, '2026-08-17'),
  ('MMin 6', 59, '2026-08-24'),
  ('MMin 6', 60, '2026-09-14'),
  ('MMin 6', 61, '2026-09-21'),
  ('MMin 6', 62, '2026-09-28'),
  ('MMin 6', 63, '2026-10-05'),
  ('MMin 6', 64, '2026-10-12'),
  ('MMin 6', 65, '2026-10-19'),
  ('MMin 6', 66, '2026-10-26'),
  ('MMin 7', 0, '2026-02-02'),
  ('MMin 7', 1, '2026-02-09'),
  ('MMin 7', 2, '2026-02-16'),
  ('MMin 7', 3, '2026-02-23'),
  ('MMin 7', 4, '2026-03-02'),
  ('MMin 7', 5, '2026-03-09'),
  ('MMin 7', 6, '2026-03-16'),
  ('MMin 7', 7, '2026-03-23'),
  ('MMin 7', 8, '2026-04-13'),
  ('MMin 7', 9, '2026-04-20'),
  ('MMin 7', 10, '2026-04-27'),
  ('MMin 7', 11, '2026-05-04'),
  ('MMin 7', 12, '2026-05-11'),
  ('MMin 7', 13, '2026-05-18'),
  ('MMin 7', 14, '2026-05-25'),
  ('MMin 7', 15, '2026-06-01'),
  ('MMin 7', 16, '2026-06-08'),
  ('MMin 7', 17, '2026-06-29'),
  ('MMin 7', 18, '2026-07-06'),
  ('MMin 7', 19, '2026-07-13'),
  ('MMin 7', 20, '2026-07-20'),
  ('MMin 7', 21, '2026-07-27'),
  ('MMin 7', 22, '2026-08-03'),
  ('MMin 7', 23, '2026-08-10'),
  ('MMin 7', 24, '2026-08-17'),
  ('MMin 7', 25, '2026-08-24'),
  ('MMin 7', 26, '2026-09-14'),
  ('MMin 7', 27, '2026-09-21'),
  ('MMin 7', 28, '2026-09-28'),
  ('MMin 7', 29, '2026-10-05'),
  ('MMin 7', 30, '2026-10-12'),
  ('MMin 7', 31, '2026-10-19'),
  ('MMin 7', 32, '2026-10-26'),
  ('MMin 7', 33, '2027-02-08'),
  ('MMin 7', 34, '2027-02-15'),
  ('MMin 7', 35, '2027-02-22'),
  ('MMin 7', 36, '2027-03-01'),
  ('MMin 7', 37, '2027-03-08'),
  ('MMin 7', 38, '2027-03-15'),
  ('MMin 7', 39, '2027-03-22'),
  ('MMin 7', 40, '2027-03-29'),
  ('MMin 7', 41, '2027-04-12'),
  ('MMin 7', 42, '2027-04-19'),
  ('MMin 7', 43, '2027-04-26'),
  ('MMin 7', 44, '2027-05-03'),
  ('MMin 7', 45, '2027-05-10'),
  ('MMin 7', 46, '2027-05-17'),
  ('MMin 7', 47, '2027-05-24'),
  ('MMin 7', 48, '2027-05-31'),
  ('MMin 7', 49, '2027-06-07'),
  ('MMin 7', 50, '2027-06-21'),
  ('MMin 7', 51, '2027-06-28'),
  ('MMin 7', 52, '2027-07-05'),
  ('MMin 7', 53, '2027-07-12'),
  ('MMin 7', 54, '2027-07-19'),
  ('MMin 7', 55, '2027-07-26'),
  ('MMin 7', 56, '2027-08-02'),
  ('MMin 7', 57, '2027-08-09'),
  ('MMin 7', 58, '2027-08-16'),
  ('MMin 7', 59, '2027-08-23'),
  ('MMin 7', 60, '2027-08-30'),
  ('MMin 7', 61, '2027-09-06'),
  ('MMin 7', 62, '2027-09-20'),
  ('MMin 7', 63, '2027-09-27'),
  ('MMin 7', 64, '2027-10-04'),
  ('MMin 7', 65, '2027-10-11'),
  ('MMin 7', 66, '2027-10-18')
on conflict (curriculum, week) do update set session_date = excluded.session_date;

-- ---------- 提醒函数：用「下周一是否上课日」取代单一 term_break 判断 ----------
drop function if exists public.run_weekly_availability_check(boolean);
create or replace function public.run_weekly_availability_check(p_send_email boolean default false)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  wk      date := public.next_week_monday();
  s       public.app_settings;
  n       integer := 0;
  app_url text;
  r       record;
begin
  if (select auth.uid()) is not null and not public.is_admin() then
    raise exception '只有管理员可手动运行';
  end if;

  select * into s from public.app_settings where id;
  if s.reminders_enabled is distinct from true then return 0; end if;
  -- 下周一不是任何课程的真实上课日 → 跳过（自动覆盖所有 break）
  if not exists (select 1 from public.class_sessions where session_date = wk) then
    return 0;
  end if;

  insert into public.availability (volunteer_id, week_start_date, is_available)
  select p.id, wk, null from public.profiles p where p.role = 'volunteer'
  on conflict (volunteer_id, week_start_date) do nothing;

  insert into public.notifications (recipient_id, type, title, body)
  select p.id, 'weekly_check', 'Are you available next week?',
         'Please confirm whether you can supervise during the week of ' || to_char(wk, 'YYYY-MM-DD') || '.'
  from public.profiles p where p.role = 'volunteer';
  get diagnostics n = row_count;

  if p_send_email then
    select decrypted_secret into app_url from vault.decrypted_secrets where name = 'app_url';
    for r in
      select u.email, p.full_name from public.profiles p
      join auth.users u on u.id = p.id
      where p.role = 'volunteer' and u.email is not null
    loop
      perform public.app_send_email(
        r.email,
        'APIIS — Are you available next week?',
        '<p>Hi ' || coalesce(r.full_name, '') || ',</p>'
          || '<p>Please confirm whether you can supervise during the week of <b>'
          || to_char(wk, 'YYYY-MM-DD') || '</b>.</p>'
          || case when app_url is not null then '<p><a href="' || app_url || '">Open APIIS Volunteer</a></p>' else '' end
      );
    end loop;
  end if;

  return n;
end;
$$;

drop function if exists public.run_summarize_coverage(boolean);
create or replace function public.run_summarize_coverage(p_send_email boolean default false)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  wk       date := public.next_week_monday();
  n        integer := 0;
  app_url  text;
  r        record;
  has_open boolean;
begin
  if (select auth.uid()) is not null and not public.is_admin() then
    raise exception '只有管理员可手动运行';
  end if;

  -- 下周一不是上课日 → 不生成补位请求
  if not exists (select 1 from public.class_sessions where session_date = wk) then
    return 0;
  end if;

  insert into public.coverage_requests (group_id, week_start_date, reason, status)
  select distinct a.group_id, wk, 'Assigned volunteer unavailable', 'open'
  from public.availability av
  join public.assignments a on a.volunteer_id = av.volunteer_id
  where av.week_start_date = wk and av.is_available = false
  on conflict (group_id, week_start_date) do nothing;

  select exists (
    select 1 from public.coverage_requests where week_start_date = wk and status = 'open'
  ) into has_open;

  if has_open then
    insert into public.notifications (recipient_id, type, title, body)
    select p.id, 'coverage_request', 'Coverage needed',
           'Some groups need coverage for the week of ' || to_char(wk, 'YYYY-MM-DD') || '. Can you help?'
    from public.profiles p where p.role = 'volunteer';

    if p_send_email then
      select decrypted_secret into app_url from vault.decrypted_secrets where name = 'app_url';
      for r in
        select u.email, p.full_name from public.profiles p
        join auth.users u on u.id = p.id
        where p.role = 'volunteer' and u.email is not null
      loop
        perform public.app_send_email(
          r.email,
          'APIIS — Coverage needed',
          '<p>Hi ' || coalesce(r.full_name, '') || ',</p>'
            || '<p>Some groups need coverage for the week of <b>'
            || to_char(wk, 'YYYY-MM-DD') || '</b>. Can you help?</p>'
            || case when app_url is not null then '<p><a href="' || app_url || '">Open APIIS Volunteer</a></p>' else '' end
        );
      end loop;
    end if;
  end if;

  select count(*) into n from public.coverage_requests where week_start_date = wk and status = 'open';
  return n;
end;
$$;

grant execute on function public.run_weekly_availability_check(boolean) to authenticated;
grant execute on function public.run_summarize_coverage(boolean) to authenticated;


-- ===== 20260620090000_student_pii：志愿者只能读学员姓名（email 收归管理员） =====
-- 学员 PII：志愿者不再能直接读取 students 表（其中含 email）。
-- 管理员仍可全权读写（students_admin_write 是 for all，已覆盖 SELECT）；
-- 志愿者改为通过 get_group_students() 只拿到「id + 姓名」，且仅限自己被分配的小组。

-- 1) 移除志愿者对 students 的直接读权限（删除「assigned_or_admin」select 策略）
drop policy if exists "students_select_assigned_or_admin" on public.students;

-- 2) 只返回姓名的安全函数：管理员或该组成员可调用；email 永不出库到志愿者端
create or replace function public.get_group_students(p_group_id uuid)
returns table (id uuid, full_name text)
language sql security definer set search_path = '' as $$
  select s.id, s.full_name
  from public.students s
  where s.group_id = p_group_id
    and (public.is_admin() or public.is_assigned_to_group(p_group_id))
  order by s.full_name;
$$;
grant execute on function public.get_group_students(uuid) to authenticated;


-- ===== 20260620100000_super_admin_manage_people：导入/删除学生与志愿者仅限 super_admin =====
-- 只有 super_admin 可以「上传(导入)/删除」学生与志愿者。
-- admin 仍可：查看报表/导出、管理小组分配、记考勤、查看名单——但不能导入或删除人。

-- ===== students：写操作(insert/update/delete)收归 super_admin；读保留给 admin =====
-- 说明：select 给 admin（报表/导出需要）；FOR ALL 的 super 策略覆盖增删改。
drop policy if exists "students_admin_write" on public.students;
drop policy if exists "students_select_admin" on public.students;
drop policy if exists "students_all_super" on public.students;

create policy "students_select_admin" on public.students
  for select to authenticated using (public.is_admin());
create policy "students_all_super" on public.students
  for all to authenticated using (public.is_super_admin()) with check (public.is_super_admin());

-- ===== 志愿者导入：super_admin only =====
create or replace function public.admin_import_volunteer(
  p_email     text,
  p_full_name text,
  p_phone     text,
  p_password  text,
  p_group_id  uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  uid uuid;
begin
  if not public.is_super_admin() then
    raise exception 'Super admin only';
  end if;
  if p_email is null or btrim(p_email) = '' then
    raise exception 'email is required';
  end if;

  select id into uid from auth.users where lower(email) = lower(btrim(p_email));

  if uid is null then
    if p_password is null or p_password = '' then
      raise exception 'password is required for a new volunteer';
    end if;
    uid := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data, is_super_admin,
      confirmation_token, recovery_token, email_change_token_new, email_change
    ) values (
      '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
      lower(btrim(p_email)), crypt(p_password, gen_salt('bf')),
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}',
      jsonb_build_object('full_name', coalesce(p_full_name, ''), 'role', 'volunteer', 'phone', p_phone),
      false, '', '', '', ''
    );
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), uid, uid::text,
            jsonb_build_object('sub', uid::text, 'email', lower(btrim(p_email))), 'email', now(), now(), now());
  end if;

  insert into public.profiles (id, full_name, role, phone)
  values (uid, coalesce(p_full_name, ''), 'volunteer', p_phone)
  on conflict (id) do update
    set full_name = excluded.full_name, role = 'volunteer', phone = excluded.phone;

  if p_group_id is not null then
    insert into public.assignments (group_id, volunteer_id)
    values (p_group_id, uid)
    on conflict (group_id, volunteer_id) do nothing;
  end if;

  return uid;
end;
$$;

-- ===== 志愿者删除：super_admin only（仍禁止删自己 / 删 super_admin）=====
create or replace function public.admin_delete_volunteer(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  target_role text;
begin
  if not public.is_super_admin() then
    raise exception 'Super admin only';
  end if;
  if p_id = (select auth.uid()) then
    raise exception 'You cannot delete your own account';
  end if;
  select role into target_role from public.profiles where id = p_id;
  if target_role is null then
    raise exception 'User not found';
  end if;
  if target_role = 'super_admin' then
    raise exception 'A super admin cannot be deleted here';
  end if;
  delete from auth.users where id = p_id;
end;
$$;

grant execute on function public.admin_import_volunteer(text, text, text, text, uuid) to authenticated;
grant execute on function public.admin_delete_volunteer(uuid) to authenticated;


-- ===== 20260620110000_per_curriculum_reminders：提醒按课程(MMin 6/7)分发 =====
-- 提醒按课程(MMin 6 / MMin 7)分发：新增 p_curriculum 参数。
--   p_curriculum 为 null  → 全部志愿者(手动 "Run now" 用,行为不变)
--   p_curriculum = 'MMin 6' / 'MMin 7' → 只通知/发给被分配到该课程班级的志愿者，
--     且按「该课程」自己的上课周判断(两套课程休息周不同)。
-- cron 改为 4 个任务，见 pg_cron_setup.sql（或本文件末尾的重排程段）。

drop function if exists public.run_weekly_availability_check(boolean);
drop function if exists public.run_weekly_availability_check();
create or replace function public.run_weekly_availability_check(
  p_send_email boolean default false,
  p_curriculum text default null
)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  wk      date := public.next_week_monday();
  s       public.app_settings;
  n       integer := 0;
  app_url text;
  r       record;
begin
  if (select auth.uid()) is not null and not public.is_admin() then
    raise exception '只有管理员可手动运行';
  end if;

  select * into s from public.app_settings where id;
  if s.reminders_enabled is distinct from true then return 0; end if;

  -- 下周一对（指定课程 / 任意课程）是否真实上课日；否则跳过
  if not exists (
    select 1 from public.class_sessions
    where session_date = wk and (p_curriculum is null or curriculum = p_curriculum)
  ) then
    return 0;
  end if;

  insert into public.availability (volunteer_id, week_start_date, is_available)
  select p.id, wk, null
  from public.profiles p
  where p.role = 'volunteer'
    and (p_curriculum is null or exists (
      select 1 from public.assignments a
      join public.groups g on g.id = a.group_id
      join public.cohorts c on c.id = g.cohort_id
      where a.volunteer_id = p.id and c.name like p_curriculum || '%'
    ))
  on conflict (volunteer_id, week_start_date) do nothing;

  insert into public.notifications (recipient_id, type, title, body)
  select p.id, 'weekly_check', 'Are you available next week?',
         'Please confirm whether you can supervise during the week of ' || to_char(wk, 'YYYY-MM-DD') || '.'
  from public.profiles p
  where p.role = 'volunteer'
    and (p_curriculum is null or exists (
      select 1 from public.assignments a
      join public.groups g on g.id = a.group_id
      join public.cohorts c on c.id = g.cohort_id
      where a.volunteer_id = p.id and c.name like p_curriculum || '%'
    ));
  get diagnostics n = row_count;

  if p_send_email then
    select decrypted_secret into app_url from vault.decrypted_secrets where name = 'app_url';
    for r in
      select u.email, p.full_name
      from public.profiles p
      join auth.users u on u.id = p.id
      where p.role = 'volunteer' and u.email is not null
        and (p_curriculum is null or exists (
          select 1 from public.assignments a
          join public.groups g on g.id = a.group_id
          join public.cohorts c on c.id = g.cohort_id
          where a.volunteer_id = p.id and c.name like p_curriculum || '%'
        ))
    loop
      perform public.app_send_email(
        r.email,
        'APIIS — Are you available next week?',
        '<p>Hi ' || coalesce(r.full_name, '') || ',</p>'
          || '<p>Please confirm whether you can supervise during the week of <b>'
          || to_char(wk, 'YYYY-MM-DD') || '</b>.</p>'
          || case when app_url is not null then '<p><a href="' || app_url || '">Open APIIS Volunteer</a></p>' else '' end
      );
    end loop;
  end if;

  return n;
end;
$$;

drop function if exists public.run_summarize_coverage(boolean);
drop function if exists public.run_summarize_coverage();
create or replace function public.run_summarize_coverage(
  p_send_email boolean default false,
  p_curriculum text default null
)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  wk       date := public.next_week_monday();
  n        integer := 0;
  app_url  text;
  r        record;
  has_open boolean;
begin
  if (select auth.uid()) is not null and not public.is_admin() then
    raise exception '只有管理员可手动运行';
  end if;

  if not exists (
    select 1 from public.class_sessions
    where session_date = wk and (p_curriculum is null or curriculum = p_curriculum)
  ) then
    return 0;
  end if;

  -- 为「该课程中、被分配志愿者本周不可用」的小组建补位请求
  insert into public.coverage_requests (group_id, week_start_date, reason, status)
  select distinct a.group_id, wk, 'Assigned volunteer unavailable', 'open'
  from public.availability av
  join public.assignments a on a.volunteer_id = av.volunteer_id
  join public.groups g on g.id = a.group_id
  join public.cohorts c on c.id = g.cohort_id
  where av.week_start_date = wk and av.is_available = false
    and (p_curriculum is null or c.name like p_curriculum || '%')
  on conflict (group_id, week_start_date) do nothing;

  select exists (
    select 1 from public.coverage_requests cr
    join public.groups g on g.id = cr.group_id
    join public.cohorts c on c.id = g.cohort_id
    where cr.week_start_date = wk and cr.status = 'open'
      and (p_curriculum is null or c.name like p_curriculum || '%')
  ) into has_open;

  if has_open then
    insert into public.notifications (recipient_id, type, title, body)
    select p.id, 'coverage_request', 'Coverage needed',
           'Some groups need coverage for the week of ' || to_char(wk, 'YYYY-MM-DD') || '. Can you help?'
    from public.profiles p
    where p.role = 'volunteer'
      and (p_curriculum is null or exists (
        select 1 from public.assignments a
        join public.groups g on g.id = a.group_id
        join public.cohorts c on c.id = g.cohort_id
        where a.volunteer_id = p.id and c.name like p_curriculum || '%'
      ));

    if p_send_email then
      select decrypted_secret into app_url from vault.decrypted_secrets where name = 'app_url';
      for r in
        select u.email, p.full_name
        from public.profiles p
        join auth.users u on u.id = p.id
        where p.role = 'volunteer' and u.email is not null
          and (p_curriculum is null or exists (
            select 1 from public.assignments a
            join public.groups g on g.id = a.group_id
            join public.cohorts c on c.id = g.cohort_id
            where a.volunteer_id = p.id and c.name like p_curriculum || '%'
          ))
      loop
        perform public.app_send_email(
          r.email,
          'APIIS — Coverage needed',
          '<p>Hi ' || coalesce(r.full_name, '') || ',</p>'
            || '<p>Some groups need coverage for the week of <b>'
            || to_char(wk, 'YYYY-MM-DD') || '</b>. Can you help?</p>'
            || case when app_url is not null then '<p><a href="' || app_url || '">Open APIIS Volunteer</a></p>' else '' end
        );
      end loop;
    end if;
  end if;

  select count(*) into n
  from public.coverage_requests cr
  join public.groups g on g.id = cr.group_id
  join public.cohorts c on c.id = g.cohort_id
  where cr.week_start_date = wk and cr.status = 'open'
    and (p_curriculum is null or c.name like p_curriculum || '%');
  return n;
end;
$$;

grant execute on function public.run_weekly_availability_check(boolean, text) to authenticated;
grant execute on function public.run_summarize_coverage(boolean, text) to authenticated;


-- ===== 20260620120000_coverage_broadcast：补位广播版(覆盖全部课程缺口,收件人按天分课程) =====
-- 补位「广播版」：补位请求覆盖全部课程(MMin 6 & 7)的缺口；
--   p_curriculum 现在只用于筛选「通知/邮件的收件人」(周六发 MMin 6 志愿者、周日发 MMin 7 志愿者)。
--   任何志愿者都能认领任何小组(跨课程互补),通知量摊到两天。
-- 注：run_weekly_availability_check(可用性)仍按课程分发，不在此文件改动。

create or replace function public.run_summarize_coverage(
  p_send_email boolean default false,
  p_curriculum text default null  -- 仅筛选收件人；补位请求始终覆盖全部课程
)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  wk       date := public.next_week_monday();
  n        integer := 0;
  app_url  text;
  r        record;
  has_open boolean;
begin
  if (select auth.uid()) is not null and not public.is_admin() then
    raise exception '只有管理员可手动运行';
  end if;

  -- 下周一对「任意课程」都不是上课日 → 跳过
  if not exists (select 1 from public.class_sessions where session_date = wk) then
    return 0;
  end if;

  -- 为「本周不可用志愿者所在的小组」建补位请求（全部课程，不按 p_curriculum 过滤）
  insert into public.coverage_requests (group_id, week_start_date, reason, status)
  select distinct a.group_id, wk, 'Assigned volunteer unavailable', 'open'
  from public.availability av
  join public.assignments a on a.volunteer_id = av.volunteer_id
  where av.week_start_date = wk and av.is_available = false
  on conflict (group_id, week_start_date) do nothing;

  -- 本周是否有任何 open 补位（全部课程）
  select exists (
    select 1 from public.coverage_requests where week_start_date = wk and status = 'open'
  ) into has_open;

  if has_open then
    -- 收件人：p_curriculum 为空=全部；否则=被分配到该课程班级的志愿者
    insert into public.notifications (recipient_id, type, title, body)
    select p.id, 'coverage_request', 'Coverage needed',
           'Some groups need coverage for the week of ' || to_char(wk, 'YYYY-MM-DD') || '. Can you help?'
    from public.profiles p
    where p.role = 'volunteer'
      and (p_curriculum is null or exists (
        select 1 from public.assignments a
        join public.groups g on g.id = a.group_id
        join public.cohorts c on c.id = g.cohort_id
        where a.volunteer_id = p.id and c.name like p_curriculum || '%'
      ));

    if p_send_email then
      select decrypted_secret into app_url from vault.decrypted_secrets where name = 'app_url';
      for r in
        select u.email, p.full_name
        from public.profiles p
        join auth.users u on u.id = p.id
        where p.role = 'volunteer' and u.email is not null
          and (p_curriculum is null or exists (
            select 1 from public.assignments a
            join public.groups g on g.id = a.group_id
            join public.cohorts c on c.id = g.cohort_id
            where a.volunteer_id = p.id and c.name like p_curriculum || '%'
          ))
      loop
        perform public.app_send_email(
          r.email,
          'APIIS — Coverage needed',
          '<p>Hi ' || coalesce(r.full_name, '') || ',</p>'
            || '<p>Some groups need coverage for the week of <b>'
            || to_char(wk, 'YYYY-MM-DD') || '</b>. Can you help?</p>'
            || case when app_url is not null then '<p><a href="' || app_url || '">Open APIIS Volunteer</a></p>' else '' end
        );
      end loop;
    end if;
  end if;

  -- 返回本周 open 补位总数（全部课程）
  select count(*) into n from public.coverage_requests where week_start_date = wk and status = 'open';
  return n;
end;
$$;

grant execute on function public.run_summarize_coverage(boolean, text) to authenticated;


-- ===== 20260620130000_temporary_coverage：补位临时分配 + 每周三过期 =====
-- 补位改为「临时分配」：认领补位产生的分配带上 coverage_week（被补的那个周一）。
-- 每周三自动清除「被补周一已过去」的临时补位分配，避免小组长期累积补位人。
-- 常规/导入的分配 coverage_week 为 null，永远不受影响。
-- 注：本迁移之前已存在的补位分配 coverage_week 也是 null（无法可靠区分），如需清理请手动用 × 移除。

alter table public.assignments add column if not exists coverage_week date;
-- null = 常规(永久)分配；非 null = 针对该周一的临时补位分配

-- claim_coverage：认领时把 coverage_week 记到分配上（其余逻辑不变）
create or replace function public.claim_coverage(p_request_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  req public.coverage_requests;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  select * into req from public.coverage_requests where id = p_request_id for update;
  if not found then
    raise exception 'Coverage request not found';
  end if;
  if req.status <> 'open' then
    raise exception 'This request is already covered';
  end if;

  update public.coverage_requests
    set status = 'covered', covered_by = uid
    where id = p_request_id;

  insert into public.assignments (group_id, volunteer_id, coverage_week)
    values (req.group_id, uid, req.week_start_date)
    on conflict (group_id, volunteer_id) do nothing;
end;
$$;

-- 每周三调用：清除「被补周一已过去」的临时补位分配
create or replace function public.expire_coverage_assignments()
returns integer
language plpgsql security definer set search_path = ''
as $$
declare n integer := 0;
begin
  if (select auth.uid()) is not null and not public.is_admin() then
    raise exception '只有管理员可手动运行';
  end if;
  delete from public.assignments
  where coverage_week is not null and coverage_week < current_date;
  get diagnostics n = row_count;
  return n;
end;
$$;

grant execute on function public.claim_coverage(uuid) to authenticated;
grant execute on function public.expire_coverage_assignments() to authenticated;


-- ===== 20260622090000_feedback：志愿者反馈表 =====
-- 志愿者反馈：任何登录用户可提交;本人可看自己的,管理员可看/删全部。
create table if not exists public.feedback (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references auth.users (id) on delete set null,
  full_name  text,                 -- 提交时的姓名快照(账号被删后仍可读)
  message    text not null,
  created_at timestamptz not null default now()
);
create index if not exists feedback_created_idx on public.feedback (created_at desc);

alter table public.feedback enable row level security;

drop policy if exists "feedback_insert_self" on public.feedback;
create policy "feedback_insert_self" on public.feedback
  for insert to authenticated with check (user_id = (select auth.uid()));

drop policy if exists "feedback_select_own_or_admin" on public.feedback;
create policy "feedback_select_own_or_admin" on public.feedback
  for select to authenticated using (user_id = (select auth.uid()) or public.is_admin());

drop policy if exists "feedback_admin_delete" on public.feedback;
create policy "feedback_admin_delete" on public.feedback
  for delete to authenticated using (public.is_admin());

grant select, insert, delete on public.feedback to authenticated;

-- ===== 20260622100000_feedback_resolved.sql =====
-- 反馈增加「已解决」状态：管理员可标记 resolved / 重新打开。
-- 沿用原有 select 策略(本人或管理员可看);只有管理员能改 resolved。
alter table public.feedback add column if not exists resolved boolean not null default false;
alter table public.feedback add column if not exists resolved_at timestamptz;

drop policy if exists "feedback_admin_update" on public.feedback;
create policy "feedback_admin_update" on public.feedback
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

grant update on public.feedback to authenticated;
