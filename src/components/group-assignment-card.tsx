import { useState } from 'react'
import { X } from 'lucide-react'
import { toast } from 'sonner'
import { useAssignVolunteer, useUnassign } from '@/hooks/use-assignments'
import type { GroupWithCohort } from '@/hooks/use-groups'
import type { Assignment, Profile } from '@/types'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'

interface Props {
  group: GroupWithCohort
  volunteers: Profile[]
  assignments: Assignment[]
}

export function GroupAssignmentCard({ group, volunteers, assignments }: Props) {
  const assign = useAssignVolunteer()
  const unassign = useUnassign()
  const [selected, setSelected] = useState('')

  const groupAssignments = assignments.filter((a) => a.group_id === group.id)
  const assignedIds = new Set(groupAssignments.map((a) => a.volunteer_id))
  const available = volunteers.filter((v) => !assignedIds.has(v.id))
  const nameOf = (id: string) => volunteers.find((v) => v.id === id)?.full_name ?? 'Unknown'

  async function onAssign() {
    if (!selected) return
    try {
      await assign.mutateAsync({ groupId: group.id, volunteerId: selected })
      setSelected('')
      toast.success('Volunteer assigned')
    } catch (e) {
      toast.error(`Failed: ${(e as Error).message}`)
    }
  }

  async function onRemove(a: Assignment) {
    try {
      await unassign.mutateAsync(a.id)
      toast.success('Assignment removed')
    } catch (e) {
      toast.error(`Failed: ${(e as Error).message}`)
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center justify-between gap-2 text-base">
          <span>{group.name}</span>
          {group.cohort?.name && (
            <Badge variant="outline" className="shrink-0 font-normal">
              {group.cohort.name}
            </Badge>
          )}
        </CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <div className="flex flex-wrap gap-2">
          {groupAssignments.length === 0 ? (
            <span className="text-muted-foreground text-sm">No volunteers assigned</span>
          ) : (
            groupAssignments.map((a) => (
              <Badge key={a.id} variant="secondary" className="gap-1 pr-1">
                {nameOf(a.volunteer_id)}
                <button
                  type="button"
                  onClick={() => void onRemove(a)}
                  className="hover:text-destructive rounded-sm"
                  aria-label={`Remove ${nameOf(a.volunteer_id)}`}
                >
                  <X className="size-3" />
                </button>
              </Badge>
            ))
          )}
        </div>
        {available.length > 0 ? (
          <div className="flex items-center gap-2">
            <Select value={selected} onValueChange={setSelected}>
              <SelectTrigger className="w-[220px]">
                <SelectValue placeholder="Choose a volunteer" />
              </SelectTrigger>
              <SelectContent>
                {available.map((v) => (
                  <SelectItem key={v.id} value={v.id}>
                    {v.full_name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Button onClick={() => void onAssign()} disabled={!selected || assign.isPending}>
              Assign
            </Button>
          </div>
        ) : (
          <span className="text-muted-foreground text-sm">All volunteers assigned</span>
        )}
      </CardContent>
    </Card>
  )
}
