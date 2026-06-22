-- 提醒按课程(MMin 6 / MMin 7)分发：新增 p_curriculum 参数。
--   p_curriculum 为 null  → 全部志愿者(手动 "Run now" 用,行为不变)
--   p_curriculum = 'MMin 6' / 'MMin 7' → 只通知/发给被分配到该课程班级的志愿者，
--     且按「该课程」自己的上课周判断(两套课程休息周不同)。
-- cron 改为 4 个任务，见 pg_cron_setup.sql（或本文件末尾的重排程段）。

drop function if exists public.run_weekly_availability_check(boolean);
drop function if exists public.run_weekly_availability_check();
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

-- 下周一对（指定课程 / 任意课程）是否真实上课日；否则跳过
if not exists (
  select 1 from public.class_sessions
  where session_date = wk and (p_curriculum is null or curriculum = p_curriculum)
) then
  return 0;
end if;

insert into public.availability (volunteer_id, week_start_date, is_available)
select p.id, wk, null
from public.profiles p
where p.role = 'volunteer'
  and (p_curriculum is null or exists (
    select 1 from public.assignments a
    join public.groups g on g.id = a.group_id
    join public.cohorts c on c.id = g.cohort_id
    where a.volunteer_id = p.id and c.name like p_curriculum || '%'
  ))
on conflict (volunteer_id, week_start_date) do nothing;

insert into public.notifications (recipient_id, type, title, body)
select p.id, 'weekly_check', 'Are you available next week?',
        'Please confirm whether you can supervise during the week of ' || to_char(wk, 'YYYY-MM-DD') || '.'
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
drop function if exists public.run_summarize_coverage();
create or replace function public.run_summarize_coverage(
p_send_email boolean default false,
p_curriculum text default null
)
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

if not exists (
  select 1 from public.class_sessions
  where session_date = wk and (p_curriculum is null or curriculum = p_curriculum)
) then
  return 0;
end if;

-- 为「该课程中、被分配志愿者本周不可用」的小组建补位请求
insert into public.coverage_requests (group_id, week_start_date, reason, status)
select distinct a.group_id, wk, 'Assigned volunteer unavailable', 'open'
from public.availability av
join public.assignments a on a.volunteer_id = av.volunteer_id
join public.groups g on g.id = a.group_id
join public.cohorts c on c.id = g.cohort_id
where av.week_start_date = wk and av.is_available = false
  and (p_curriculum is null or c.name like p_curriculum || '%')
on conflict (group_id, week_start_date) do nothing;

select exists (
  select 1 from public.coverage_requests cr
  join public.groups g on g.id = cr.group_id
  join public.cohorts c on c.id = g.cohort_id
  where cr.week_start_date = wk and cr.status = 'open'
    and (p_curriculum is null or c.name like p_curriculum || '%')
) into has_open;

if has_open then
  insert into public.notifications (recipient_id, type, title, body)
  select p.id, 'coverage_request', 'Coverage needed',
          'Some groups need coverage for the week of ' || to_char(wk, 'YYYY-MM-DD') || '. Can you help?'
  from public.profiles p
  where p.role = 'volunteer'
    and (p_curriculum is null or exists (
      select 1 from public.assignments a
      join public.groups g on g.id = a.group_id
      join public.cohorts c on c.id = g.cohort_id
      where a.volunteer_id = p.id and c.name like p_curriculum || '%'
    ));

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
        'APIIS — Coverage needed',
        '<p>Hi ' || coalesce(r.full_name, '') || ',</p>'
          || '<p>Some groups need coverage for the week of <b>'
          || to_char(wk, 'YYYY-MM-DD') || '</b>. Can you help?</p>'
          || case when app_url is not null then '<p><a href="' || app_url || '">Open APIIS Volunteer</a></p>' else '' end
      );
    end loop;
  end if;
end if;

select count(*) into n
from public.coverage_requests cr
join public.groups g on g.id = cr.group_id
join public.cohorts c on c.id = g.cohort_id
where cr.week_start_date = wk and cr.status = 'open'
  and (p_curriculum is null or c.name like p_curriculum || '%');
return n;
end;
$$;

grant execute on function public.run_weekly_availability_check(boolean, text) to authenticated;
grant execute on function public.run_summarize_coverage(boolean, text) to authenticated;
