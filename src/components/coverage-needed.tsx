import { toast } from 'sonner'
import { useClaimCoverage, useOpenCoverageRequests } from '@/hooks/use-scheduling'
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
        {requests.map((r) => (
          <div key={r.id} className="flex items-center justify-between gap-2 rounded-md border p-2">
            <div className="text-sm">
              <span className="font-medium">{r.group_name}</span>
              <span className="text-muted-foreground"> · {r.class_name} · week of {r.week_start_date}</span>
            </div>
            <Button size="sm" disabled={claim.isPending} onClick={() => onClaim(r.id)}>
              I will cover
            </Button>
          </div>
        ))}
      </CardContent>
    </Card>
  )
}
