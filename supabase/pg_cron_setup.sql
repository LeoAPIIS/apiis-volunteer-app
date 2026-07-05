-- pg_cron 定时任务（在 Supabase SQL Editor 运行一次；时间为 UTC）
-- 依赖 20260620110000_per_curriculum_reminders 里的 run_*(boolean, text) 函数。
-- 按课程分天发，摊开每周邮件量（UTC+8 晚 8:00 = UTC 12:00）：
--   周四 MMin 6 可用性 · 周五 MMin 7 可用性
--   周六/周日 补位：覆盖全部课程缺口，周六发给 MMin 6 志愿者、周日发给 MMin 7 志愿者（任何人可认领）

create extension if not exists pg_cron;

-- 幂等：取消所有同名旧任务（含早期的两个全量任务）
do $$
declare j text;
begin
  foreach j in array array[
    'weekly-availability-check', 'summarize-coverage',
    'availability-mmin6', 'availability-mmin7', 'coverage-mmin6', 'coverage-mmin7',
    'expire-coverage'
  ] loop
    if exists (select 1 from cron.job where jobname = j) then perform cron.unschedule(j); end if;
  end loop;
end $$;

-- 可用性提醒（true = 同时发邮件）
select cron.schedule('availability-mmin6', '0 12 * * 4',  -- 周四 20:00 UTC+8
  $$ select public.run_weekly_availability_check(true, 'MMin 6'); $$);
select cron.schedule('availability-mmin7', '0 12 * * 5',  -- 周五 20:00 UTC+8
  $$ select public.run_weekly_availability_check(true, 'MMin 7'); $$);

-- 补位征集（覆盖全部课程缺口；p_curriculum 仅决定收件人那一批；true = 同时发邮件）
-- 补位征集:每周六 23:00 UTC+8(在可用性截止 22:59 之后),发给全体志愿者(补位可跨课程认领)
select cron.schedule('coverage-all', '0 15 * * 6',        -- 周六 23:00 UTC+8
  $$ select public.run_summarize_coverage(true, null); $$);

-- 每周三清除上周的临时补位分配（被补周一已过去的）
select cron.schedule('expire-coverage', '0 1 * * 3',      -- 周三 09:00 UTC+8
  $$ select public.expire_coverage_assignments(); $$);

-- 每周三清空「原负责志愿者到没到」的临时管理标记
select cron.schedule('clear-group-checkmarks', '0 1 * * 3',  -- 周三 09:00 UTC+8
  $$ select public.clear_group_check_marks(); $$);

-- 每周三清空「管理员手动指派」的分配(只留导入的原负责人)
select cron.schedule('clear-manual-assignments', '0 1 * * 3',  -- 周三 09:00 UTC+8
  $$ select public.clear_manual_assignments(); $$);

-- 查看：select jobname, schedule, active from cron.job order by jobname;
-- 取消单个：select cron.unschedule('availability-mmin6');
