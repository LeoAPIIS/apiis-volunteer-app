-- Re-open 补位时:除了释放认领人 + 改回 open,再主动发一条「站内通知」(不发邮件)
-- 给本周标了 available 的志愿者,提醒该组重新需要补位。
-- 用 'general' 类型(会显示在通知列表 + 计入红点;'coverage_request' 类型被隐藏了,故不用它)。
create or replace function public.admin_reopen_coverage(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  req       public.coverage_requests;
  grp_name  text;
  cls_name  text;
  sess_date date;
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;

  select * into req from public.coverage_requests where id = p_request_id for update;
  if not found then
    raise exception 'Coverage request not found';
  end if;

  -- 释放原认领人的临时补位分配
  if req.covered_by is not null then
    delete from public.assignments
    where group_id = req.group_id
      and volunteer_id = req.covered_by
      and coverage_week = req.week_start_date;
  end if;

  -- 请求改回 open
  update public.coverage_requests
    set status = 'open', covered_by = null
    where id = p_request_id;

  -- 组名 / 班名 / 实际上课日(周二班 = 周一 +1)
  select g.name, c.name into grp_name, cls_name
  from public.groups g
  join public.cohorts c on c.id = g.cohort_id
  where g.id = req.group_id;
  sess_date := req.week_start_date + case when cls_name ilike '%tuesday%' then 1 else 0 end;

  -- 主动站内通知本周 available 的志愿者(不发邮件)
  insert into public.notifications (recipient_id, type, title, body)
  select p.id, 'general', 'Coverage needed again',
         coalesce(grp_name, 'A group') || ' · ' || coalesce(cls_name, '')
         || ' needs coverage on ' || to_char(sess_date, 'YYYY-MM-DD')
         || '. Open APIIS Volunteer to claim.'
  from public.profiles p
  where p.role = 'volunteer'
    and exists (
      select 1 from public.availability av
      where av.volunteer_id = p.id
        and av.week_start_date = req.week_start_date
        and av.is_available = true
    );
end;
$$;
grant execute on function public.admin_reopen_coverage(uuid) to authenticated;
