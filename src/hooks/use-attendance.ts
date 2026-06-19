import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { fetchReportData } from '@/lib/report'
import type { AttendanceRecord } from '@/types'

export interface AttendanceUpsert {
  group_id: string
  student_id: string
  volunteer_id: string
  session_date: string
  contribution: number | null
  notes: string
}

/** 某小组某次课的出勤/评估记录。 */
export function useAttendance(groupId: string | undefined, sessionDate: string) {
  return useQuery({
    queryKey: ['attendance', groupId, sessionDate],
    enabled: !!groupId && !!sessionDate,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('attendance_records')
        .select('*')
        .eq('group_id', groupId as string)
        .eq('session_date', sessionDate)
      if (error) throw error
      return (data ?? []) as AttendanceRecord[]
    },
  })
}

/** 批量 upsert 评估（同一 student+date 已存在则更新）。 */
export function useSaveAttendance() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (rows: AttendanceUpsert[]) => {
      const { error } = await supabase
        .from('attendance_records')
        .upsert(rows, { onConflict: 'student_id,session_date' })
      if (error) throw error
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['attendance'] })
      void qc.invalidateQueries({ queryKey: ['attendance-report'] })
    },
  })
}

/** 「学员 × 周」报表数据（管理员专用，可按班级筛选）。 */
export function useAttendanceReport(classId: string | undefined) {
  return useQuery({
    queryKey: ['attendance-report', classId ?? 'all'],
    queryFn: () => fetchReportData(classId),
  })
}
