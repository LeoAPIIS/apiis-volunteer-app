import { useMarkAllRead, useNotifications } from '@/hooks/use-scheduling'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'

export function NotificationsPage() {
  const { data: items, isLoading } = useNotifications()
  const markAll = useMarkAllRead()

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between gap-2">
        <h1 className="text-2xl font-semibold tracking-tight">Notifications</h1>
        <Button
          variant="outline"
          size="sm"
          disabled={markAll.isPending}
          onClick={() => markAll.mutate()}
        >
          Mark all read
        </Button>
      </div>

      {isLoading ? (
        <p className="text-muted-foreground text-sm">Loading…</p>
      ) : !items || items.length === 0 ? (
        <p className="text-muted-foreground text-sm">No notifications.</p>
      ) : (
        <div className="flex flex-col gap-2">
          {items.map((n) => (
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
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
