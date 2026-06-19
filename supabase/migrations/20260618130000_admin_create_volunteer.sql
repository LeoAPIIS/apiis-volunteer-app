-- Phase 5+：管理员创建志愿者账号（供 App 内「导入志愿者」调用）
-- SECURITY DEFINER + is_admin 守门；沿用 seed 的 auth.users + identities 建号方式。
-- search_path 含 extensions：crypt/gen_salt 在 Supabase(extensions) 与本地(public) 都能解析。

create or replace function public.admin_create_volunteer(
  p_email     text,
  p_full_name text,
  p_phone     text,
  p_password  text
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  uid uuid;
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;
  if p_email is null or btrim(p_email) = '' or p_password is null or p_password = '' then
    raise exception 'email and password are required';
  end if;
  if exists (select 1 from auth.users where lower(email) = lower(btrim(p_email))) then
    raise exception 'A user with email % already exists', p_email;
  end if;

  uid := gen_random_uuid();

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data, is_super_admin,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
    lower(btrim(p_email)), crypt(p_password, gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}',
    jsonb_build_object('full_name', coalesce(p_full_name, ''), 'role', 'volunteer', 'phone', p_phone),
    false, '', '', '', ''
  );

  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (
    gen_random_uuid(), uid, uid::text,
    jsonb_build_object('sub', uid::text, 'email', lower(btrim(p_email))),
    'email', now(), now(), now()
  );

  -- 触发器通常已建 profile；这里 upsert 确保姓名/电话/角色正确
  insert into public.profiles (id, full_name, role, phone)
  values (uid, coalesce(p_full_name, ''), 'volunteer', p_phone)
  on conflict (id) do update
    set full_name = excluded.full_name, role = 'volunteer', phone = excluded.phone;

  return uid;
end;
$$;

grant execute on function public.admin_create_volunteer(text, text, text, text) to authenticated;
