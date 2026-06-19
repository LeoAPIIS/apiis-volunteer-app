# APIIS 志愿者管理 App — Claude Code 执行计划

> 把这份文件放进项目根目录（例如命名为 `PLAN.md`），然后在 Claude Code 中按阶段（Phase）逐步执行。每个阶段末尾都有给 Claude Code 的具体指令，可直接复制粘贴。

---

## 1. 项目概述

为 APIIS 线上培训项目构建一个 Web 应用，用于管理 100+ 名志愿者对学期内学员 Zoom 课程的监督工作。

### 核心功能
1. **出勤与表现记录表**
   - 志愿者进入分配给自己的 Zoom 小组，记录每位学员的：是否出席、是否开视频、是否对讨论有贡献、其他备注。
   - 表格可导出（Excel / CSV）。
   - 权限隔离：每名志愿者只能看到/填写自己被分配的小组；管理员负责把小组分配给志愿者。

2. **每周可用性提醒与调度机制**
   - 每周六、周日自动提醒志愿者，询问下一周是否可以参加监督工作。
   - 收集回馈后，汇总哪些小组的志愿者本周无法参加。
   - 把"缺人小组"的信息推送给全体志愿者，征集其他志愿者补位。

### 技术选型（基于已确认偏好）
- **前端**：TypeScript + React + Vite，桌面端为主（响应式以兼顾移动）。
- **UI**：Tailwind CSS + shadcn/ui。
- **后端 / 数据 / 认证 / 权限**：Supabase（Postgres + Auth + Row Level Security + Edge Functions + 定时任务 pg_cron）。
- **短信提醒**：Twilio（通过 Supabase Edge Function 调用）。
- **App 内推送**：站内通知表 + 实时订阅（Supabase Realtime）。
- **导出**：前端用 SheetJS (xlsx) 生成下载文件。

---

## 2. 角色与权限模型

| 角色 | 权限 |
|------|------|
| **管理员 (admin)** | 管理志愿者、管理小组、把小组分配给志愿者、查看全部记录、导出全部数据、查看可用性汇总、触发/管理提醒 |
| **志愿者 (volunteer)** | 只能查看与填写分配给自己的小组的出勤表；填写每周可用性；接收并响应补位请求 |

权限通过 Supabase Row Level Security (RLS) 在数据库层强制执行，而非仅靠前端隐藏。

---

## 3. 数据模型（Supabase / Postgres）

```
profiles            -- 用户资料（关联 auth.users）
  id (uuid, FK auth.users)
  full_name
  role            -- 'admin' | 'volunteer'
  phone           -- 用于短信
  created_at

cohorts             -- 学期 / 期次
  id
  name            -- 如 "2026 Spring"
  start_date
  end_date
  is_active

groups              -- Zoom 小组
  id
  cohort_id (FK)
  name            -- 如 "Group A"
  zoom_link
  meeting_day     -- 上课日

students            -- 学员
  id
  group_id (FK)
  full_name
  email

assignments         -- 小组 ↔ 志愿者 分配关系
  id
  group_id (FK)
  volunteer_id (FK profiles)
  assigned_at

attendance_records  -- 出勤与表现记录（核心表）
  id
  group_id (FK)
  student_id (FK)
  volunteer_id (FK)   -- 填写人
  session_date
  attended            -- bool 是否出席
  video_on            -- bool 是否开视频
  contributed         -- bool 是否有贡献
  notes               -- text 备注
  created_at
  updated_at

availability        -- 每周可用性回馈
  id
  volunteer_id (FK)
  week_start_date     -- 该周的周一日期
  is_available        -- bool
  responded_at

coverage_requests   -- 补位请求
  id
  group_id (FK)
  week_start_date
  reason              -- 原志愿者不可用
  status              -- 'open' | 'covered'
  covered_by (FK profiles, nullable)
  created_at

notifications       -- 站内通知
  id
  recipient_id (FK profiles)
  type                -- 'weekly_check' | 'coverage_request' | 'general'
  title
  body
  is_read
  related_id          -- 关联的 coverage_request 等
  created_at
```

---

## 4. 分阶段执行计划（给 Claude Code）

### Phase 0 — 项目初始化
目标：搭好骨架，能本地跑起来。

给 Claude Code 的指令：
```
初始化一个新项目：
- 使用 Vite + React + TypeScript
- 安装并配置 Tailwind CSS 和 shadcn/ui
- 安装 @supabase/supabase-js、react-router-dom、@tanstack/react-query、xlsx
- 创建基础目录结构：src/components, src/pages, src/lib, src/hooks, src/types
- 创建 src/lib/supabase.ts 初始化 Supabase 客户端（从环境变量读取 URL 和 anon key）
- 创建 .env.example，列出所需环境变量
- 配置基础路由：/login, /dashboard, /admin
- 确认 npm run dev 能正常启动
```

### Phase 1 — 数据库与权限
目标：在 Supabase 建好表结构和 RLS 策略。

给 Claude Code 的指令：
```
根据 PLAN.md 第 3 节的数据模型，编写 Supabase 迁移 SQL，放在 supabase/migrations/ 下：
- 创建所有表及外键
- 创建 profiles 表，并写一个触发器：当 auth.users 新增用户时自动创建 profile
- 为每张表启用 Row Level Security，并编写策略：
  * admin 可读写所有表
  * volunteer 只能读写 assignments 中分配给自己的 group 对应的 attendance_records
  * volunteer 只能读写自己的 availability 记录
  * volunteer 可读所有 open 状态的 coverage_requests，可把 status 改为 covered（认领补位）
  * notifications 只能被本人读取
- 写一个种子脚本 supabase/seed.sql，插入一个示例 cohort、几个 group、几名 student、一个 admin 和两个 volunteer 用于测试
给出在 Supabase 中执行这些迁移的步骤说明。
```

### Phase 2 — 认证与布局
目标：登录、按角色跳转、基础导航。

给 Claude Code 的指令：
```
实现认证：
- 登录页面（邮箱 + 密码，使用 Supabase Auth）
- 一个 AuthProvider（React Context），加载当前用户的 profile 和 role
- 受保护路由：未登录跳 /login；志愿者进 /dashboard，管理员进 /admin
- 通用布局组件（顶部栏含用户名、角色、登出按钮 + 通知铃铛入口）
```

### Phase 3 — 功能一：出勤与表现记录表
目标：志愿者填表 + 导出 + 管理员分配小组。

给 Claude Code 的指令：
```
实现志愿者端出勤记录功能：
- 志愿者仪表盘列出分配给自己的小组
- 点进某小组 + 选择 session_date 后，显示该组学员列表
- 每名学员一行，可勾选：出席、开视频、有贡献，并填写备注
- 保存到 attendance_records（同一 group+student+date 已存在则更新）
- 提供"导出"按钮，用 xlsx 把当前小组/日期范围的记录导出为 Excel
实现管理员端小组分配：
- 管理员可查看所有小组与志愿者
- 可把某小组分配给某志愿者（增删 assignments）
- 管理员可查看和导出所有小组的记录
确保所有数据访问都依赖 RLS，前端不要绕过权限。
```

### Phase 4 — 功能二：每周可用性提醒与调度
目标：定时提醒 + 收集回馈 + 汇总缺人 + 征集补位。

给 Claude Code 的指令：
```
实现可用性与补位调度：

数据库 / 定时任务（Supabase Edge Functions + pg_cron）：
- 写一个 Edge Function "weekly-availability-check"：
  * 为每位志愿者创建下周的 availability 记录（is_available 默认 null）
  * 为每位志愿者创建一条 type='weekly_check' 的站内通知
  * 通过 Twilio 给有手机号的志愿者发短信，附上回馈链接
- 用 pg_cron 配置该函数在每周六、周日定时运行
- 写一个 Edge Function "summarize-coverage"：
  * 找出本周 is_available=false 的志愿者所负责的小组
  * 为这些小组创建 coverage_requests（status='open'）
  * 给全体志愿者推送 type='coverage_request' 通知（站内 + 短信），询问谁能补位

前端：
- 志愿者收到每周提醒后，可在页面上回答"下周能否参加"（写入 availability）
- 通知中心页面：列出站内通知，未读高亮
- 补位请求列表：显示所有 open 的缺人小组，志愿者可点击"我来补位"（更新 coverage_request 并创建临时 assignment）
- 管理员可查看本周可用性汇总：哪些小组有人、哪些缺人、谁认领了补位

给出 Twilio 凭证如何配置为 Supabase secrets 的说明，以及如何部署 Edge Functions 的命令。
```

### Phase 5 — 收尾与上线
给 Claude Code 的指令：
```
- 添加加载态、错误提示、表单校验
- 增加移动端响应式适配（虽以桌面为主）
- 写 README：本地启动、环境变量、Supabase 部署、Twilio 配置步骤
- 给出部署到 Vercel/Netlify 的说明
- 做一遍端到端自测清单：管理员分配 → 志愿者填表导出 → 周末提醒 → 回馈缺人 → 补位
```

---

## 5. 需要你提前准备的东西
- 一个 Supabase 项目（免费版即可起步）：拿到 Project URL 和 anon/service key。
- 一个 Twilio 账号（如要短信）：Account SID、Auth Token、一个发送号码。
- 志愿者名单（姓名、邮箱、手机号）和小组划分，用于种子数据。

## 6. 给 Claude Code 的开场白（建议第一句话）
```
我有一份项目计划在 PLAN.md。请先读完整个文件，然后从 Phase 0 开始执行。
每完成一个 Phase 就停下来让我确认，再继续下一个。开始 Phase 0。
```
