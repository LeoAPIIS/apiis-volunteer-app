-- 兜底:确保 availability 的 (volunteer_id, group_id, week_start_date) 唯一约束存在。
-- 背景:按组可用性迁移(20260623100000)的「加唯一约束」步骤在某线上库未生效,
-- 导致点 available 时 upsert 报 "no unique or exclusion constraint matching the ON CONFLICT specification"。
-- 本迁移幂等:列/非空/去重/约束都先判断再处理,反复运行安全。

alter table public.availability add column if not exists group_id uuid references public.groups (id) on delete cascade;

-- 清掉没有 group 的旧行(每人每周一条的遗留)
delete from public.availability where group_id is null;

-- 去重:同一 (volunteer, group, week) 只保留一条,否则加唯一约束会失败
delete from public.availability a
using public.availability b
where a.ctid < b.ctid
  and a.volunteer_id = b.volunteer_id
  and a.group_id = b.group_id
  and a.week_start_date = b.week_start_date;

alter table public.availability alter column group_id set not null;
alter table public.availability drop constraint if exists availability_volunteer_id_week_start_date_key;
alter table public.availability drop constraint if exists availability_vol_group_week_key;
alter table public.availability add constraint availability_vol_group_week_key unique (volunteer_id, group_id, week_start_date);
