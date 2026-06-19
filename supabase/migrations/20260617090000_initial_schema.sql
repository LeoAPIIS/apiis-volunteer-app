-- APIIS 志愿者管理 — 初始 schema（表、约束、索引）
-- 函数/触发器见 ..._functions_triggers.sql；RLS 策略见 ..._rls_policies.sql

create extension if not exists pgcrypto with schema extensions;

-- profiles：用户资料，1:1 关联 auth.users
create table public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  full_name  text not null default '',
  role       text not null default 'volunteer' check (role in ('admin', 'volunteer')),
  phone      text,
  created_at timestamptz not null default now()
);

-- cohorts：学期 / 期次
create table public.cohorts (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  start_date date,
  end_date   date,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

-- groups：Zoom 小组
create table public.groups (
  id          uuid primary key default gen_random_uuid(),
  cohort_id   uuid not null references public.cohorts (id) on delete cascade,
  name        text not null,
  zoom_link   text,
  meeting_day text,                       -- 上课日，如 'Monday'
  created_at  timestamptz not null default now()
);

-- students：学员
create table public.students (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.groups (id) on delete cascade,
  full_name  text not null,
  email      text,
  created_at timestamptz not null default now()
);

-- assignments：小组 ↔ 志愿者 分配关系
create table public.assignments (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups (id) on delete cascade,
  volunteer_id uuid not null references public.profiles (id) on delete cascade,
  assigned_at  timestamptz not null default now(),
  unique (group_id, volunteer_id)
);

-- attendance_records：出勤与表现记录（核心表）
create table public.attendance_records (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups (id) on delete cascade,
  student_id   uuid not null references public.students (id) on delete cascade,
  volunteer_id uuid references public.profiles (id) on delete set null,  -- 填写人
  session_date date not null,
  attended     boolean not null default false,
  video_on     boolean not null default false,
  contributed  boolean not null default false,
  notes        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  -- 一个学员在某次课只有一条记录 → 支持「存在则更新」的 upsert
  unique (student_id, session_date)
);

-- availability：每周可用性回馈
create table public.availability (
  id            uuid primary key default gen_random_uuid(),
  volunteer_id  uuid not null references public.profiles (id) on delete cascade,
  week_start_date date not null,          -- 该周的周一日期
  is_available  boolean,                  -- null = 尚未回复
  responded_at  timestamptz,
  created_at    timestamptz not null default now(),
  unique (volunteer_id, week_start_date)
);

-- coverage_requests：补位请求
create table public.coverage_requests (
  id             uuid primary key default gen_random_uuid(),
  group_id       uuid not null references public.groups (id) on delete cascade,
  week_start_date date not null,
  reason         text,
  status         text not null default 'open' check (status in ('open', 'covered')),
  covered_by     uuid references public.profiles (id) on delete set null,
  created_at     timestamptz not null default now(),
  unique (group_id, week_start_date)
);

-- notifications：站内通知
create table public.notifications (
  id           uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  type         text not null check (type in ('weekly_check', 'coverage_request', 'general')),
  title        text not null,
  body         text,
  is_read      boolean not null default false,
  related_id   uuid,                      -- 关联的 coverage_request 等（保持灵活，不加 FK）
  created_at   timestamptz not null default now()
);

-- 索引：RLS 子查询与常见过滤会用到
create index idx_groups_cohort           on public.groups (cohort_id);
create index idx_students_group          on public.students (group_id);
create index idx_assignments_volunteer   on public.assignments (volunteer_id);
create index idx_assignments_group       on public.assignments (group_id);
create index idx_attendance_group        on public.attendance_records (group_id);
create index idx_attendance_student      on public.attendance_records (student_id);
create index idx_attendance_session_date on public.attendance_records (session_date);
create index idx_availability_volunteer  on public.availability (volunteer_id);
create index idx_availability_week       on public.availability (week_start_date);
create index idx_coverage_status         on public.coverage_requests (status);
create index idx_coverage_week           on public.coverage_requests (week_start_date);
create index idx_notifications_recipient on public.notifications (recipient_id);
