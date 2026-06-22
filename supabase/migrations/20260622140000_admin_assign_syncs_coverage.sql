-- 管理员手动把人指派到某组时,同步该组未认领(open)的补位请求:
-- 标为已覆盖(covered),覆盖人 = 被指派的志愿者 → Scheduling → Coverage requests 即时反映。
-- 没有 open 请求时,仅建立普通(manual)分配,不影响其他。

-- 确保 source 列存在(与 20260622130000 一致,幂等)
alter table public.assignments
  add column if not exists source text not null default 'import'
  check (source in ('import', 'manual', 'coverage'));

create or replace function public.admin_assign_volunteer(p_group_id uuid, p_volunteer_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;

  -- 1) 建立永久分配(与界面手动指派一致,标记 manual → 组上显示深蓝)
  insert into public.assignments (group_id, volunteer_id, source)
  values (p_group_id, p_volunteer_id, 'manual')
  on conflict (group_id, volunteer_id) do nothing;

  -- 2) 同步:该组所有未认领的补位请求 → 已覆盖,覆盖人 = 被指派者
  update public.coverage_requests
    set status = 'covered', covered_by = p_volunteer_id
    where group_id = p_group_id and status = 'open';
end;
$$;

grant execute on function public.admin_assign_volunteer(uuid, uuid) to authenticated;
