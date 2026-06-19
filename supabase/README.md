# Supabase 数据库（Phase 1）

本目录包含 APIIS 志愿者管理 App 的数据库 schema、RLS 策略与种子数据。

```
supabase/
├── migrations/
│   ├── 20260617090000_initial_schema.sql      表、约束、索引
│   ├── 20260617090100_functions_triggers.sql  辅助函数 + 触发器
│   └── 20260617090200_rls_policies.sql         启用 RLS + 所有策略
├── seed.sql                                     测试数据（账号 + 业务数据）
└── README.md
```

## 数据模型概览

9 张表：`profiles` `cohorts` `groups` `students` `assignments` `attendance_records`
`availability` `coverage_requests` `notifications`（字段见 PLAN.md 第 3 节）。

## 权限模型（RLS）

- **admin**：除 `notifications` 外的所有表全权读写；`notifications` 仅能读自己的。
- **volunteer**：
  - 读写自己被分配小组（`assignments`）对应的 `attendance_records`、`students`（只读）；
  - 读写自己的 `availability`；
  - 读 `open` 的 `coverage_requests`，可将其改为 `covered` 认领；
  - 读/改自己的 `notifications`。
- **anon（未登录）**：无任何策略 → 默认全部拒绝。

角色判断通过 `public.is_admin()` / `public.is_assigned_to_group()` 两个
`SECURITY DEFINER` 函数完成（绕过 RLS，避免在 `profiles` 策略中递归）。
防越权：`guard_profile_role` 触发器禁止非管理员修改自己的 `role`。

---

## 如何应用到你的 Supabase 项目

### 方式 A：Supabase CLI（推荐）

```bash
# 1. 安装 CLI（macOS）
brew install supabase/tap/supabase

# 2. 在项目根目录初始化（生成 config.toml；保留已有 migrations/ 与 seed.sql）
supabase init

# 3. 关联到你的云端项目（在 Dashboard > Project Settings > General 获取 ref）
supabase login
supabase link --project-ref <your-project-ref>

# 4. 推送迁移到云端
supabase db push

# 5. （可选）执行种子数据
#    云端没有内置 seed 命令，可用 psql 连接后执行，或在 SQL Editor 粘贴 seed.sql：
psql "<your-connection-string>" -f supabase/seed.sql
```

本地全栈开发（需要 Docker）：

```bash
supabase start          # 启动本地 Postgres + Auth 等
supabase db reset       # 重建本地库：跑全部迁移 + 自动执行 seed.sql
# 生成 TypeScript 类型（Phase 2/3 会用到）：
supabase gen types typescript --local > src/types/database.ts
```

### 方式 B：Dashboard SQL Editor（无需 CLI）

1. 打开 Supabase 项目 → **SQL Editor**。
2. 按文件名顺序，依次把 3 个 migration 文件内容粘贴执行：
   `initial_schema` → `functions_triggers` → `rls_policies`。
3. 把 `seed.sql` 内容粘贴执行（只需一次）。
   - 若「创建 auth 用户」一段报错（GoTrue 版本差异），改为：
     **Authentication → Users → Add user** 手动创建 3 个测试账号，
     然后执行 `seed.sql` 末尾被注释的「按邮箱设置角色」片段。

---

## 测试账号（密码均为 `apiis1234`）

| 邮箱 | 角色 | 备注 |
|------|------|------|
| admin@apiis.test | admin | 管理员 |
| volunteer1@apiis.test | volunteer | 已分配 Group A |
| volunteer2@apiis.test | volunteer | 已分配 Group B |

> ⚠️ 仅供测试，生产环境请删除这些账号并使用真实邮箱。

## 本地校验说明

这些 SQL 已在一次性 Postgres 16 容器（叠加最小化的 `auth` 环境垫片）中
完整跑通：建表、函数、触发器、全部 RLS 策略、以及 seed。详见提交说明。
真正的 GoTrue auth 细节请在你的 Supabase 项目上最终确认。
