-- 迁移：4 个真实班级 + 各自的小组；评估改为单一 Contribution(0-3)
-- 说明：沿用 cohorts 表作为「班级(class)」层级；前端 UI 以 "Class" 呈现。
-- 本迁移可在已部署的库上安全运行一次。

-- 1) 移除初期的测试期次（级联删除 Group A/B/C 及其学员/出勤/分配）
delete from public.cohorts where id = '00000000-0000-0000-0000-0000000000c1';

-- 2) attendance_records：评估从「出席/视频/贡献」三个布尔，改为单一 contribution 分数
--    (0-3，可空 = 未评估)
alter table public.attendance_records
  drop column if exists attended,
  drop column if exists video_on,
  drop column if exists contributed,
  add column if not exists contribution smallint check (contribution >= 0 and contribution <= 3);

-- 3) groups 增加 (cohort_id, name) 唯一约束（防重名 + 支持幂等导入）
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'groups_cohort_name_unique') then
    alter table public.groups add constraint groups_cohort_name_unique unique (cohort_id, name);
  end if;
end $$;

-- 4) 四个班级
insert into public.cohorts (id, name, is_active) values
  ('00000000-0000-0000-0000-0000000060a0', 'MMin 6P Monday Morning',  true),
  ('00000000-0000-0000-0000-0000000060b0', 'MMin 6L Tuesday Night',   true),
  ('00000000-0000-0000-0000-0000000070a0', 'MMin 7P Tuesday Morning', true),
  ('00000000-0000-0000-0000-0000000070b0', 'MMin 7L Monday Night',    true)
on conflict (id) do nothing;

-- 5) 各班级的小组 Group 1..N（共 28+43+21+64 = 156 个）
insert into public.groups (cohort_id, name, meeting_day)
select c.cid, 'Group ' || g, c.day
from (values
  ('00000000-0000-0000-0000-0000000060a0'::uuid, 28, 'Monday'),
  ('00000000-0000-0000-0000-0000000060b0'::uuid, 43, 'Tuesday'),
  ('00000000-0000-0000-0000-0000000070a0'::uuid, 21, 'Tuesday'),
  ('00000000-0000-0000-0000-0000000070b0'::uuid, 64, 'Monday')
) as c(cid, n, day)
cross join lateral generate_series(1, c.n) as g
on conflict (cohort_id, name) do nothing;
