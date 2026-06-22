-- 反馈增加「已解决」状态：管理员可标记 resolved / 重新打开。
-- 沿用原有 select 策略(本人或管理员可看);只有管理员能改 resolved。
alter table public.feedback add column if not exists resolved boolean not null default false;
alter table public.feedback add column if not exists resolved_at timestamptz;

drop policy if exists "feedback_admin_update" on public.feedback;
create policy "feedback_admin_update" on public.feedback
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

grant update on public.feedback to authenticated;
