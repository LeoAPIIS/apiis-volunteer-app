-- 课程日历（按 Excel 排课表）：每套课程 0~66 周的上课日期。
-- 提醒系统据此判断「下周一是否真实上课日」，自动跳过所有 term break。

create table if not exists public.class_sessions (
  curriculum   text not null,
  week         int  not null,
  session_date date not null,
  primary key (curriculum, week),
  unique (curriculum, session_date)
);
create index if not exists class_sessions_date_idx on public.class_sessions (session_date);

alter table public.class_sessions enable row level security;
drop policy if exists "class_sessions_read_auth" on public.class_sessions;
create policy "class_sessions_read_auth" on public.class_sessions
  for select to authenticated using (true);
drop policy if exists "class_sessions_admin_write" on public.class_sessions;
create policy "class_sessions_admin_write" on public.class_sessions
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

insert into public.class_sessions (curriculum, week, session_date) values
  ('MMin 6', 0, '2025-02-03'),
  ('MMin 6', 1, '2025-02-10'),
  ('MMin 6', 2, '2025-02-17'),
  ('MMin 6', 3, '2025-02-24'),
  ('MMin 6', 4, '2025-03-03'),
  ('MMin 6', 5, '2025-03-10'),
  ('MMin 6', 6, '2025-03-17'),
  ('MMin 6', 7, '2025-03-24'),
  ('MMin 6', 8, '2025-04-07'),
  ('MMin 6', 9, '2025-04-14'),
  ('MMin 6', 10, '2025-04-21'),
  ('MMin 6', 11, '2025-04-28'),
  ('MMin 6', 12, '2025-05-05'),
  ('MMin 6', 13, '2025-05-12'),
  ('MMin 6', 14, '2025-05-19'),
  ('MMin 6', 15, '2025-05-26'),
  ('MMin 6', 16, '2025-06-02'),
  ('MMin 6', 17, '2025-06-09'),
  ('MMin 6', 18, '2025-06-30'),
  ('MMin 6', 19, '2025-07-07'),
  ('MMin 6', 20, '2025-07-14'),
  ('MMin 6', 21, '2025-07-21'),
  ('MMin 6', 22, '2025-07-28'),
  ('MMin 6', 23, '2025-08-04'),
  ('MMin 6', 24, '2025-08-11'),
  ('MMin 6', 25, '2025-08-18'),
  ('MMin 6', 26, '2025-08-25'),
  ('MMin 6', 27, '2025-09-01'),
  ('MMin 6', 28, '2025-09-22'),
  ('MMin 6', 29, '2025-09-29'),
  ('MMin 6', 30, '2025-10-06'),
  ('MMin 6', 31, '2025-10-13'),
  ('MMin 6', 32, '2025-10-20'),
  ('MMin 6', 33, '2025-10-27'),
  ('MMin 6', 34, '2025-11-03'),
  ('MMin 6', 35, '2026-02-09'),
  ('MMin 6', 36, '2026-02-16'),
  ('MMin 6', 37, '2026-02-23'),
  ('MMin 6', 38, '2026-03-02'),
  ('MMin 6', 39, '2026-03-09'),
  ('MMin 6', 40, '2026-03-16'),
  ('MMin 6', 41, '2026-03-23'),
  ('MMin 6', 42, '2026-04-13'),
  ('MMin 6', 43, '2026-04-20'),
  ('MMin 6', 44, '2026-04-27'),
  ('MMin 6', 45, '2026-05-04'),
  ('MMin 6', 46, '2026-05-11'),
  ('MMin 6', 47, '2026-05-18'),
  ('MMin 6', 48, '2026-05-25'),
  ('MMin 6', 49, '2026-06-01'),
  ('MMin 6', 50, '2026-06-08'),
  ('MMin 6', 51, '2026-06-29'),
  ('MMin 6', 52, '2026-07-06'),
  ('MMin 6', 53, '2026-07-13'),
  ('MMin 6', 54, '2026-07-20'),
  ('MMin 6', 55, '2026-07-27'),
  ('MMin 6', 56, '2026-08-03'),
  ('MMin 6', 57, '2026-08-10'),
  ('MMin 6', 58, '2026-08-17'),
  ('MMin 6', 59, '2026-08-24'),
  ('MMin 6', 60, '2026-09-14'),
  ('MMin 6', 61, '2026-09-21'),
  ('MMin 6', 62, '2026-09-28'),
  ('MMin 6', 63, '2026-10-05'),
  ('MMin 6', 64, '2026-10-12'),
  ('MMin 6', 65, '2026-10-19'),
  ('MMin 6', 66, '2026-10-26'),
  ('MMin 7', 0, '2026-02-02'),
  ('MMin 7', 1, '2026-02-09'),
  ('MMin 7', 2, '2026-02-16'),
  ('MMin 7', 3, '2026-02-23'),
  ('MMin 7', 4, '2026-03-02'),
  ('MMin 7', 5, '2026-03-09'),
  ('MMin 7', 6, '2026-03-16'),
  ('MMin 7', 7, '2026-03-23'),
  ('MMin 7', 8, '2026-04-13'),
  ('MMin 7', 9, '2026-04-20'),
  ('MMin 7', 10, '2026-04-27'),
  ('MMin 7', 11, '2026-05-04'),
  ('MMin 7', 12, '2026-05-11'),
  ('MMin 7', 13, '2026-05-18'),
  ('MMin 7', 14, '2026-05-25'),
  ('MMin 7', 15, '2026-06-01'),
  ('MMin 7', 16, '2026-06-08'),
  ('MMin 7', 17, '2026-06-29'),
  ('MMin 7', 18, '2026-07-06'),
  ('MMin 7', 19, '2026-07-13'),
  ('MMin 7', 20, '2026-07-20'),
  ('MMin 7', 21, '2026-07-27'),
  ('MMin 7', 22, '2026-08-03'),
  ('MMin 7', 23, '2026-08-10'),
  ('MMin 7', 24, '2026-08-17'),
  ('MMin 7', 25, '2026-08-24'),
  ('MMin 7', 26, '2026-09-14'),
  ('MMin 7', 27, '2026-09-21'),
  ('MMin 7', 28, '2026-09-28'),
  ('MMin 7', 29, '2026-10-05'),
  ('MMin 7', 30, '2026-10-12'),
  ('MMin 7', 31, '2026-10-19'),
  ('MMin 7', 32, '2026-10-26'),
  ('MMin 7', 33, '2027-02-08'),
  ('MMin 7', 34, '2027-02-15'),
  ('MMin 7', 35, '2027-02-22'),
  ('MMin 7', 36, '2027-03-01'),
  ('MMin 7', 37, '2027-03-08'),
  ('MMin 7', 38, '2027-03-15'),
  ('MMin 7', 39, '2027-03-22'),
  ('MMin 7', 40, '2027-03-29'),
  ('MMin 7', 41, '2027-04-12'),
  ('MMin 7', 42, '2027-04-19'),
  ('MMin 7', 43, '2027-04-26'),
  ('MMin 7', 44, '2027-05-03'),
  ('MMin 7', 45, '2027-05-10'),
  ('MMin 7', 46, '2027-05-17'),
  ('MMin 7', 47, '2027-05-24'),
  ('MMin 7', 48, '2027-05-31'),
  ('MMin 7', 49, '2027-06-07'),
  ('MMin 7', 50, '2027-06-21'),
  ('MMin 7', 51, '2027-06-28'),
  ('MMin 7', 52, '2027-07-05'),
  ('MMin 7', 53, '2027-07-12'),
  ('MMin 7', 54, '2027-07-19'),
  ('MMin 7', 55, '2027-07-26'),
  ('MMin 7', 56, '2027-08-02'),
  ('MMin 7', 57, '2027-08-09'),
  ('MMin 7', 58, '2027-08-16'),
  ('MMin 7', 59, '2027-08-23'),
  ('MMin 7', 60, '2027-08-30'),
  ('MMin 7', 61, '2027-09-06'),
  ('MMin 7', 62, '2027-09-20'),
  ('MMin 7', 63, '2027-09-27'),
  ('MMin 7', 64, '2027-10-04'),
  ('MMin 7', 65, '2027-10-11'),
  ('MMin 7', 66, '2027-10-18')
on conflict (curriculum, week) do update set session_date = excluded.session_date;

-- ---------- 提醒函数：用「下周一是否上课日」取代单一 term_break 判断 ----------
drop function if exists public.run_weekly_availability_check(boolean);
create or replace function public.run_weekly_availability_check(p_send_email boolean default false)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  wk      date := public.next_week_monday();
  s       public.app_settings;
  n       integer := 0;
  app_url text;
  r       record;
begin
  if (select auth.uid()) is not null and not public.is_admin() then
    raise exception '只有管理员可手动运行';
  end if;

  select * into s from public.app_settings where id;
  if s.reminders_enabled is distinct from true then return 0; end if;
  -- 下周一不是任何课程的真实上课日 → 跳过（自动覆盖所有 break）
  if not exists (select 1 from public.class_sessions where session_date = wk) then
    return 0;
  end if;

  insert into public.availability (volunteer_id, week_start_date, is_available)
  select p.id, wk, null from public.profiles p where p.role = 'volunteer'
  on conflict (volunteer_id, week_start_date) do nothing;

  insert into public.notifications (recipient_id, type, title, body)
  select p.id, 'weekly_check', 'Are you available next week?',
         'Please confirm whether you can supervise during the week of ' || to_char(wk, 'YYYY-MM-DD') || '.'
  from public.profiles p where p.role = 'volunteer';
  get diagnostics n = row_count;

  if p_send_email then
    select decrypted_secret into app_url from vault.decrypted_secrets where name = 'app_url';
    for r in
      select u.email, p.full_name from public.profiles p
      join auth.users u on u.id = p.id
      where p.role = 'volunteer' and u.email is not null
    loop
      perform public.app_send_email(
        r.email,
        'APIIS — Are you available next week?',
        '<p>Hi ' || coalesce(r.full_name, '') || ',</p>'
          || '<p>Please confirm whether you can supervise during the week of <b>'
          || to_char(wk, 'YYYY-MM-DD') || '</b>.</p>'
          || case when app_url is not null then '<p><a href="' || app_url || '">Open APIIS Volunteer</a></p>' else '' end
      );
    end loop;
  end if;

  return n;
end;
$$;

drop function if exists public.run_summarize_coverage(boolean);
create or replace function public.run_summarize_coverage(p_send_email boolean default false)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  wk       date := public.next_week_monday();
  n        integer := 0;
  app_url  text;
  r        record;
  has_open boolean;
begin
  if (select auth.uid()) is not null and not public.is_admin() then
    raise exception '只有管理员可手动运行';
  end if;

  -- 下周一不是上课日 → 不生成补位请求
  if not exists (select 1 from public.class_sessions where session_date = wk) then
    return 0;
  end if;

  insert into public.coverage_requests (group_id, week_start_date, reason, status)
  select distinct a.group_id, wk, 'Assigned volunteer unavailable', 'open'
  from public.availability av
  join public.assignments a on a.volunteer_id = av.volunteer_id
  where av.week_start_date = wk and av.is_available = false
  on conflict (group_id, week_start_date) do nothing;

  select exists (
    select 1 from public.coverage_requests where week_start_date = wk and status = 'open'
  ) into has_open;

  if has_open then
    insert into public.notifications (recipient_id, type, title, body)
    select p.id, 'coverage_request', 'Coverage needed',
           'Some groups need coverage for the week of ' || to_char(wk, 'YYYY-MM-DD') || '. Can you help?'
    from public.profiles p where p.role = 'volunteer';

    if p_send_email then
      select decrypted_secret into app_url from vault.decrypted_secrets where name = 'app_url';
      for r in
        select u.email, p.full_name from public.profiles p
        join auth.users u on u.id = p.id
        where p.role = 'volunteer' and u.email is not null
      loop
        perform public.app_send_email(
          r.email,
          'APIIS — Coverage needed',
          '<p>Hi ' || coalesce(r.full_name, '') || ',</p>'
            || '<p>Some groups need coverage for the week of <b>'
            || to_char(wk, 'YYYY-MM-DD') || '</b>. Can you help?</p>'
            || case when app_url is not null then '<p><a href="' || app_url || '">Open APIIS Volunteer</a></p>' else '' end
        );
      end loop;
    end if;
  end if;

  select count(*) into n from public.coverage_requests where week_start_date = wk and status = 'open';
  return n;
end;
$$;

grant execute on function public.run_weekly_availability_check(boolean) to authenticated;
grant execute on function public.run_summarize_coverage(boolean) to authenticated;
