import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import type { Group, Student } from '@/types'

export type GroupWithCohort = Group & { cohort: { name: string } | null }

/** 班级列表（cohorts 表）。 */
export function useClasses() {
  return useQuery({
    queryKey: ['classes'],
    queryFn: async () => {
      const { data, error } = await supabase.from('cohorts').select('id, name').order('name')
      if (error) throw error
      return (data ?? []) as { id: string; name: string }[]
    },
  })
}

/** 志愿者：自己被分配的小组（含所属班级名）。 */
export function useMyGroups(volunteerId: string | undefined) {
  return useQuery({
    queryKey: ['my-groups', volunteerId],
    enabled: !!volunteerId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('assignments')
        .select('group:groups(*, cohorts(name))')
        .eq('volunteer_id', volunteerId as string)
      if (error) throw error
      const rows = (data ?? []) as unknown as {
        group: (Group & { cohorts: { name: string } | null }) | null
      }[]
      return rows
        .map((r) => r.group)
        .filter((g): g is Group & { cohorts: { name: string } | null } => !!g)
        .map((g) => ({
          id: g.id,
          cohort_id: g.cohort_id,
          name: g.name,
          zoom_link: g.zoom_link,
          meeting_day: g.meeting_day,
          created_at: g.created_at,
          class_name: g.cohorts?.name ?? '',
        }))
        .sort(
          (a, b) =>
            a.class_name.localeCompare(b.class_name) ||
            a.name.localeCompare(b.name, undefined, { numeric: true }),
        )
    },
  })
}

/** 管理员：全部小组（含 cohort/class 名）。 */
export function useAllGroups() {
  return useQuery({
    queryKey: ['all-groups'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('groups')
        .select('*, cohort:cohorts(name)')
      if (error) throw error
      // 按「班级名 → 组号(数值)」排序，避免字典序的 Group 1,10,11,2…
      const rows = (data ?? []) as GroupWithCohort[]
      rows.sort(
        (a, b) =>
          (a.cohort?.name ?? '').localeCompare(b.cohort?.name ?? '') ||
          a.name.localeCompare(b.name, undefined, { numeric: true }),
      )
      return rows
    },
  })
}

/** 单个小组（含 cohort/class 名）。 */
export function useGroup(groupId: string | undefined) {
  return useQuery({
    queryKey: ['group', groupId],
    enabled: !!groupId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('groups')
        .select('*, cohort:cohorts(name)')
        .eq('id', groupId as string)
        .single()
      if (error) throw error
      return data as GroupWithCohort
    },
  })
}

/** 某小组的学员。 */
export function useStudents(groupId: string | undefined) {
  return useQuery({
    queryKey: ['students', groupId],
    enabled: !!groupId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('students')
        .select('*')
        .eq('group_id', groupId as string)
        .order('full_name')
      if (error) throw error
      return (data ?? []) as Student[]
    },
  })
}

/** 删除学生（管理员；RLS 允许）。会级联删除其出勤记录。 */
export function useDeleteStudent() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('students').delete().eq('id', id)
      if (error) throw error
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['students'] })
      void qc.invalidateQueries({ queryKey: ['attendance-report'] })
    },
  })
}
