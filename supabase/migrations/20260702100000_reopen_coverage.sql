-- 管理员「重新放出」补位:认领人来不了时,释放其补位分配并把请求改回 open。
-- 于是它重新出现在站内 "Coverage needed" 卡片,别人可再认领(不发邮件)。
create or replace function public.admin_reopen_coverage(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare req public.coverage_requests;
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;

  select * into req from public.coverage_requests where id = p_request_id for update;
  if not found then
    raise exception 'Coverage request not found';
  end if;

  -- 释放原认领人的临时补位分配(该组、该周、该人)
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
end;
$$;
grant execute on function public.admin_reopen_coverage(uuid) to authenticated;
