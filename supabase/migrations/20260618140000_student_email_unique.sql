-- 学生以 email 为唯一基准（姓名可能重名）。
-- 允许多个 NULL（历史/无邮箱数据），非空 email 唯一。
-- 注意：若已有重复的非空 email，加约束会失败 —— 需先人工去重再跑本迁移。

-- 统一小写，避免大小写造成的“假重复”
update public.students set email = lower(email)
 where email is not null and email <> lower(email);

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'students_email_unique') then
    alter table public.students add constraint students_email_unique unique (email);
  end if;
end $$;
