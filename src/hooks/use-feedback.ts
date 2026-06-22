import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

export interface Feedback {
  id: string
  user_id: string | null
  full_name: string | null
  message: string
  created_at: string
  resolved: boolean
  resolved_at: string | null
}

/** 提交反馈（任何登录用户）。 */
export function useSubmitFeedback() {
  return useMutation({
    mutationFn: async (vars: { userId: string; fullName: string; message: string }) => {
      const { error } = await supabase.from('feedback').insert({
        user_id: vars.userId,
        full_name: vars.fullName,
        message: vars.message,
      })
      if (error) throw error
    },
  })
}

/** 反馈列表（管理员看全部；普通用户只看自己的——由 RLS 决定）。 */
export function useFeedback() {
  return useQuery({
    queryKey: ['feedback'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('feedback')
        .select('*')
        .order('created_at', { ascending: false })
      if (error) throw error
      return (data ?? []) as Feedback[]
    },
  })
}

/** 标记反馈为已解决 / 重新打开（仅管理员，RLS 限制）。 */
export function useSetFeedbackResolved() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (vars: { id: string; resolved: boolean }) => {
      const { error } = await supabase
        .from('feedback')
        .update({
          resolved: vars.resolved,
          resolved_at: vars.resolved ? new Date().toISOString() : null,
        })
        .eq('id', vars.id)
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['feedback'] }),
  })
}
