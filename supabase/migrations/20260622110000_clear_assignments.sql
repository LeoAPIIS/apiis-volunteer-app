-- 一键清空所有「志愿者 → Group」分配（仅 super_admin）。
-- 用途：重传志愿者名单(含 Class/Group)前先清零，避免旧分配残留导致同一 Group 累积多人。
-- 删除 assignments 全表(含临时补位 coverage_week 行)；不影响志愿者账号、学生、出席记录。
create or replace function public.admin_clear_assignments()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare n integer := 0;
begin
  if not public.is_super_admin() then
    raise exception 'Super admin only';
  end if;
  delete from public.assignments;
  get diagnostics n = row_count;
  return n;
end;
$$;

grant execute on function public.admin_clear_assignments() to authenticated;
