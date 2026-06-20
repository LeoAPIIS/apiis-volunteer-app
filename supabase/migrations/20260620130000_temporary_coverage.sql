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
