-- pg_cron 定时任务（在 Supabase SQL Editor 运行一次；时间为 UTC，可按需调整）
-- 依赖 20260618100000_phase4_scheduling.sql 里的函数。

create extension if not exists pg_cron;

-- 幂等：先取消同名任务（若已存在）
do $$ begin
  if exists (select 1 from cron.job where jobname = 'weekly-availability-check') then
    perform cron.unschedule('weekly-availability-check');
  end if;
  if exists (select 1 from cron.job where jobname = 'summarize-coverage') then
    perform cron.unschedule('summarize-coverage');
  end if;
end $$;

-- 周五 12:00 UTC（= UTC+8 周五 20:00）：为下周创建可用性记录 + 提醒（true = 同时发邮件）
select cron.schedule(
  'weekly-availability-check', '0 12 * * 5',
  $$ select public.run_weekly_availability_check(true); $$
);

-- 周日 12:00 UTC（= UTC+8 周日 20:00）：汇总缺人小组并向全体征集补位（true = 同时发邮件）
select cron.schedule(
  'summarize-coverage', '0 12 * * 0',
  $$ select public.run_summarize_coverage(true); $$
);

-- 查看已排程任务：  select jobname, schedule, active from cron.job;
-- 取消：           select cron.unschedule('weekly-availability-check');
