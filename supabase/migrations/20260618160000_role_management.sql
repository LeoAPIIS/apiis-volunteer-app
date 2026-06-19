-- 角色管理：放宽 guard_profile_role —— 仅拦截「已登录的非管理员」改 role。
-- 无 auth 上下文（SQL Editor / service_role / cron 等可信场景）允许改 role，
-- 以便用 SQL 给首个/超级管理员 bootstrap，且不影响 App 内的安全（登录的志愿者仍被拦）。

create or replace function public.guard_profile_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.role is distinct from old.role)
     and (select auth.uid()) is not null
     and not public.is_admin() then
    raise exception '只有管理员可以修改角色 (role)';
  end if;
  return new;
end;
$$;
