-- Email 提醒配置（Resend + Supabase Vault）—— 在 SQL Editor 运行一次
--
-- 前置：
--   1) 注册 https://resend.com，创建一个 API key（re_ 开头）。
--   2) 在 Resend 验证一个发件域名（生产用）；测试可用 onboarding@resend.dev 作为发件人。
--   3) 确保项目已启用 pg_net（迁移里会自动 create extension）。
--
-- 把密钥存入 Vault（不要放进普通表，app_settings 对所有登录用户可读）：

select vault.create_secret('re_xxxxxxxxxxxxxxxx', 'resend_api_key',    'Resend API key');
select vault.create_secret('APIIS Volunteers <noreply@yourdomain.com>', 'resend_from_email', 'Reminder sender');
-- 可选：邮件里「打开 App」的链接（部署后填真实地址）
select vault.create_secret('https://your-app.vercel.app', 'app_url', 'App URL used in email links');

-- 更新某个密钥（先查 id）：
--   select id, name from vault.secrets;
--   select vault.update_secret('<secret-id>', 're_new_key', 'resend_api_key', 'Resend API key');

-- 验证读取（应能看到 name；decrypted_secret 仅特权角色可见）：
--   select name from vault.decrypted_secrets;

-- 配置完成后：
--   * 周末 cron 会自动发邮件（pg_cron_setup.sql 里以 true 调用）。
--   * 想立刻测试发信，可手动：select public.run_weekly_availability_check(true);
--     （注意：会给「所有志愿者邮箱」发信——测试账号是 @apiis.test 假域名，不会真正送达。）
