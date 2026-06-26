-- 提醒邮件里列出具体的 Class — Group,便于同一天带多组的志愿者区分。
-- 可用性邮件:列出收件人(本课程)的组;补位邮件:列出本周需补位的组。
-- 基于批量发送版本(20260625100000),仅改邮件 HTML。

create or replace function public.run_weekly_availability_check(
  p_send_email boolean default false,
  p_curriculum text default null
)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  wk          date := public.next_week_monday();
  s           public.app_settings;
  n           integer := 0;
  app_url     text;
  email_batch jsonb;
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
  where p.role = 'volunteer' and a.coverage_week is null
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
    select coalesce(jsonb_agg(jsonb_build_object(
             'to', u.email,
             'subject', 'APIIS — Are you available next week?',
             'html', '<p>Hi ' || coalesce(p.full_name, '') || ',</p>'
                     || '<p>Please confirm whether you can supervise the following next week (week of <b>'
                     || to_char(wk, 'YYYY-MM-DD') || '</b>):</p>'
                     || '<ul>' || coalesce((
                          select string_agg('<li>' || c2.name || ' — ' || g2.name || '</li>', '' order by c2.name, g2.name)
                          from public.assignments a2
                          join public.groups g2 on g2.id = a2.group_id
                          join public.cohorts c2 on c2.id = g2.cohort_id
                          where a2.volunteer_id = p.id and a2.coverage_week is null
                            and (p_curriculum is null or c2.name like p_curriculum || '%')
                        ), '<li>your assigned group(s)</li>') || '</ul>'
                     || '<p>Open the app to answer Yes/No for each group:</p>'
                     || case when app_url is not null then '<p><a href="' || app_url || '">Open APIIS Volunteer</a></p>' else '' end
           )), '[]'::jsonb)
      into email_batch
    from public.profiles p
    join auth.users u on u.id = p.id
    where p.role = 'volunteer' and u.email is not null
      and (p_curriculum is null or exists (
        select 1 from public.assignments a
        join public.groups g on g.id = a.group_id
        join public.cohorts c on c.id = g.cohort_id
        where a.volunteer_id = p.id and c.name like p_curriculum || '%'
      ));
    perform public.app_send_email_batch(email_batch);
  end if;

  return n;
end;
$$;

create or replace function public.run_summarize_coverage(
  p_send_email boolean default false,
  p_curriculum text default null
)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  wk          date := public.next_week_monday();
  n           integer := 0;
  app_url     text;
  email_batch jsonb;
  has_open    boolean;
  open_html   text;
begin
  if (select auth.uid()) is not null and not public.is_admin() then
    raise exception '只有管理员可手动运行';
  end if;
  if not exists (select 1 from public.class_sessions where session_date = wk) then
    return 0;
  end if;

  insert into public.coverage_requests (group_id, week_start_date, reason, status)
  select distinct av.group_id, wk, 'Assigned volunteer unavailable', 'open'
  from public.availability av
  join public.groups g on g.id = av.group_id
  join public.cohorts c on c.id = g.cohort_id
  where av.week_start_date = wk and av.is_available = false
    and exists (select 1 from public.class_sessions cs where cs.session_date = wk and cs.curriculum = left(c.name, 6))
  on conflict (group_id, week_start_date) do nothing;

  select exists (select 1 from public.coverage_requests where week_start_date = wk and status = 'open') into has_open;

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

      -- 本周需补位的具体组(对所有收件人相同)
      select coalesce(string_agg('<li>' || c.name || ' — ' || g.name || '</li>', '' order by c.name, g.name), '')
        into open_html
      from public.coverage_requests cr
      join public.groups g on g.id = cr.group_id
      join public.cohorts c on c.id = g.cohort_id
      where cr.week_start_date = wk and cr.status = 'open';

      select coalesce(jsonb_agg(jsonb_build_object(
               'to', u.email,
               'subject', 'APIIS — Coverage needed',
               'html', '<p>Hi ' || coalesce(p.full_name, '') || ',</p>'
                       || '<p>These groups need coverage for the week of <b>' || to_char(wk, 'YYYY-MM-DD') || '</b>. Can you help?</p>'
                       || '<ul>' || open_html || '</ul>'
                       || case when app_url is not null then '<p><a href="' || app_url || '">Open APIIS Volunteer to claim</a></p>' else '' end
             )), '[]'::jsonb)
        into email_batch
      from public.profiles p
      join auth.users u on u.id = p.id
      where p.role = 'volunteer' and u.email is not null
        and (p_curriculum is null or exists (
          select 1 from public.assignments a
          join public.groups g on g.id = a.group_id
          join public.cohorts c on c.id = g.cohort_id
          where a.volunteer_id = p.id and c.name like p_curriculum || '%'
        ));
      perform public.app_send_email_batch(email_batch);
    end if;
  end if;

  select count(*) into n from public.coverage_requests where week_start_date = wk and status = 'open';
  return n;
end;
$$;
