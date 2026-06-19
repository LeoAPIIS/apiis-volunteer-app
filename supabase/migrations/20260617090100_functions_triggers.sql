-- APIIS 志愿者管理 — 辅助函数与触发器

-- 当前用户是否 admin。
-- SECURITY DEFINER + 固定 search_path：以函数属主(postgres，具 BYPASSRLS)身份读取，
-- 因此即便在 profiles 自身的 RLS 策略中调用也不会触发递归。
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;

-- 当前用户是否被分配到某小组（含补位产生的临时分配）。
create or replace function public.is_assigned_to_group(p_group_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.assignments
    where group_id = p_group_id and volunteer_id = (select auth.uid())
  );
$$;

-- 新用户注册时自动创建 profile（默认志愿者；可由 user metadata 指定 role/full_name/phone）。
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, role, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'role', 'volunteer'),
    new.raw_user_meta_data ->> 'phone'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 维护 attendance_records.updated_at
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_attendance_updated_at
  before update on public.attendance_records
  for each row execute function public.set_updated_at();

-- 防止非管理员修改自己的 role（防止越权提权）。
create or replace function public.guard_profile_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.role is distinct from old.role) and not public.is_admin() then
    raise exception '只有管理员可以修改角色 (role)';
  end if;
  return new;
end;
$$;

create trigger trg_profiles_guard_role
  before update on public.profiles
  for each row execute function public.guard_profile_role();

-- 策略中会用到这两个辅助函数，确保 authenticated 可执行
grant execute on function public.is_admin() to anon, authenticated;
grant execute on function public.is_assigned_to_group(uuid) to anon, authenticated;
