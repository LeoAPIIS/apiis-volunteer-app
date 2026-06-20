-- pg_cron 定时任务（在 Supabase SQL Editor 运行一次；时间为 UTC）
-- 依赖 20260620110000_per_curriculum_reminders 里的 run_*(boolean, text) 函数。
-- 按课程分天发，摊开每周邮件量（UTC+8 晚 8:00 = UTC 12:00）：
--   周四 MMin 6 可用性 · 周五 MMin 7 可用性 · 周六 MMin 6 补位 · 周日 MMin 7 补位

create extension if not exists pg_cron;

-- 幂等：取消所有同名旧任务（含早期的两个全量任务）
do $$
declare j text;
begin
  foreach j in array array[
    'weekly-availability-check', 'summarize-coverage',
    'availability-mmin6', 'availability-mmin7', 'coverage-mmin6', 'coverage-mmin7'
  ] loop
    if exists (select 1 from cron.job where jobname = j) then perform cron.unschedule(j); end if;
  end loop;
end $$;

-- 可用性提醒（true = 同时发邮件）
select cron.schedule('availability-mmin6', '0 12 * * 4',  -- 周四 20:00 UTC+8
  $$ select public.run_weekly_availability_check(true, 'MMin 6'); $$);
select cron.schedule('availability-mmin7', '0 12 * * 5',  -- 周五 20:00 UTC+8
  $$ select public.run_weekly_availability_check(true, 'MMin 7'); $$);

-- 补位汇总 + 征集（true = 同时发邮件）
select cron.schedule('coverage-mmin6', '0 12 * * 6',      -- 周六 20:00 UTC+8
  $$ select public.run_summarize_coverage(true, 'MMin 6'); $$);
select cron.schedule('coverage-mmin7', '0 12 * * 0',      -- 周日 20:00 UTC+8
  $$ select public.run_summarize_coverage(true, 'MMin 7'); $$);

-- 查看：select jobname, schedule, active from cron.job order by jobname;
-- 取消单个：select cron.unschedule('availability-mmin6');
