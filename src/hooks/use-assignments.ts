import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import type { Assignment, Profile } from '@/types'

/** 所有志愿者（管理员用）。 */
export function useVolunteers() {
  return useQuery({
    queryKey: ['volunteers'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .eq('role', 'volunteer')
        .order('full_name')
      if (error) throw error
      return (data ?? []) as Profile[]
    },
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
      const { error } = await supabase
        .from('assignments')
        .insert({ group_id: vars.groupId, volunteer_id: vars.volunteerId })
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['assignments'] }),
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
      void qc.invalidateQueries({ queryKey: ['volunteers'] })
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
      void qc.invalidateQueries({ queryKey: ['volunteers'] })
      void qc.invalidateQueries({ queryKey: ['assignments'] })
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
