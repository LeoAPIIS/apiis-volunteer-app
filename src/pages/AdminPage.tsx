import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Check, Trash2 } from 'lucide-react'
import { toast } from 'sonner'
import { useAllGroups, useClasses } from '@/hooks/use-groups'
import { useAssignments, useAllUsers } from '@/hooks/use-assignments'
import { GroupAssignmentCard } from '@/components/group-assignment-card'
import { StudentsReport } from '@/components/students-report'
import { SchedulingAdmin } from '@/components/scheduling-admin'
import { VolunteersReport } from '@/components/volunteers-report'
import { Spinner } from '@/components/spinner'
import {
  useDeleteFeedback,
  useFeedback,
  useSetFeedbackResolved,
  type Feedback,
} from '@/hooks/use-feedback'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'

function AssignmentsTab({ classFilter }: { classFilter: string }) {
  const groupsQ = useAllGroups()
  const usersQ = useAllUsers()
  const assignmentsQ = useAssignments()

  if (groupsQ.isLoading || usersQ.isLoading || assignmentsQ.isLoading) {
    return <Spinner label="Loading groups & assignments…" />
  }
  const users = usersQ.data ?? []
  const assignments = assignmentsQ.data ?? []
  const groups = (groupsQ.data ?? []).filter(
    (g) => classFilter === 'all' || g.cohort_id === classFilter,
  )

  if (groups.length === 0) {
    return <p className="text-muted-foreground text-sm">No groups.</p>
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="text-muted-foreground flex flex-wrap items-center gap-x-4 gap-y-1 text-xs">
        <span className="flex items-center gap-1.5">
          <span className="bg-secondary inline-block size-3 rounded-full" /> Roster (original)
        </span>
        <span className="flex items-center gap-1.5">
          <span className="inline-block size-3 rounded-full bg-blue-700" /> Admin-assigned
        </span>
        <span className="flex items-center gap-1.5">
          <span className="inline-block size-3 rounded-full border bg-green-100" /> Coverage
        </span>
      </div>
      <div className="grid gap-4 md:grid-cols-2">
        {groups.map((g) => (
          <GroupAssignmentCard key={g.id} group={g} users={users} assignments={assignments} />
        ))}
      </div>
    </div>
  )
}

function RecordsTab({ classFilter }: { classFilter: string }) {
  const groupsQ = useAllGroups()
  if (groupsQ.isLoading) return <Spinner />
  const groups = (groupsQ.data ?? []).filter(
    (g) => classFilter === 'all' || g.cohort_id === classFilter,
  )

  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {groups.map((g) => (
        <Card key={g.id}>
          <CardHeader>
            <CardTitle className="text-base">{g.name}</CardTitle>
            {g.cohort?.name && <p className="text-muted-foreground text-xs">{g.cohort.name}</p>}
          </CardHeader>
          <CardContent>
            <Button asChild size="sm" variant="secondary">
              <Link to={`/groups/${g.id}`}>Open attendance</Link>
            </Button>
          </CardContent>
        </Card>
      ))}
    </div>
  )
}

function FeedbackTab() {
  const { data: items, isLoading } = useFeedback()
  const setResolved = useSetFeedbackResolved()
  const del = useDeleteFeedback()
  if (isLoading) return <Spinner />
  if (!items || items.length === 0)
    return <p className="text-muted-foreground text-sm">No feedback yet.</p>

  // 未解决在前,其次按时间(新 → 旧)
  const sorted = [...items].sort(
    (a, b) => Number(a.resolved) - Number(b.resolved) || b.created_at.localeCompare(a.created_at),
  )

  function toggle(f: Feedback) {
    setResolved.mutate(
      { id: f.id, resolved: !f.resolved },
      {
        onSuccess: () => toast.success(f.resolved ? 'Reopened' : 'Marked resolved'),
        onError: (e) => toast.error(`Failed: ${(e as Error).message}`),
      },
    )
  }

  function onDelete(f: Feedback) {
    if (
      !window.confirm(
        `Delete this feedback from ${f.full_name || 'Unknown'}? This permanently removes it.`,
      )
    )
      return
    del.mutate(f.id, {
      onSuccess: () => toast.success('Feedback deleted'),
      onError: (e) => toast.error(`Failed: ${(e as Error).message}`),
    })
  }

  return (
    <div className="flex flex-col gap-2">
      {sorted.map((f) => (
        <div key={f.id} className={`rounded-md border p-3 ${f.resolved ? 'bg-muted/40' : ''}`}>
          <div className="flex items-center justify-between gap-2">
            <div className="flex items-center gap-2">
              <p className="font-medium">{f.full_name || 'Unknown'}</p>
              {f.resolved && (
                <Badge
                  variant="secondary"
                  className="gap-1 font-normal"
                  title={f.resolved_at ? `Resolved ${new Date(f.resolved_at).toLocaleString()}` : undefined}
                >
                  <Check className="size-3" /> Resolved
                </Badge>
              )}
            </div>
            <span className="text-muted-foreground text-xs">
              {new Date(f.created_at).toLocaleString()}
            </span>
          </div>
          <p className="text-muted-foreground mt-1 text-sm whitespace-pre-wrap">{f.message}</p>
          <div className="mt-2 flex justify-end gap-2">
            <Button
              size="sm"
              variant={f.resolved ? 'outline' : 'secondary'}
              disabled={setResolved.isPending}
              onClick={() => toggle(f)}
            >
              {f.resolved ? 'Reopen' : 'Mark resolved'}
            </Button>
            <Button
              size="sm"
              variant="outline"
              className="text-destructive hover:text-destructive"
              disabled={del.isPending}
              onClick={() => onDelete(f)}
            >
              <Trash2 className="size-3.5" /> Delete
            </Button>
          </div>
        </div>
      ))}
    </div>
  )
}

export function AdminPage() {
  const [classFilter, setClassFilter] = useState('all')
  const classesQ = useClasses()
  const classes = classesQ.data ?? []

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-2xl font-semibold tracking-tight">Admin Console</h1>
        <Select value={classFilter} onValueChange={setClassFilter}>
          <SelectTrigger className="w-[260px]">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All classes</SelectItem>
            {classes.map((c) => (
              <SelectItem key={c.id} value={c.id}>
                {c.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <Tabs defaultValue="assignments">
        <TabsList>
          <TabsTrigger value="assignments">Groups &amp; Assignments</TabsTrigger>
          <TabsTrigger value="records">Records</TabsTrigger>
          <TabsTrigger value="students">Students</TabsTrigger>
          <TabsTrigger value="volunteers">Volunteers</TabsTrigger>
          <TabsTrigger value="scheduling">Scheduling</TabsTrigger>
          <TabsTrigger value="feedback">Feedback</TabsTrigger>
        </TabsList>
        <TabsContent value="assignments" className="mt-4">
          <AssignmentsTab classFilter={classFilter} />
        </TabsContent>
        <TabsContent value="records" className="mt-4">
          <RecordsTab classFilter={classFilter} />
        </TabsContent>
        <TabsContent value="students" className="mt-4">
          <StudentsReport classFilter={classFilter} />
        </TabsContent>
        <TabsContent value="volunteers" className="mt-4">
          <VolunteersReport classFilter={classFilter} />
        </TabsContent>
        <TabsContent value="scheduling" className="mt-4">
          <SchedulingAdmin />
        </TabsContent>
        <TabsContent value="feedback" className="mt-4">
          <FeedbackTab />
        </TabsContent>
      </Tabs>
    </div>
  )
}
