-- 分配历史(审计):每周三清理 manual / coverage 分配前,先归档一份快照,便于事后追溯
-- 「过去某周,某组是谁被管理员指派 / 谁在补位」。快照存文本(组名/班级/姓名/邮箱),
-- 即使日后删组/删人也可读。原负责人(import)是永久的,不需归档。
create table if not exists public.assignment_history (
  id              uuid primary key default gen_random_uuid(),
  week_start_date date not null,           -- 该分配所属的周(周一日期)
  source          text not null,           -- 'manual' 管理员指派 · 'coverage' 补位
  group_id        uuid,
  group_name      text,
  class_name      text,
  volunteer_id    uuid,
  volunteer_name  text,
  volunteer_email text,
  archived_at     timestamptz not null default now()
);
create index if not exists assignment_history_week_idx on public.assignment_history (week_start_date);

alter table public.assignment_history enable row level security;
drop policy if exists "ah_admin_select" on public.assignment_history;
create policy "ah_admin_select" on public.assignment_history
  for select to authenticated using (public.is_admin());
grant select on public.assignment_history to authenticated;

-- 每周三清 manual：先归档(周次 = 本周周一),再删
create or replace function public.clear_manual_assignments()
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  n  integer := 0;
  wk date := date_trunc('week', now())::date;  -- 本周周一
begin
  if (select auth.uid()) is not null and not public.is_admin() then
    raise exception '只有管理员可手动运行';
  end if;

  insert into public.assignment_history
    (week_start_date, source, group_id, group_name, class_name, volunteer_id, volunteer_name, volunteer_email)
  select wk, 'manual', g.id, g.name, c.name, a.volunteer_id, p.full_name, u.email
  from public.assignments a
  join public.groups   g on g.id = a.group_id
  join public.cohorts  c on c.id = g.cohort_id
  left join public.profiles p on p.id = a.volunteer_id
  left join auth.users      u on u.id = a.volunteer_id
  where a.source = 'manual';

  delete from public.assignments where source = 'manual';
  get diagnostics n = row_count;
  return n;
end;
$$;
grant execute on function public.clear_manual_assignments() to authenticated;
revoke execute on function public.clear_manual_assignments() from public, anon;

-- 每周三清过期 coverage：先归档(周次 = coverage_week 即被补的那一周),再删
create or replace function public.expire_coverage_assignments()
returns integer
language plpgsql security definer set search_path = ''
as $$
declare n integer := 0;
begin
  if (select auth.uid()) is not null and not public.is_admin() then
    raise exception '只有管理员可手动运行';
  end if;

  insert into public.assignment_history
    (week_start_date, source, group_id, group_name, class_name, volunteer_id, volunteer_name, volunteer_email)
  select a.coverage_week, 'coverage', g.id, g.name, c.name, a.volunteer_id, p.full_name, u.email
  from public.assignments a
  join public.groups   g on g.id = a.group_id
  join public.cohorts  c on c.id = g.cohort_id
  left join public.profiles p on p.id = a.volunteer_id
  left join auth.users      u on u.id = a.volunteer_id
  where a.coverage_week is not null and a.coverage_week < current_date;

  delete from public.assignments
  where coverage_week is not null and coverage_week < current_date;
  get diagnostics n = row_count;
  return n;
end;
$$;
grant execute on function public.expire_coverage_assignments() to authenticated;
