-- 可用性改为「按组」:每个志愿者对自己负责的「每个组、每周」各回复一次。
-- 补位随之变精准——只对志愿者「标记不可用的那个组」建补位,且仅限那周真有课的组。

-- ============ 1) availability 表:加 group_id,唯一键改为 (volunteer, group, week) ============
alter table public.availability
  add column if not exists group_id uuid references public.groups (id) on delete cascade;

-- 旧的「每人每周一条、无 group」数据已无意义,清空(带 WHERE 兼容 safeupdate)
delete from public.availability where group_id is null;

alter table public.availability alter column group_id set not null;
alter table public.availability drop constraint if exists availability_volunteer_id_week_start_date_key;
alter table public.availability
  add constraint availability_vol_group_week_key unique (volunteer_id, group_id, week_start_date);

-- ============ 2) 可用性提醒:按 (志愿者 × 其负责的组) 预置「待回复」行 ============
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

  -- 按「志愿者 × 其负责(永久)的组」预置待回复行(coverage_week 为 null = 常驻负责人)
  insert into public.availability (volunteer_id, group_id, week_start_date, is_available)
  select distinct a.volunteer_id, a.group_id, wk, null
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

-- ============ 3) 补位征集:按「不可用的那个组」建补位(仅限那周有课的组)============
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

  if not exists (select 1 from public.class_sessions where session_date = wk) then
    return 0;
  end if;

  -- 按组:志愿者对「该组」标记不可用 → 给该组建补位(仅当该组所属课程那周有课)
  insert into public.coverage_requests (group_id, week_start_date, reason, status)
  select distinct av.group_id, wk, 'Assigned volunteer unavailable', 'open'
  from public.availability av
  join public.groups g on g.id = av.group_id
  join public.cohorts c on c.id = g.cohort_id
  where av.week_start_date = wk
    and av.is_available = false
    and exists (
      select 1 from public.class_sessions cs
      where cs.session_date = wk and cs.curriculum = left(c.name, 6)
    )
  on conflict (group_id, week_start_date) do nothing;

  select exists (
    select 1 from public.coverage_requests where week_start_date = wk and status = 'open'
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

  select count(*) into n from public.coverage_requests where week_start_date = wk and status = 'open';
  return n;
end;
$$;
