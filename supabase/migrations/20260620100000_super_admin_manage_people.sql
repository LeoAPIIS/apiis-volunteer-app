-- 只有 super_admin 可以「上传(导入)/删除」学生与志愿者。
-- admin 仍可：查看报表/导出、管理小组分配、记考勤、查看名单——但不能导入或删除人。

-- ===== students：写操作(insert/update/delete)收归 super_admin；读保留给 admin =====
-- 说明：select 给 admin（报表/导出需要）；FOR ALL 的 super 策略覆盖增删改。
drop policy if exists "students_admin_write" on public.students;
drop policy if exists "students_select_admin" on public.students;
drop policy if exists "students_all_super" on public.students;

create policy "students_select_admin" on public.students
  for select to authenticated using (public.is_admin());
create policy "students_all_super" on public.students
  for all to authenticated using (public.is_super_admin()) with check (public.is_super_admin());

-- ===== 志愿者导入：super_admin only =====
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
  if not public.is_super_admin() then
    raise exception 'Super admin only';
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

-- ===== 志愿者删除：super_admin only（仍禁止删自己 / 删 super_admin）=====
create or replace function public.admin_delete_volunteer(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  target_role text;
begin
  if not public.is_super_admin() then
    raise exception 'Super admin only';
  end if;
  if p_id = (select auth.uid()) then
    raise exception 'You cannot delete your own account';
  end if;
  select role into target_role from public.profiles where id = p_id;
  if target_role is null then
    raise exception 'User not found';
  end if;
  if target_role = 'super_admin' then
    raise exception 'A super admin cannot be deleted here';
  end if;
  delete from auth.users where id = p_id;
end;
$$;

grant execute on function public.admin_import_volunteer(text, text, text, text, uuid) to authenticated;
grant execute on function public.admin_delete_volunteer(uuid) to authenticated;
