import { useEffect } from 'react'
import { useAuth } from '@/lib/auth'
import { useMarkAllRead, useNotifications } from '@/hooks/use-scheduling'
import { cn } from '@/lib/utils'
import { AvailabilityActions } from '@/components/availability-actions'
import { CoverageNeeded } from '@/components/coverage-needed'

export function NotificationsPage() {
  const { user } = useAuth()
  const { data: items, isLoading } = useNotifications()
  const { mutate: markAllRead } = useMarkAllRead()
  // 通用「Coverage needed」通知与上面可认领的卡片重复，隐藏它(卡片才是可操作的)
  const visible = (items ?? []).filter((n) => n.type !== 'coverage_request')

  // 打开通知页即自动标记为已读(红点随之清零);标记后 items 重新拉取、无未读 → 不再触发
  useEffect(() => {
    if ((items ?? []).some((n) => !n.is_read)) markAllRead()
  }, [items, markAllRead])

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-semibold tracking-tight">Notifications</h1>

      <CoverageNeeded />

      {isLoading ? (
        <p className="text-muted-foreground text-sm">Loading…</p>
      ) : visible.length === 0 ? (
        <p className="text-muted-foreground text-sm">No notifications.</p>
      ) : (
        <div className="flex flex-col gap-2">
          {visible.map((n) => {
            // weekly_check 通知里直接给可用性按钮；周次从正文(…week of YYYY-MM-DD…)解析
            const availWeek =
              n.type === 'weekly_check' ? (n.body?.match(/\d{4}-\d{2}-\d{2}/)?.[0] ?? null) : null
            return (
              <div
                key={n.id}
                className={cn(
                  'rounded-md border p-3',
                  !n.is_read && 'border-l-primary bg-muted/40 border-l-4',
                )}
              >
                <div className="flex items-center justify-between gap-2">
                  <p className="font-medium">{n.title}</p>
                  <span className="text-muted-foreground text-xs">
                    {new Date(n.created_at).toLocaleString()}
                  </span>
                </div>
                {n.body && <p className="text-muted-foreground mt-1 text-sm">{n.body}</p>}
                {availWeek && user && <AvailabilityActions volunteerId={user.id} week={availWeek} />}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
