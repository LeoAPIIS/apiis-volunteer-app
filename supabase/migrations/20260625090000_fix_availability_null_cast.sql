-- 修复:per-group 可用性预置 INSERT 用了裸 null,在 SELECT DISTINCT 下被推断为 text,
-- 插入 boolean 列 is_available 时报错(导致周四 availability cron 失败、未发信)。改为 null::boolean。
create or replace function public.run_weekly_availability_check(
  p_send_email boolean default false,
  p_curriculum text default null
)
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

  if not exists (
    select 1 from public.class_sessions
    where session_date = wk and (p_curriculum is null or curriculum = p_curriculum)
  ) then
    return 0;
  end if;

  insert into public.availability (volunteer_id, group_id, week_start_date, is_available)
  select distinct a.volunteer_id, a.group_id, wk, null::boolean
  from public.assignments a
  join public.groups g on g.id = a.group_id
  join public.cohorts c on c.id = g.cohort_id
  join public.profiles p on p.id = a.volunteer_id
  where p.role = 'volunteer'
    and a.coverage_week is null
    and (p_curriculum is null or c.name like p_curriculum || '%')
  on conflict (volunteer_id, group_id, week_start_date) do nothing;

  insert into public.notifications (recipient_id, type, title, body)
  select p.id, 'weekly_check', 'Are you available next week?',
         'Please confirm, for each of your groups, whether you can supervise during the week of '
         || to_char(wk, 'YYYY-MM-DD') || '.'
  from public.profiles p
  where p.role = 'volunteer'
    and (p_curriculum is null or exists (
      select 1 from public.assignments a
      join public.groups g on g.id = a.group_id
      join public.cohorts c on c.id = g.cohort_id
      where a.volunteer_id = p.id and c.name like p_curriculum || '%'
    ));
  get diagnostics n = row_count;

  if p_send_email then
    select decrypted_secret into app_url from vault.decrypted_secrets where name = 'app_url';
    for r in
      select u.email, p.full_name
      from public.profiles p
      join auth.users u on u.id = p.id
      where p.role = 'volunteer' and u.email is not null
        and (p_curriculum is null or exists (
          select 1 from public.assignments a
          join public.groups g on g.id = a.group_id
          join public.cohorts c on c.id = g.cohort_id
          where a.volunteer_id = p.id and c.name like p_curriculum || '%'
        ))
    loop
      perform public.app_send_email(
        r.email,
        'APIIS — Are you available next week?',
        '<p>Hi ' || coalesce(r.full_name, '') || ',</p>'
          || '<p>Please confirm, for each of your groups, whether you can supervise during the week of <b>'
          || to_char(wk, 'YYYY-MM-DD') || '</b>.</p>'
          || case when app_url is not null then '<p><a href="' || app_url || '">Open APIIS Volunteer</a></p>' else '' end
      );
    end loop;
  end if;

  return n;
end;
$$;
