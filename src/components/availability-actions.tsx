import { toast } from 'sonner'
import { useMyAvailability, useSetAvailability } from '@/hooks/use-scheduling'
import { Button } from '@/components/ui/button'

/** 可用性回复按钮（用于通知里的 weekly_check 通知，直接 Available / Unavailable）。 */
export function AvailabilityActions({ volunteerId, week }: { volunteerId: string; week: string }) {
  const { data } = useMyAvailability(volunteerId, week)
  const setAvail = useSetAvailability(volunteerId, week)
  const current = data?.is_available ?? null

  function set(v: boolean) {
    setAvail.mutate(v, {
      onSuccess: () => toast.success('Response saved'),
      onError: (e) => toast.error(`Failed: ${(e as Error).message}`),
    })
  }

  return (
    <div className="mt-2 flex flex-wrap items-center gap-2">
      <Button
        variant={current === true ? 'default' : 'outline'}
        size="sm"
        disabled={setAvail.isPending}
        onClick={() => set(true)}
      >
        Yes, available
      </Button>
      <Button
        variant={current === false ? 'default' : 'outline'}
        size="sm"
        disabled={setAvail.isPending}
        onClick={() => set(false)}
      >
        No, not available
      </Button>
      {current !== null && (
        <span className="text-muted-foreground text-xs">
          {current ? 'You said you’re available' : 'You said you’re not available'}
        </span>
      )}
    </div>
  )
}
