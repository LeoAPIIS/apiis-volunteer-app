-- 区分分配来源,便于在组上用颜色区分三类人:
--   import   = 导入名单 / 本来的负责人  → 默认色
--   manual   = 管理员在界面手动指派      → 深蓝
--   补位(coverage)由 coverage_week 标识 → 浅绿(颜色优先级最高),故 source 只需区分 manual。
-- 已有数据默认 'import'(无法回溯区分历史上的手动指派,从此以后界面手动指派会标 'manual')。
alter table public.assignments
  add column if not exists source text not null default 'import'
  check (source in ('import', 'manual', 'coverage'));
