-- 补位:每人每周最多认领 1 个组。认领前检查该志愿者本周(coverage_week=被补周一)是否已认领过。
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

  -- 每人每周最多认领一个补位组
  if exists (
    select 1 from public.assignments a
    where a.volunteer_id = uid and a.coverage_week = req.week_start_date
  ) then
    raise exception 'You can only cover one group per week';
  end if;

  update public.coverage_requests
    set status = 'covered', covered_by = uid
    where id = p_request_id;

  insert into public.assignments (group_id, volunteer_id, coverage_week)
    values (req.group_id, uid, req.week_start_date)
    on conflict (group_id, volunteer_id) do nothing;
end;
$$;
grant execute on function public.claim_coverage(uuid) to authenticated;
