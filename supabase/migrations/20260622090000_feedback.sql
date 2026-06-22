-- 志愿者反馈：任何登录用户可提交;本人可看自己的,管理员可看/删全部。
create table if not exists public.feedback (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references auth.users (id) on delete set null,
  full_name  text,                 -- 提交时的姓名快照(账号被删后仍可读)
  message    text not null,
  created_at timestamptz not null default now()
);
create index if not exists feedback_created_idx on public.feedback (created_at desc);

alter table public.feedback enable row level security;

drop policy if exists "feedback_insert_self" on public.feedback;
create policy "feedback_insert_self" on public.feedback
  for insert to authenticated with check (user_id = (select auth.uid()));

drop policy if exists "feedback_select_own_or_admin" on public.feedback;
create policy "feedback_select_own_or_admin" on public.feedback
  for select to authenticated using (user_id = (select auth.uid()) or public.is_admin());

drop policy if exists "feedback_admin_delete" on public.feedback;
create policy "feedback_admin_delete" on public.feedback
  for delete to authenticated using (public.is_admin());

grant select, insert, delete on public.feedback to authenticated;
