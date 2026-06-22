import { useMemo, useState } from 'react'
import { Download, Lock, ShieldCheck, ShieldOff, Trash2, Upload } from 'lucide-react'
import { toast } from 'sonner'
import { useAuth } from '@/lib/auth'
import { exportVolunteers } from '@/lib/report'
import {
  useAssignments,
  useDeleteVolunteer,
  useSetUserRole,
  useVolunteerActivity,
} from '@/hooks/use-assignments'
import { useAllGroups } from '@/hooks/use-groups'
import { ImportVolunteers } from '@/components/import-admin'
import { Spinner } from '@/components/spinner'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
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

// 排序优先级：super_admin → admin → volunteer（同级再按姓名 a→z）
function roleRank(r: string): number {
  return r === 'super_admin' ? 0 : r === 'admin' ? 1 : 2
}

export function VolunteersReport({ classFilter }: { classFilter: string }) {
  const { user, profile } = useAuth()
  const iAmSuper = profile?.role === 'super_admin'
  const { data, isLoading } = useVolunteerActivity()
  const assignmentsQ = useAssignments()
  const groupsQ = useAllGroups()
  const del = useDeleteVolunteer()
  const setRole = useSetUserRole()
  const [query, setQuery] = useState('')
  const [showImport, setShowImport] = useState(false)
  const [exporting, setExporting] = useState(false)

  // 按班级筛选 → 搜索 → 角色置顶(super/admin)再按姓名 a→z
  const rows = useMemo(() => {
    const all = data ?? []
    let list = all
    if (classFilter !== 'all') {
      const groupIdsInClass = new Set(
        (groupsQ.data ?? []).filter((g) => g.cohort_id === classFilter).map((g) => g.id),
      )
      const ids = new Set(
        (assignmentsQ.data ?? [])
          .filter((a) => groupIdsInClass.has(a.group_id))
          .map((a) => a.volunteer_id),
      )
      list = all.filter((v) => ids.has(v.volunteer_id))
    }
    const q = query.trim().toLowerCase()
    if (q)
      list = list.filter(
        (v) => v.full_name.toLowerCase().includes(q) || (v.email || '').toLowerCase().includes(q),
      )
    return [...list].sort(
      (a, b) =>
        roleRank(a.role) - roleRank(b.role) ||
        a.full_name.localeCompare(b.full_name, undefined, { sensitivity: 'base', numeric: true }),
    )
  }, [data, assignmentsQ.data, groupsQ.data, classFilter, query])

  // 每个志愿者的具体组名(客户端用 assignments + groups 拼出),带简短班级码,如 "6P · Group 1"
  const groupsByVolunteer = useMemo(() => {
    const groupById = new Map((groupsQ.data ?? []).map((g) => [g.id, g]))
    const map = new Map<string, { id: string; label: string; title: string }[]>()
    for (const a of assignmentsQ.data ?? []) {
      const g = groupById.get(a.group_id)
      if (!g) continue
      const cls = g.cohort?.name ?? ''
      const short = cls.replace(/^MMin\s+/i, '').split(/\s+/)[0] || cls
      const arr = map.get(a.volunteer_id) ?? []
      arr.push({
        id: a.id,
        label: short ? `${short} · ${g.name}` : g.name,
        title: cls ? `${cls} · ${g.name}` : g.name,
      })
      map.set(a.volunteer_id, arr)
    }
    for (const arr of map.values())
      arr.sort((x, y) => x.label.localeCompare(y.label, undefined, { numeric: true }))
    return map
  }, [assignmentsQ.data, groupsQ.data])

  async function onExport() {
    setExporting(true)
    try {
      const n = await exportVolunteers(rows, 'volunteers.xlsx')
      toast.success(`Exported ${n} volunteer(s)`)
    } catch (e) {
      toast.error(`Export failed: ${(e as Error).message}`)
    } finally {
      setExporting(false)
    }
  }

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

  if (isLoading) return <Spinner />

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <Input
          placeholder="Search by name or email…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          className="max-w-xs"
        />
        <div className="flex items-center gap-2">
          {iAmSuper && (
            <Button
              variant={showImport ? 'secondary' : 'outline'}
              onClick={() => setShowImport((v) => !v)}
            >
              <Upload className="size-4" /> Import CSV
            </Button>
          )}
          <Button variant="outline" onClick={() => void onExport()} disabled={exporting || rows.length === 0}>
            <Download className="size-4" /> {exporting ? 'Exporting…' : 'Export Excel'}
          </Button>
        </div>
      </div>

      {iAmSuper && showImport && <ImportVolunteers />}

      {rows.length === 0 ? (
        <p className="text-muted-foreground text-sm">No matching users.</p>
      ) : (
        <div className="overflow-x-auto rounded-md border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Name</TableHead>
                <TableHead className="whitespace-nowrap">Email</TableHead>
                <TableHead>Role</TableHead>
                <TableHead>Assigned groups</TableHead>
                <TableHead className="text-center">Sessions attended</TableHead>
                <TableHead className="whitespace-nowrap">Last active</TableHead>
                <TableHead className="text-center">Coverage given</TableHead>
                <TableHead className="text-center">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((v) => {
                const isSelf = v.volunteer_id === user?.id
                const canDelete = !isSelf && iAmSuper && v.role !== 'super_admin'
                const canToggleRole = !isSelf && iAmSuper && v.role !== 'super_admin'
                const vGroups = groupsByVolunteer.get(v.volunteer_id) ?? []
                return (
                  <TableRow key={v.volunteer_id}>
                    <TableCell className="font-medium">{v.full_name}</TableCell>
                    <TableCell className="text-muted-foreground whitespace-nowrap">{v.email || '—'}</TableCell>
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
                    <TableCell>
                      {vGroups.length === 0 ? (
                        <span className="text-muted-foreground">—</span>
                      ) : (
                        <div className="flex max-w-xs flex-wrap gap-1">
                          {vGroups.map((g) => (
                            <Badge key={g.id} variant="outline" className="font-normal" title={g.title}>
                              {g.label}
                            </Badge>
                          ))}
                        </div>
                      )}
                    </TableCell>
                    <TableCell className="text-center tabular-nums">{v.sessions_recorded}</TableCell>
                    <TableCell className="whitespace-nowrap">{v.last_active ?? '—'}</TableCell>
                    <TableCell className="text-center tabular-nums">{v.coverage_count}</TableCell>
                    <TableCell className="text-center">
                      {isSelf ? (
                        <span className="text-muted-foreground text-xs">you</span>
                      ) : v.role === 'super_admin' ? (
                        <span className="text-muted-foreground inline-flex items-center gap-1 text-xs">
                          <Lock className="size-3" /> super
                        </span>
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
      )}

      <p className="text-muted-foreground text-xs">
        Admins shown first, then A–Z by name. Only a <b>super admin</b> can import, promote/demote, or delete users —
        admins manage assignments, attendance &amp; reports; volunteers record attendance. You can&apos;t
        act on your own row or a super admin.
      </p>
    </div>
  )
}
