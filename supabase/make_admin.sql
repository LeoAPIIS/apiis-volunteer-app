-- 把 itsupport@apiis.org 设为 super_admin（最高权限：可任命/撤销 admin、删任何人、不可被他人删/降级）。
-- 前置：先跑迁移 20260619090000_super_admin.sql（它会放开 role 取值，并把已存在的 itsupport 升为 super_admin）。
-- 仅当 itsupport 账号「还不存在」时才需要本脚本来创建它（请改 pw）。

do $$
declare
  uid uuid;
  pw  text := 'ChangeMe-123';  -- ← 新建账号时的初始密码，请改；已存在则忽略
begin
  select id into uid from auth.users where lower(email) = 'itsupport@apiis.org';

  if uid is null then
    uid := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data, is_super_admin,
      confirmation_token, recovery_token, email_change_token_new, email_change
    ) values (
      '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
      'itsupport@apiis.org', crypt(pw, gen_salt('bf')), now(), now(), now(),
      '{"provider":"email","providers":["email"]}',
      '{"full_name":"IT Support","role":"super_admin"}', false, '', '', '', ''
    );
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), uid, uid::text,
            jsonb_build_object('sub', uid::text, 'email', 'itsupport@apiis.org'), 'email', now(), now(), now());
  end if;

  insert into public.profiles (id, full_name, role)
  values (uid, 'IT Support', 'super_admin')
  on conflict (id) do update set role = 'super_admin';
end $$;

-- 验证：
-- select u.email, p.role from public.profiles p
--   join auth.users u on u.id = p.id where lower(u.email) = 'itsupport@apiis.org';
