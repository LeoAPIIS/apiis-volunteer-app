-- 补位征集的收件人改为「本周回复了 available 的志愿者」(某个组标了 is_available=true 即算)。
-- 补位缺口的创建逻辑不变(仍按 is_available=false 的组);仅改「通知/邮件发给谁」。
-- 基于 20260701110000(链接文字 + 批量发送 + 列出分组)。
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

  -- 缺口:某组的原负责人本周标了不可用 → 建补位(仅那周有课的组)
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
    -- 收件人:本周至少有一个组标了 available 的志愿者(+ 可选课程过滤)
    insert into public.notifications (recipient_id, type, title, body)
    select p.id, 'coverage_request', 'Coverage needed',
           'Some groups need coverage for the week of ' || to_char(wk, 'YYYY-MM-DD') || '. Can you help?'
    from public.profiles p
    where p.role = 'volunteer'
      and exists (
        select 1 from public.availability av
        where av.volunteer_id = p.id and av.week_start_date = wk and av.is_available = true
      )
      and (p_curriculum is null or exists (
        select 1 from public.assignments a
        join public.groups g on g.id = a.group_id
        join public.cohorts c on c.id = g.cohort_id
        where a.volunteer_id = p.id and c.name like p_curriculum || '%'
      ));

    if p_send_email then
      select decrypted_secret into app_url from vault.decrypted_secrets where name = 'app_url';

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
                       || case when app_url is not null then '<p><a href="' || app_url || '">Open APIIS Volunteer APP to claim</a></p>' else '' end
             )), '[]'::jsonb)
        into email_batch
      from public.profiles p
      join auth.users u on u.id = p.id
      where p.role = 'volunteer' and u.email is not null
        and exists (
          select 1 from public.availability av
          where av.volunteer_id = p.id and av.week_start_date = wk and av.is_available = true
        )
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
