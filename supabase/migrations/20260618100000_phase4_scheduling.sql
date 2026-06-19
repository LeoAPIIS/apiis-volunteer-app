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
