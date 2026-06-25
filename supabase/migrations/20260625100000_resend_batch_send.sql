-- 修复 Resend 限流(2 封/秒):提醒原本逐封发,几十上百封瞬间打出 → 大量 429。
-- 改用 Resend 批量接口 /emails/batch:每个请求最多 100 封 → 一次群发只需 1–2 个请求。

-- 批量发送:p_emails 是 [{to, subject, html}, ...];按 100 封一批 POST 到 /emails/batch。
create or replace function public.app_send_email_batch(p_emails jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  api_key    text;
  from_email text;
  total      int;
  i          int := 0;
  chunk      jsonb;
begin
  if p_emails is null or jsonb_typeof(p_emails) <> 'array' then return; end if;
  total := jsonb_array_length(p_emails);
  if total = 0 then return; end if;

  select decrypted_secret into api_key    from vault.decrypted_secrets where name = 'resend_api_key';
  select decrypted_secret into from_email from vault.decrypted_secrets where name = 'resend_from_email';
  if api_key is null or from_email is null then return; end if;

  while i < total loop
    select jsonb_agg(
             jsonb_build_object('from', from_email,
                                'to', q.value->>'to',
                                'subject', q.value->>'subject',
                                'html', q.value->>'html'))
      into chunk
    from (
      select value, ordinality
      from jsonb_array_elements(p_emails) with ordinality
    ) q
    where q.ordinality > i and q.ordinality <= i + 100;

    if chunk is not null then
      perform net.http_post(
        url     := 'https://api.resend.com/emails/batch',
        headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'),
        body    := chunk
      );
    end if;
    i := i + 100;
  end loop;
end;
$$;
-- 与 app_send_email 一样:不对外开放,仅供 SECURITY DEFINER 内部链路(以 owner 身份)调用
revoke execute on function public.app_send_email_batch(jsonb) from public, anon, authenticated;

-- ===== run_weekly_availability_check:邮件改批量发 =====
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
                     || '<p>Please confirm, for each of your groups, whether you can supervise during the week of <b>'
                     || to_char(wk, 'YYYY-MM-DD') || '</b>.</p>'
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

-- ===== run_summarize_coverage:邮件改批量发 =====
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
      select coalesce(jsonb_agg(jsonb_build_object(
               'to', u.email,
               'subject', 'APIIS — Coverage needed',
               'html', '<p>Hi ' || coalesce(p.full_name, '') || ',</p>'
                       || '<p>Some groups need coverage for the week of <b>' || to_char(wk, 'YYYY-MM-DD') || '</b>. Can you help?</p>'
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
  end if;

  select count(*) into n from public.coverage_requests where week_start_date = wk and status = 'open';
  return n;
end;
$$;
