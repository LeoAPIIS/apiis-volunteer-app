-- 补位「广播版」：补位请求覆盖全部课程(MMin 6 & 7)的缺口；
--   p_curriculum 现在只用于筛选「通知/邮件的收件人」(周六发 MMin 6 志愿者、周日发 MMin 7 志愿者)。
--   任何志愿者都能认领任何小组(跨课程互补),通知量摊到两天。
-- 注：run_weekly_availability_check(可用性)仍按课程分发，不在此文件改动。

create or replace function public.run_summarize_coverage(
  p_send_email boolean default false,
  p_curriculum text default null  -- 仅筛选收件人；补位请求始终覆盖全部课程
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

  -- 下周一对「任意课程」都不是上课日 → 跳过
  if not exists (select 1 from public.class_sessions where session_date = wk) then
    return 0;
  end if;

  -- 为「本周不可用志愿者所在的小组」建补位请求（全部课程，不按 p_curriculum 过滤）
  insert into public.coverage_requests (group_id, week_start_date, reason, status)
  select distinct a.group_id, wk, 'Assigned volunteer unavailable', 'open'
  from public.availability av
  join public.assignments a on a.volunteer_id = av.volunteer_id
  where av.week_start_date = wk and av.is_available = false
  on conflict (group_id, week_start_date) do nothing;

  -- 本周是否有任何 open 补位（全部课程）
  select exists (
    select 1 from public.coverage_requests where week_start_date = wk and status = 'open'
  ) into has_open;

  if has_open then
    -- 收件人：p_curriculum 为空=全部；否则=被分配到该课程班级的志愿者
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

  -- 返回本周 open 补位总数（全部课程）
  select count(*) into n from public.coverage_requests where week_start_date = wk and status = 'open';
  return n;
end;
$$;

grant execute on function public.run_summarize_coverage(boolean, text) to authenticated;
