-- 管理员临时标记:某组「原负责志愿者本周到没到」。纯管理用途,不计入出勤/任何统计。
-- 每周三由 cron 清空(见 pg_cron_setup.sql 的 clear-group-checkmarks)。
create table if not exists public.group_check_marks (
  group_id  uuid primary key references public.groups (id) on delete cascade,
  status    text not null check (status in ('present', 'absent')),
  marked_at timestamptz not null default now()
);

alter table public.group_check_marks enable row level security;

drop policy if exists "gcm_admin_all" on public.group_check_marks;
create policy "gcm_admin_all" on public.group_check_marks
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

grant select, insert, update, delete on public.group_check_marks to authenticated;

-- 每周三清空(临时标记,不留存)。TRUNCATE 不受 safeupdate 约束。
create or replace function public.clear_group_check_marks()
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if (select auth.uid()) is not null and not public.is_admin() then
    raise exception '只有管理员可手动运行';
  end if;
  truncate table public.group_check_marks;
end;
$$;
grant execute on function public.clear_group_check_marks() to authenticated;
revoke execute on function public.clear_group_check_marks() from public, anon;
