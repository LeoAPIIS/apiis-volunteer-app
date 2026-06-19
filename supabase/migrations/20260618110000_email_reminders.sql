-- Phase 4：Email 提醒（pg_net + Resend，无需 Edge Function/CLI）
-- 站内通知不变；这里增加「发邮件」能力。
-- Resend 的 API key / 发件人 / App URL 存放在 Supabase Vault（见 email_setup.sql）。

-- pg_net（本地无此扩展时忽略，便于 Docker 校验函数逻辑）
do $$ begin
  execute 'create extension if not exists pg_net';
exception when others then
  raise notice 'pg_net not available here (ok for local test): %', sqlerrm;
end $$;

-- 通用发信：从 Vault 读 Resend 配置；未配置则跳过（不报错，站内通知照常）。
-- 不授予普通用户执行权限——仅供下面的 SECURITY DEFINER 函数内部调用。
create or replace function public.app_send_email(p_to text, p_subject text, p_html text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  api_key    text;
  from_email text;
begin
  select decrypted_secret into api_key    from vault.decrypted_secrets where name = 'resend_api_key';
  select decrypted_secret into from_email from vault.decrypted_secrets where name = 'resend_from_email';
  if api_key is null or from_email is null or p_to is null then
    return; -- 未配置 Resend → 跳过发信
  end if;
  perform net.http_post(
    url     := 'https://api.resend.com/emails',
    headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'),
    body    := jsonb_build_object('from', from_email, 'to', p_to, 'subject', p_subject, 'html', p_html)
  );
end;
$$;

-- ---------- 重建 run_weekly_availability_check：新增 p_send_email ----------
-- 默认 false：管理员手动「Run now」只建站内通知、不发邮件；cron 传 true 才发邮件。
drop function if exists public.run_weekly_availability_check();
create or replace function public.run_weekly_availability_check(p_send_email boolean default false)
returns integer
language plpgsql
security definer
set search_path = ''
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
  if s.term_break_start is not null and s.term_break_end is not null
     and wk between s.term_break_start and s.term_break_end then
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

-- ---------- 重建 run_summarize_coverage：新增 p_send_email ----------
drop function if exists public.run_summarize_coverage();
create or replace function public.run_summarize_coverage(p_send_email boolean default false)
returns integer
language plpgsql
security definer
set search_path = ''
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
