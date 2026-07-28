import { useMemo, useState } from 'react'
import { useAssignmentHistory } from '@/hooks/use-assignments'
import { Spinner } from '@/components/spinner'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'

/** 只读:历史上被「管理员指派 / 补位」到各组的人(每周三清理前的归档)。 */
export function AssignmentHistory() {
  const { data, isLoading } = useAssignmentHistory()
  const [query, setQuery] = useState('')

  const rows = useMemo(() => {
    const q = query.trim().toLowerCase()
    const all = data ?? []
    if (!q) return all
    return all.filter((r) =>
      [r.week_start_date, r.class_name, r.group_name, r.volunteer_name, r.volunteer_email].some(
        (v) => (v ?? '').toLowerCase().includes(q),
      ),
    )
  }, [data, query])

  if (isLoading) return <Spinner />

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <Input
          placeholder="Search by week, class, group, name or email…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          className="max-w-sm"
        />
        <span className="text-muted-foreground text-xs">{rows.length} record(s)</span>
      </div>
      <p className="text-muted-foreground text-xs">
        Temporary assignments (admin-assigned and coverage) archived just before the weekly Wednesday
        clear. Roster (original) volunteers are permanent — see Groups &amp; Assignments.
      </p>

      {rows.length === 0 ? (
        <p className="text-muted-foreground text-sm">No history yet.</p>
      ) : (
        <div className="overflow-x-auto rounded-md border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="whitespace-nowrap">Week (Mon)</TableHead>
                <TableHead>Class</TableHead>
                <TableHead>Group</TableHead>
                <TableHead>Type</TableHead>
                <TableHead>Volunteer</TableHead>
                <TableHead className="whitespace-nowrap">Email</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((r) => (
                <TableRow key={r.id}>
                  <TableCell className="tabular-nums whitespace-nowrap">
                    {r.week_start_date}
                  </TableCell>
                  <TableCell>{r.class_name ?? '—'}</TableCell>
                  <TableCell>{r.group_name ?? '—'}</TableCell>
                  <TableCell>
                    <Badge
                      variant="secondary"
                      className={
                        r.source === 'coverage'
                          ? 'bg-green-100 font-normal text-green-900 dark:bg-green-900/40 dark:text-green-100'
                          : 'bg-blue-700 font-normal text-white'
                      }
                    >
                      {r.source === 'coverage' ? 'Coverage' : 'Admin-assigned'}
                    </Badge>
                  </TableCell>
                  <TableCell className="font-medium">{r.volunteer_name ?? '—'}</TableCell>
                  <TableCell className="text-muted-foreground whitespace-nowrap">
                    {r.volunteer_email ?? '—'}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
    </div>
  )
}
