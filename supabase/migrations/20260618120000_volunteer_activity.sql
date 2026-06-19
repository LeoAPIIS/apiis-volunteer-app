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
