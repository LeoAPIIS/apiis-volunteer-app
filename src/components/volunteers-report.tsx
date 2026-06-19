import { useMemo } from 'react'
import { ShieldCheck, ShieldOff, Trash2 } from 'lucide-react'
import { toast } from 'sonner'
import { useAuth } from '@/lib/auth'
import {
  useAssignments,
  useDeleteVolunteer,
  useSetUserRole,
  useVolunteerActivity,
} from '@/hooks/use-assignments'
import { useAllGroups } from '@/hooks/use-groups'
import { Badge } from '@/components/ui/badge'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'

function roleLabel(r: string): string {
  return r === 'super_admin' ? 'Super Admin' : r === 'admin' ? 'Admin' : 'Volunteer'
}

export function VolunteersReport({ classFilter }: { classFilter: string }) {
  const { user, profile } = useAuth()
  const iAmSuper = profile?.role === 'super_admin'
  const { data, isLoading } = useVolunteerActivity()
  const assignmentsQ = useAssignments()
  const groupsQ = useAllGroups()
  const del = useDeleteVolunteer()
  const setRole = useSetUserRole()

  const rows = useMemo(() => {
    const all = data ?? []
    if (classFilter === 'all') return all
    const groupIdsInClass = new Set(
      (groupsQ.data ?? []).filter((g) => g.cohort_id === classFilter).map((g) => g.id),
    )
    const ids = new Set(
      (assignmentsQ.data ?? [])
        .filter((a) => groupIdsInClass.has(a.group_id))
        .map((a) => a.volunteer_id),
    )
    return all.filter((v) => ids.has(v.volunteer_id))
  }, [data, assignmentsQ.data, groupsQ.data, classFilter])

  function onDelete(id: string, name: string) {
    if (!window.confirm(`Delete "${name}"? This removes their account and assignments.`)) return
    del.mutate(id, {
      onSuccess: () => toast.success('User deleted'),
      onError: (e) => toast.error(`Failed: ${(e as Error).message}`),
    })
  }

  function onSetRole(id: string, name: string, role: 'admin' | 'volunteer') {
    const msg =
      role === 'admin'
        ? `Make "${name}" an admin? They get full admin access (but not super-admin powers).`
        : `Change "${name}" back to a volunteer?`
    if (!window.confirm(msg)) return
    setRole.mutate(
      { id, role },
      {
        onSuccess: () =>
          toast.success(role === 'admin' ? `${name} is now an admin` : `${name} is now a volunteer`),
        onError: (e) => toast.error(`Failed: ${(e as Error).message}`),
      },
    )
  }

  if (isLoading) return <p className="text-muted-foreground text-sm">Loading…</p>
  if (rows.length === 0) {
    return (
      <p className="text-muted-foreground text-sm">
        {classFilter === 'all' ? 'No users yet.' : 'No one assigned to this class yet.'}
      </p>
    )
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="overflow-x-auto rounded-md border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Name</TableHead>
              <TableHead>Role</TableHead>
              <TableHead className="text-center">Assigned groups</TableHead>
              <TableHead className="text-center">Sessions attended</TableHead>
              <TableHead className="whitespace-nowrap">Last active</TableHead>
              <TableHead className="text-center">Coverage given</TableHead>
              <TableHead className="text-center">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((v) => {
              const isSelf = v.volunteer_id === user?.id
              // admin 只能删 volunteer；super_admin 可删 admin/volunteer；super_admin 行不可操作
              const canDelete = !isSelf && v.role !== 'super_admin' && (v.role === 'volunteer' || iAmSuper)
              const canToggleRole = !isSelf && iAmSuper && v.role !== 'super_admin'
              return (
                <TableRow key={v.volunteer_id}>
                  <TableCell className="font-medium">{v.full_name}</TableCell>
                  <TableCell>
                    <Badge
                      variant={
                        v.role === 'super_admin'
                          ? 'default'
                          : v.role === 'admin'
                            ? 'secondary'
                            : 'outline'
                      }
                    >
                      {roleLabel(v.role)}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-center tabular-nums">{v.assigned_groups}</TableCell>
                  <TableCell className="text-center tabular-nums">{v.sessions_recorded}</TableCell>
                  <TableCell className="whitespace-nowrap">{v.last_active ?? '—'}</TableCell>
                  <TableCell className="text-center tabular-nums">{v.coverage_count}</TableCell>
                  <TableCell className="text-center">
                    {isSelf ? (
                      <span className="text-muted-foreground text-xs">you</span>
                    ) : !canToggleRole && !canDelete ? (
                      <span className="text-muted-foreground text-xs">—</span>
                    ) : (
                      <div className="flex items-center justify-center gap-3">
                        {canToggleRole &&
                          (v.role === 'volunteer' ? (
                            <button
                              type="button"
                              onClick={() => onSetRole(v.volunteer_id, v.full_name, 'admin')}
                              className="text-muted-foreground hover:text-foreground"
                              title="Make admin"
                              aria-label={`Make ${v.full_name} an admin`}
                            >
                              <ShieldCheck className="size-3.5" />
                            </button>
                          ) : (
                            <button
                              type="button"
                              onClick={() => onSetRole(v.volunteer_id, v.full_name, 'volunteer')}
                              className="text-muted-foreground hover:text-foreground"
                              title="Make volunteer"
                              aria-label={`Make ${v.full_name} a volunteer`}
                            >
                              <ShieldOff className="size-3.5" />
                            </button>
                          ))}
                        {canDelete && (
                          <button
                            type="button"
                            onClick={() => onDelete(v.volunteer_id, v.full_name)}
                            className="text-muted-foreground hover:text-destructive"
                            title="Delete"
                            aria-label={`Delete ${v.full_name}`}
                          >
                            <Trash2 className="size-3.5" />
                          </button>
                        )}
                      </div>
                    )}
                  </TableCell>
                </TableRow>
              )
            })}
          </TableBody>
        </Table>
      </div>
      <p className="text-muted-foreground text-xs">
        Roles: <b>Super Admin</b> appoints/removes admins and can delete anyone; <b>Admin</b> runs
        day-to-day and can delete volunteers only; <b>Volunteer</b> records attendance. Only a super
        admin sees the promote/demote (shield) icons. You can&apos;t act on your own row or on a super
        admin.
      </p>
    </div>
  )
}
