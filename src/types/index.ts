// 应用级共享类型（与 Supabase 迁移保持一致）。

export type UserRole = 'super_admin' | 'admin' | 'volunteer'

export interface Profile {
  id: string
  full_name: string
  role: UserRole
  phone: string | null
  created_at: string
}

/** cohorts 表既作为「班级 class」层级（UI 显示 Class）。 */
export interface Cohort {
  id: string
  name: string
  start_date: string | null
  end_date: string | null
  is_active: boolean
  created_at: string
}

export interface Group {
  id: string
  cohort_id: string
  name: string
  zoom_link: string | null
  meeting_day: string | null
  created_at: string
}

export interface Student {
  id: string
  group_id: string
  full_name: string
  email: string | null
  created_at: string
}

export interface Assignment {
  id: string
  group_id: string
  volunteer_id: string
  assigned_at: string
}

export interface AttendanceRecord {
  id: string
  group_id: string
  student_id: string
  volunteer_id: string | null
  session_date: string
  contribution: number | null // 0-3，null = 未评估
  notes: string | null
  created_at: string
  updated_at: string
}

export interface Notification {
  id: string
  recipient_id: string
  type: 'weekly_check' | 'coverage_request' | 'general'
  title: string
  body: string | null
  is_read: boolean
  related_id: string | null
  created_at: string
}

export interface AppSettings {
  id: boolean
  reminders_enabled: boolean
  term_break_start: string | null
  term_break_end: string | null
  updated_at: string
}
