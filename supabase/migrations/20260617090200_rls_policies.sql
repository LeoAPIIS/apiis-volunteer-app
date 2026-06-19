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
