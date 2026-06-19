import { toast } from 'sonner'
import { useMyAvailability, useSetAvailability } from '@/hooks/use-scheduling'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

export function AvailabilityCard({ volunteerId, week }: { volunteerId: string; week: string }) {
  const { data, isLoading } = useMyAvailability(volunteerId, week)
  const setAvail = useSetAvailability(volunteerId, week)
  const current = data?.is_available ?? null

  function set(v: boolean) {
    setAvail.mutate(v, {
      onSuccess: () => toast.success('Response saved'),
      onError: (e) => toast.error(`Failed: ${(e as Error).message}`),
    })
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Available the week of {week}?</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-wrap items-center gap-2">
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
        {!isLoading && current === null && (
          <span className="text-muted-foreground text-sm">No response yet</span>
        )}
      </CardContent>
    </Card>
  )
}
