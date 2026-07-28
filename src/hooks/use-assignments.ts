import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import type { Assignment, Profile } from '@/types'

/** 所有用户（管理员用，含 volunteer/admin/super_admin）。用于分配名单与名字解析——
 *  这样志愿者被提升为 admin 后,其已有分配仍能正确显示名字(不再 Unknown)。 */
export function useAllUsers() {
  return useQuery({
    queryKey: ['all-users'],
    queryFn: async () => {
      const { data, error } = await supabase.from('profiles').select('*').order('full_name')
      if (error) throw error
      return (data ?? []) as Profile[]
    },
  })
}

// ============== 临时管理标记:某组原负责志愿者本周到没到(不计入数据,每周三清空)==============
export type CheckStatus = 'present' | 'absent'

export function useGroupCheckMarks() {
  return useQuery({
    queryKey: ['group-check-marks'],
    queryFn: async () => {
      const { data, error } = await supabase.from('group_check_marks').select('group_id, status')
      if (error) throw error
      return (data ?? []) as { group_id: string; status: CheckStatus }[]
    },
  })
}

export function useSetGroupCheckMark() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (vars: { groupId: string; status: CheckStatus | null }) => {
      if (vars.status === null) {
        const { error } = await supabase
          .from('group_check_marks')
          .delete()
          .eq('group_id', vars.groupId)
        if (error) throw error
      } else {
        const { error } = await supabase.from('group_check_marks').upsert(
          { group_id: vars.groupId, status: vars.status, marked_at: new Date().toISOString() },
          { onConflict: 'group_id' },
        )
        if (error) throw error
      }
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['group-check-marks'] }),
  })
}

/** 所有分配关系（管理员用）。 */
export function useAssignments() {
  return useQuery({
    queryKey: ['assignments'],
    queryFn: async () => {
      const { data, error } = await supabase.from('assignments').select('*')
      if (error) throw error
      return (data ?? []) as Assignment[]
    },
  })
}

export function useAssignVolunteer() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (vars: { groupId: string; volunteerId: string }) => {
      // RPC：建立 manual 分配 + 同步关闭该组未认领的补位请求(覆盖人=被指派者)
      const { error } = await supabase.rpc('admin_assign_volunteer', {
        p_group_id: vars.groupId,
        p_volunteer_id: vars.volunteerId,
      })
      if (error) throw error
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['assignments'] })
      void qc.invalidateQueries({ queryKey: ['coverage-week'] })
      void qc.invalidateQueries({ queryKey: ['coverage-open'] })
    },
  })
}

export function useUnassign() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (assignmentId: string) => {
      const { error } = await supabase.from('assignments').delete().eq('id', assignmentId)
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['assignments'] }),
  })
}

/** 清空所有「志愿者→Group」分配（仅 super_admin，调用 RPC）。重传名单前重置用。 */
export function useClearAssignments() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.rpc('admin_clear_assignments')
      if (error) throw error
      return data as number
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['assignments'] })
      void qc.invalidateQueries({ queryKey: ['volunteer-activity'] })
      void qc.invalidateQueries({ queryKey: ['my-groups'] })
    },
  })
}

export interface VolunteerActivity {
  volunteer_id: string
  full_name: string
  email: string
  role: string
  assigned_groups: number
  sessions_recorded: number
  last_active: string | null
  coverage_count: number
}

/** 修改用户角色（管理员操作；RLS + guard 触发器都允许管理员改角色）。 */
export function useSetUserRole() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (vars: { id: string; role: 'admin' | 'volunteer' }) => {
      const { error } = await supabase.from('profiles').update({ role: vars.role }).eq('id', vars.id)
      if (error) throw error
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['volunteer-activity'] })
      void qc.invalidateQueries({ queryKey: ['all-users'] })
      void qc.invalidateQueries({ queryKey: ['assignments'] })
    },
  })
}

/** 删除志愿者（管理员;调用 RPC 删 auth 账号，级联清理）。 */
export function useDeleteVolunteer() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('admin_delete_volunteer', { p_id: id })
      if (error) throw error
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['volunteer-activity'] })
      void qc.invalidateQueries({ queryKey: ['all-users'] })
      void qc.invalidateQueries({ queryKey: ['assignments'] })
    },
  })
}

export interface AssignmentHistoryRow {
  id: string
  week_start_date: string
  source: string // 'manual' | 'coverage'
  group_name: string | null
  class_name: string | null
  volunteer_name: string | null
  volunteer_email: string | null
  archived_at: string
}

/** 分配历史（审计）：每周三清理前归档的 manual / coverage 分配。管理员只读。 */
export function useAssignmentHistory() {
  return useQuery({
    queryKey: ['assignment-history'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('assignment_history')
        .select(
          'id, week_start_date, source, group_name, class_name, volunteer_name, volunteer_email, archived_at',
        )
        .order('week_start_date', { ascending: false })
        .order('class_name')
        .order('group_name')
      if (error) throw error
      return (data ?? []) as AssignmentHistoryRow[]
    },
  })
}

/** 志愿者出席/活跃度（管理员专用，调用聚合 RPC）。 */
export function useVolunteerActivity() {
  return useQuery({
    queryKey: ['volunteer-activity'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('admin_volunteer_activity')
      if (error) throw error
      return (data ?? []) as VolunteerActivity[]
    },
  })
}
