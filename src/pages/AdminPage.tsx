import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useAllGroups, useClasses } from '@/hooks/use-groups'
import { useAssignments, useVolunteers } from '@/hooks/use-assignments'
import { GroupAssignmentCard } from '@/components/group-assignment-card'
import { StudentsReport } from '@/components/students-report'
import { SchedulingAdmin } from '@/components/scheduling-admin'
import { VolunteersReport } from '@/components/volunteers-report'
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
  const volunteersQ = useVolunteers()
  const assignmentsQ = useAssignments()

  if (groupsQ.isLoading || volunteersQ.isLoading || assignmentsQ.isLoading) {
    return <p className="text-muted-foreground text-sm">Loading…</p>
  }
  const volunteers = volunteersQ.data ?? []
  const assignments = assignmentsQ.data ?? []
  const groups = (groupsQ.data ?? []).filter(
    (g) => classFilter === 'all' || g.cohort_id === classFilter,
  )

  if (groups.length === 0) {
    return <p className="text-muted-foreground text-sm">No groups.</p>
  }

  return (
    <div className="grid gap-4 md:grid-cols-2">
      {groups.map((g) => (
        <GroupAssignmentCard
          key={g.id}
          group={g}
          volunteers={volunteers}
          assignments={assignments}
        />
      ))}
    </div>
  )
}

function RecordsTab({ classFilter }: { classFilter: string }) {
  const groupsQ = useAllGroups()
  if (groupsQ.isLoading) return <p className="text-muted-foreground text-sm">Loading…</p>
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
      </Tabs>
    </div>
  )
}
