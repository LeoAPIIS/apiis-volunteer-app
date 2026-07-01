-- 每周三清空「管理员手动指派」的分配(source='manual',蓝色徽章),只保留导入(roster)的原负责人。
-- 补位(coverage_week 非空)由 expire_coverage_assignments 单独处理,不在此函数内。
create or replace function public.clear_manual_assignments()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare n integer := 0;
begin
  if (select auth.uid()) is not null and not public.is_admin() then
    raise exception '只有管理员可手动运行';
  end if;
  delete from public.assignments where source = 'manual';
  get diagnostics n = row_count;
  return n;
end;
$$;
grant execute on function public.clear_manual_assignments() to authenticated;
revoke execute on function public.clear_manual_assignments() from public, anon;
