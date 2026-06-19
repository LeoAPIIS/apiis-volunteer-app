-- 志愿者：导入(可带小组分配，幂等) + 删除

-- 取代旧的 admin_create_volunteer
drop function if exists public.admin_create_volunteer(text, text, text, text);

-- 幂等导入：邮箱不存在则建号；已存在则复用并更新姓名/电话；可选地分配到某小组。
create or replace function public.admin_import_volunteer(
  p_email     text,
  p_full_name text,
  p_phone     text,
  p_password  text,
  p_group_id  uuid default null
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
  if p_email is null or btrim(p_email) = '' then
    raise exception 'email is required';
  end if;

  select id into uid from auth.users where lower(email) = lower(btrim(p_email));

  if uid is null then
    if p_password is null or p_password = '' then
      raise exception 'password is required for a new volunteer';
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
    values (gen_random_uuid(), uid, uid::text,
            jsonb_build_object('sub', uid::text, 'email', lower(btrim(p_email))), 'email', now(), now(), now());
  end if;

  insert into public.profiles (id, full_name, role, phone)
  values (uid, coalesce(p_full_name, ''), 'volunteer', p_phone)
  on conflict (id) do update
    set full_name = excluded.full_name, role = 'volunteer', phone = excluded.phone;

  if p_group_id is not null then
    insert into public.assignments (group_id, volunteer_id)
    values (p_group_id, uid)
    on conflict (group_id, volunteer_id) do nothing;
  end if;

  return uid;
end;
$$;

-- 删除志愿者：删 auth.users → 级联删 profile/assignments/availability/notifications；
-- attendance/coverage 的引用置空。仅限删志愿者（不可删管理员）。
create or replace function public.admin_delete_volunteer(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;
  if not exists (select 1 from public.profiles where id = p_id and role = 'volunteer') then
    raise exception 'Not a volunteer';
  end if;
  delete from auth.users where id = p_id;
end;
$$;

grant execute on function public.admin_import_volunteer(text, text, text, text, uuid) to authenticated;
grant execute on function public.admin_delete_volunteer(uuid) to authenticated;
