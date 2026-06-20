-- 一次性清除 seed.sql 建立的测试数据：
--   • 3 个 @apiis.test 账号（admin / volunteer1 / volunteer2）
--   • 5 个 ts1..5@example.com 测试学员
-- 安全保证：仅按 seed 固定 UUID + 测试域名/邮箱定向删除；
--   绝不触碰 itsupport@apiis.org 或 CSV 导入的真实志愿者 / 学员。
-- 级联：删账号 → 自动清其 profiles / assignments / availability，并把
--   attendance_records.volunteer_id 置空（不删真实学员的出勤记录）；
--   删测试学员 → 级联删除其 attendance_records。
-- 在 Supabase → SQL Editor 运行。

begin;

-- 1) 测试学员（精确邮箱）
delete from public.students
 where lower(email) in (
   'ts1@example.com', 'ts2@example.com', 'ts3@example.com', 'ts4@example.com', 'ts5@example.com'
 );

-- 2) 测试账号（seed 的固定 UUID）
delete from auth.users
 where id in (
   '00000000-0000-0000-0000-0000000000a1',
   '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000b2'
 );

-- 3) 兜底：任何 @apiis.test 账号（itsupport@apiis.org 属 .org 域，绝不会被命中）
delete from auth.users
 where lower(email) like '%@apiis.test';

commit;

-- ── 验证（期望结果：0 / 0 / 1）──
select 'test accounts left' as check, count(*) as n from auth.users where lower(email) like '%@apiis.test'
union all
select 'test students left', count(*) from public.students
  where lower(email) in ('ts1@example.com','ts2@example.com','ts3@example.com','ts4@example.com','ts5@example.com')
union all
select 'itsupport intact', count(*) from auth.users where lower(email) = 'itsupport@apiis.org';
