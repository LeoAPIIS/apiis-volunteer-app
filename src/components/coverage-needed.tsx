import { toast } from 'sonner'
import { useClaimCoverage, useOpenCoverageRequests } from '@/hooks/use-scheduling'
import { coverageDeadline, formatDeadline, isPast } from '@/lib/deadlines'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

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
                onClick={() => onClaim(r.id)}
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
