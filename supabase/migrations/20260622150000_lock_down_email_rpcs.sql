-- 安全加固 H1 + H2:锁定邮件相关 RPC,关闭 anon/public 的直达入口。
-- 背景:Postgres 默认把函数 EXECUTE 授予 PUBLIC,本项目从未撤销 → 任何持 anon key 者(前端公开)可直接:
--   · 调 app_send_email,用机构已验证域名群发任意邮件(H1);
--   · 调 run_*,触发邮件群发 + 写数据——其旧门控 `auth.uid() is not null and not is_admin()`
--     对「未登录(anon, auth.uid() 为 null)」不生效,故 anon 能绕过(H2)。

-- 1) 清理 run_* 的历史重载(0 参 / 1 参),只保留当前 (boolean, text)。
--    cron 调用的是 2 参版本,不受影响;前端「Run now」(无参调用)今后解析到当前(按课程)版本。
drop function if exists public.run_weekly_availability_check();
drop function if exists public.run_weekly_availability_check(boolean);
drop function if exists public.run_summarize_coverage();
drop function if exists public.run_summarize_coverage(boolean);

-- 2) H1:app_send_email 不对外开放。仅供 SECURITY DEFINER 的 run_*(以 owner 身份)内部调用,
--    cron / 管理员触发 run_* 的发信链路照常工作;任何客户端直调被拒。
revoke execute on function public.app_send_email(text, text, text) from public, anon, authenticated;

-- 3) H2:run_* 仅 authenticated 可调(内部门控仍会拦下非管理员);撤销 anon / public 直达。
--    cron 以 job owner 身份运行,不依赖这些 grant,照常工作。
revoke execute on function public.run_weekly_availability_check(boolean, text) from public, anon;
revoke execute on function public.run_summarize_coverage(boolean, text) from public, anon;
grant  execute on function public.run_weekly_availability_check(boolean, text) to authenticated;
grant  execute on function public.run_summarize_coverage(boolean, text) to authenticated;
