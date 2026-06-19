-- APIIS 志愿者管理 — 种子数据（仅测试用，切勿用于生产）
--
-- 前提：先跑完所有 migrations（含 4 个班级 + 156 个小组）。
-- 本文件创建 3 个测试账号，并给 MMin 6P 的 Group 1/2 放几名测试学员 + 分配志愿者，
-- 以便测试出勤评分与报表。可重复运行（带幂等保护）。
--
-- 测试账号（密码均为 apiis1234）：
--   admin@apiis.test        管理员
--   volunteer1@apiis.test   志愿者 → MMin 6P / Group 1
--   volunteer2@apiis.test   志愿者 → MMin 6P / Group 2

-- ---------- 1) 测试 auth 用户 ----------
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data, is_super_admin,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a1',
   'authenticated', 'authenticated', 'admin@apiis.test', crypt('apiis1234', gen_salt('bf')),
   now(), now(), now(), '{"provider":"email","providers":["email"]}',
   '{"full_name":"Admin User","role":"admin"}', false, '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000b1',
   'authenticated', 'authenticated', 'volunteer1@apiis.test', crypt('apiis1234', gen_salt('bf')),
   now(), now(), now(), '{"provider":"email","providers":["email"]}',
   '{"full_name":"Volunteer One","role":"volunteer","phone":"+12015550101"}', false, '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000b2',
   'authenticated', 'authenticated', 'volunteer2@apiis.test', crypt('apiis1234', gen_salt('bf')),
   now(), now(), now(), '{"provider":"email","providers":["email"]}',
   '{"full_name":"Volunteer Two","role":"volunteer","phone":"+12015550102"}', false, '', '', '', '')
on conflict (id) do nothing;

insert into auth.identities (
  id, user_id, provider_id, identity_data, provider,
  last_sign_in_at, created_at, updated_at
)
values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a1',
   '{"sub":"00000000-0000-0000-0000-0000000000a1","email":"admin@apiis.test"}', 'email', now(), now(), now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b1',
   '{"sub":"00000000-0000-0000-0000-0000000000b1","email":"volunteer1@apiis.test"}', 'email', now(), now(), now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000b2',
   '{"sub":"00000000-0000-0000-0000-0000000000b2","email":"volunteer2@apiis.test"}', 'email', now(), now(), now())
on conflict do nothing;

-- ---------- 2) profiles（触发器通常已建，这里 upsert 确保角色/姓名正确）----------
insert into public.profiles (id, full_name, role, phone)
values
  ('00000000-0000-0000-0000-0000000000a1', 'Admin User',    'admin',     null),
  ('00000000-0000-0000-0000-0000000000b1', 'Volunteer One', 'volunteer', '+12015550101'),
  ('00000000-0000-0000-0000-0000000000b2', 'Volunteer Two', 'volunteer', '+12015550102')
on conflict (id) do update
  set full_name = excluded.full_name, role = excluded.role, phone = excluded.phone;

-- ---------- 3) 测试业务数据：MMin 6P 的 Group 1/2 ----------
do $$
declare g1 uuid; g2 uuid;
begin
  select grp.id into g1 from public.groups grp
    join public.cohorts c on c.id = grp.cohort_id
   where c.name = 'MMin 6P Monday Morning' and grp.name = 'Group 1';
  select grp.id into g2 from public.groups grp
    join public.cohorts c on c.id = grp.cohort_id
   where c.name = 'MMin 6P Monday Morning' and grp.name = 'Group 2';

  if g1 is not null then
    insert into public.assignments (group_id, volunteer_id)
      values (g1, '00000000-0000-0000-0000-0000000000b1') on conflict do nothing;
    if not exists (select 1 from public.students where group_id = g1) then
      insert into public.students (group_id, full_name, email) values
        (g1, 'Test Student 1', 'ts1@example.com'),
        (g1, 'Test Student 2', 'ts2@example.com'),
        (g1, 'Test Student 3', 'ts3@example.com');
    end if;
  end if;

  if g2 is not null then
    insert into public.assignments (group_id, volunteer_id)
      values (g2, '00000000-0000-0000-0000-0000000000b2') on conflict do nothing;
    if not exists (select 1 from public.students where group_id = g2) then
      insert into public.students (group_id, full_name, email) values
        (g2, 'Test Student 4', 'ts4@example.com'),
        (g2, 'Test Student 5', 'ts5@example.com');
    end if;
  end if;
end $$;
