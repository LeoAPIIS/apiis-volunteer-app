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
