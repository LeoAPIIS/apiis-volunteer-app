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
