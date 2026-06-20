-- 学员 PII：志愿者不再能直接读取 students 表（其中含 email）。
-- 管理员仍可全权读写（students_admin_write 是 for all，已覆盖 SELECT）；
-- 志愿者改为通过 get_group_students() 只拿到「id + 姓名」，且仅限自己被分配的小组。

-- 1) 移除志愿者对 students 的直接读权限（删除「assigned_or_admin」select 策略）
drop policy if exists "students_select_assigned_or_admin" on public.students;

-- 2) 只返回姓名的安全函数：管理员或该组成员可调用；email 永不出库到志愿者端
create or replace function public.get_group_students(p_group_id uuid)
returns table (id uuid, full_name text)
language sql security definer set search_path = '' as $$
  select s.id, s.full_name
  from public.students s
  where s.group_id = p_group_id
    and (public.is_admin() or public.is_assigned_to_group(p_group_id))
  order by s.full_name;
$$;
grant execute on function public.get_group_students(uuid) to authenticated;
