import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { todaySG } from '@/lib/date'
import type { AppSettings, Notification } from '@/types'

// ============================== 可用性（按组）==============================
/** 该志愿者本周的逐组可用性（每组一条）。 */
export function useMyAvailability(volunteerId: string | undefined, week: string) {
  return useQuery({
    queryKey: ['my-availability', volunteerId, week],
    enabled: !!volunteerId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('availability')
        .select('group_id, is_available')
        .eq('volunteer_id', volunteerId as string)
        .eq('week_start_date', week)
      if (error) throw error
      return (data ?? []) as { group_id: string; is_available: boolean | null }[]
    },
  })
}

/** 下周一是否为真实上课日（在 class_sessions 内）。用于休息周隐藏"可用性"询问。 */
export function useIsSessionWeek(week: string) {
  return useQuery({
    queryKey: ['is-session-week', week],
    enabled: !!week,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('class_sessions')
        .select('session_date')
        .eq('session_date', week)
        .limit(1)
      if (error) throw error
      return (data?.length ?? 0) > 0
    },
  })
}

/** 下一个真实上课日（>= 今天）。用于休息周时提示"何时复课"。 */
export function useNextSession() {
  return useQuery({
    queryKey: ['next-session'],
    queryFn: async () => {
      const today = todaySG()
      const { data, error } = await supabase
        .from('class_sessions')
        .select('session_date')
        .gte('session_date', today)
        .order('session_date', { ascending: true })
        .limit(1)
      if (error) throw error
      return (data?.[0]?.session_date as string | undefined) ?? null
    },
  })
}

export function useSetAvailability(volunteerId: string, week: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (vars: { groupId: string; isAvailable: boolean }) => {
      const { error } = await supabase.from('availability').upsert(
        {
          volunteer_id: volunteerId,
          group_id: vars.groupId,
          week_start_date: week,
          is_available: vars.isAvailable,
          responded_at: new Date().toISOString(),
        },
        { onConflict: 'volunteer_id,group_id,week_start_date' },
      )
      if (error) throw error
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['my-availability'] })
      void qc.invalidateQueries({ queryKey: ['week-availability'] })
    },
  })
}

// ============================== 通知 ==============================
export function useNotifications() {
  return useQuery({
    queryKey: ['notifications'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('notifications')
        .select('*')
        .order('created_at', { ascending: false })
      if (error) throw error
      return (data ?? []) as Notification[]
    },
  })
}

export function useUnreadCount() {
  return useQuery({
    queryKey: ['notifications-unread'],
    queryFn: async () => {
      const { count, error } = await supabase
        .from('notifications')
        .select('*', { count: 'exact', head: true })
        .eq('is_read', false)
        .neq('type', 'coverage_request')
      if (error) throw error
      return count ?? 0
    },
  })
}

export function useMarkAllRead() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async () => {
      const { error } = await supabase.from('notifications').update({ is_read: true }).eq('is_read', false)
      if (error) throw error
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['notifications'] })
      void qc.invalidateQueries({ queryKey: ['notifications-unread'] })
    },
  })
}

// ============================== 补位（志愿者）==============================
export function useOpenCoverageRequests() {
  return useQuery({
    queryKey: ['coverage-open'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('coverage_requests')
        .select('id, week_start_date, status, reason, groups(name, cohorts(name))')
        .eq('status', 'open')
        .order('week_start_date', { ascending: false })
      if (error) throw error
      return (data ?? []).map((r) => {
        const rec = r as unknown as {
          id: string
          week_start_date: string
          reason: string | null
          groups: { name: string; cohorts: { name: string } | null } | null
        }
        return {
          id: rec.id,
          week_start_date: rec.week_start_date,
          reason: rec.reason,
          group_name: rec.groups?.name ?? '',
          class_name: rec.groups?.cohorts?.name ?? '',
        }
      })
    },
  })
}

export function useClaimCoverage() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (requestId: string) => {
      const { error } = await supabase.rpc('claim_coverage', { p_request_id: requestId })
      if (error) throw error
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['coverage-open'] })
      void qc.invalidateQueries({ queryKey: ['coverage-week'] })
      void qc.invalidateQueries({ queryKey: ['my-groups'] })
    },
  })
}

/** 管理员：重新放出补位(认领人来不了 → 释放并改回 open)。 */
export function useReopenCoverage() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (requestId: string) => {
      const { error } = await supabase.rpc('admin_reopen_coverage', { p_request_id: requestId })
      if (error) throw error
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['coverage-week'] })
      void qc.invalidateQueries({ queryKey: ['coverage-open'] })
      void qc.invalidateQueries({ queryKey: ['assignments'] })
      void qc.invalidateQueries({ queryKey: ['my-groups'] })
    },
  })
}

// ============================== 管理员：设置 ==============================
export function useAppSettings() {
  return useQuery({
    queryKey: ['app-settings'],
    queryFn: async () => {
      const { data, error } = await supabase.from('app_settings').select('*').eq('id', true).single()
      if (error) throw error
      return data as AppSettings
    },
  })
}

export function useUpdateAppSettings() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (patch: {
      reminders_enabled?: boolean
      term_break_start?: string | null
      term_break_end?: string | null
    }) => {
      const { error } = await supabase
        .from('app_settings')
        .update({ ...patch, updated_at: new Date().toISOString() })
        .eq('id', true)
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['app-settings'] }),
  })
}

// ============================== 管理员：本周汇总 ==============================
export function useWeekAvailability(week: string) {
  return useQuery({
    queryKey: ['week-availability', week],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('availability')
        .select('is_available, volunteer:profiles(full_name), group:groups(name, cohorts(name))')
        .eq('week_start_date', week)
      if (error) throw error
      return (data ?? []).map((r) => {
        const rec = r as unknown as {
          is_available: boolean | null
          volunteer: { full_name: string } | null
          group: { name: string; cohorts: { name: string } | null } | null
        }
        return {
          is_available: rec.is_available,
          name: rec.volunteer?.full_name ?? '',
          group_name: rec.group?.name ?? '',
          class_name: rec.group?.cohorts?.name ?? '',
        }
      })
    },
  })
}

export function useWeekCoverage(week: string) {
  return useQuery({
    queryKey: ['coverage-week', week],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('coverage_requests')
        .select('id, status, groups(name, cohorts(name)), coverer:profiles(full_name)')
        .eq('week_start_date', week)
      if (error) throw error
      return (data ?? []).map((r) => {
        const rec = r as unknown as {
          id: string
          status: string
          groups: { name: string; cohorts: { name: string } | null } | null
          coverer: { full_name: string } | null
        }
        return {
          id: rec.id,
          status: rec.status,
          group_name: rec.groups?.name ?? '',
          class_name: rec.groups?.cohorts?.name ?? '',
          coverer: rec.coverer?.full_name ?? null,
        }
      })
    },
  })
}

// ============================== 管理员：手动触发 ==============================
export function useRunWeeklyCheck() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async () => {
      // 手动触发:显式 p_send_email=false → 仅站内,绝不发邮件;p_curriculum=null → 全部志愿者
      const { data, error } = await supabase.rpc('run_weekly_availability_check', {
        p_send_email: false,
        p_curriculum: null,
      })
      if (error) throw error
      return data as number
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['week-availability'] })
      void qc.invalidateQueries({ queryKey: ['notifications'] })
      void qc.invalidateQueries({ queryKey: ['notifications-unread'] })
    },
  })
}

export function useRunSummarize() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async () => {
      // 手动触发:显式 p_send_email=false → 仅站内,绝不发邮件;p_curriculum=null → 全部志愿者
      const { data, error } = await supabase.rpc('run_summarize_coverage', {
        p_send_email: false,
        p_curriculum: null,
      })
      if (error) throw error
      return data as number
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['coverage-week'] })
      void qc.invalidateQueries({ queryKey: ['coverage-open'] })
      void qc.invalidateQueries({ queryKey: ['notifications'] })
    },
  })
}
