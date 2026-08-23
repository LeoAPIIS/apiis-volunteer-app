import { toast } from 'sonner'
import { useClaimCoverage, useOpenCoverageRequests } from '@/hooks/use-scheduling'
import { coverageDeadline, formatDeadline, isPast } from '@/lib/deadlines'
import { weekdayOffsetForClass } from '@/lib/calendar'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

const DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
// 该周该班的实际上课日(周一班=周一,周二班=周一+1),如 "Tue 2026-07-14"
function sessionDayLabel(weekMondayISO: string, className: string): string {
  const [y, m, d] = weekMondayISO.split('-').map(Number)
  const dt = new Date(Date.UTC(y, m - 1, d + weekdayOffsetForClass(className)))
  return `${DOW[dt.getUTCDay()]} ${dt.toISOString().slice(0, 10)}`
}

export function CoverageNeeded() {
  const { data: requests, isLoading } = useOpenCoverageRequests()
  const claim = useClaimCoverage()

  function onClaim(id: string) {
    claim.mutate(id, {
      onSuccess: () => toast.success('You are now covering this group'),
      onError: (e) => toast.error(`Failed: ${(e as Error).message}`),
    })
  }

  // 没有缺人请求时不显示
  if (isLoading || !requests || requests.length === 0) return null

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Coverage needed</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-2">
        {requests.map((r) => {
          const deadline = coverageDeadline(r.week_start_date, r.class_name) // 按班级的认领截止
          const closed = deadline !== null && isPast(deadline)
          return (
            <div key={r.id} className="flex items-center justify-between gap-2 rounded-md border p-2">
              <div className="text-sm">
                <div>
                  <span className="font-medium">{r.group_name}</span>
                  <span className="text-muted-foreground">
                    {' '}
                    · {r.class_name} · week of {r.week_start_date}
                  </span>
                </div>
                {deadline !== null && (
                  <span className="text-muted-foreground text-xs">
                    {closed
                      ? `Claim closed (${formatDeadline(deadline)})`
                      : `Claim by ${formatDeadline(deadline)}`}
                  </span>
                )}
              </div>
              <Button
                size="sm"
                disabled={claim.isPending || closed}
                onClick={() => {
                  if (
                    !window.confirm(
                      `Confirm you'll cover ${r.group_name} · ${r.class_name}, on ${sessionDayLabel(r.week_start_date, r.class_name)}?`,
                    )
                  )
                    return
                  onClaim(r.id)
                }}
              >
                {closed ? 'Closed' : 'I will cover'}
              </Button>
            </div>
          )
        })}
      </CardContent>
    </Card>
  )
}
