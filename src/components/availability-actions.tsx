import { toast } from 'sonner'
import { useMyAvailability, useSetAvailability } from '@/hooks/use-scheduling'
import { useMyGroups } from '@/hooks/use-groups'
import { availabilityDeadline, formatDeadline, isPast } from '@/lib/deadlines'
import { Button } from '@/components/ui/button'

/** 可用性回复（通知里的 weekly_check）：按志愿者负责的「每个组」逐组 Yes / No。 */
export function AvailabilityActions({ volunteerId, week }: { volunteerId: string; week: string }) {
  const { data: groups } = useMyGroups(volunteerId)
  const { data: avail } = useMyAvailability(volunteerId, week)
  const setAvail = useSetAvailability(volunteerId, week)
  const deadline = availabilityDeadline(week) // 周六 20:00(UTC+8)
  const closed = isPast(deadline)

  const byGroup = new Map((avail ?? []).map((a) => [a.group_id, a.is_available]))

  function set(groupId: string, v: boolean) {
    setAvail.mutate(
      { groupId, isAvailable: v },
      {
        onSuccess: () => toast.success('Response saved'),
        onError: (e) => toast.error(`Failed: ${(e as Error).message}`),
      },
    )
  }

  const list = groups ?? []
  if (list.length === 0) return null

  return (
    <div className="mt-2 flex flex-col gap-2">
      {list.map((g) => {
        const cur = byGroup.get(g.id) ?? null
        return (
          <div key={g.id} className="flex flex-wrap items-center gap-2">
            <span className="text-sm font-medium">{g.name}</span>
            <span className="text-muted-foreground text-xs">{g.class_name}</span>
            <Button
              variant={cur === true ? 'default' : 'outline'}
              size="sm"
              disabled={setAvail.isPending || closed}
              onClick={() => set(g.id, true)}
            >
              Yes
            </Button>
            <Button
              variant={cur === false ? 'default' : 'outline'}
              size="sm"
              disabled={setAvail.isPending || closed}
              onClick={() => set(g.id, false)}
            >
              No
            </Button>
            {cur !== null && (
              <span className="text-muted-foreground text-xs">
                {cur ? 'available' : 'not available'}
              </span>
            )}
          </div>
        )
      })}
      <span className="text-muted-foreground text-xs">
        {closed
          ? `Closed — responses were due ${formatDeadline(deadline)}`
          : `Please respond by ${formatDeadline(deadline)}`}
      </span>
    </div>
  )
}
