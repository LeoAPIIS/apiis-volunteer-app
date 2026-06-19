-- 志愿者列表增加 email 列：email 存在 auth.users（登录邮箱），故 join auth.users。
-- 改了返回类型（多一列），必须先 drop 再建。SECURITY DEFINER + search_path='' → 全限定 auth.users。

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
