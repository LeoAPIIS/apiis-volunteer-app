import { useMemo, useState } from 'react'
import { Download, Trash2 } from 'lucide-react'
import { toast } from 'sonner'
import { useAttendanceReport } from '@/hooks/use-attendance'
import { useDeleteStudent } from '@/hooks/use-groups'
import { exportStudentMatrix } from '@/lib/report'
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

export function StudentsReport({ classFilter }: { classFilter: string }) {
  const [exporting, setExporting] = useState(false)
  const [query, setQuery] = useState('')
  const reportQ = useAttendanceReport(classFilter === 'all' ? undefined : classFilter)
  const del = useDeleteStudent()
  const report = reportQ.data

  // 搜索(姓名/班级/组)+ 按姓名 a→z
  const visibleStudents = useMemo(() => {
    const list = report?.students ?? []
    const q = query.trim().toLowerCase()
    const filtered = q
      ? list.filter(
          (s) =>
            s.full_name.toLowerCase().includes(q) ||
            s.class_name.toLowerCase().includes(q) ||
            s.group_name.toLowerCase().includes(q),
        )
      : list
    return [...filtered].sort((a, b) =>
      a.full_name.localeCompare(b.full_name, undefined, { sensitivity: 'base', numeric: true }),
    )
  }, [report, query])

  async function onExport() {
    setExporting(true)
    try {
      const n = await exportStudentMatrix({
        classId: classFilter === 'all' ? undefined : classFilter,
        fileName: 'students-report.xlsx',
      })
      toast.success(`Exported ${n} student(s) across all weeks`)
    } catch (e) {
      toast.error(`Export failed: ${(e as Error).message}`)
    } finally {
      setExporting(false)
    }
  }

  function onDelete(s: { id: string; full_name: string }) {
    if (!window.confirm(`Delete student "${s.full_name}"? This also removes their attendance records.`))
      return
    del.mutate(s.id, {
      onSuccess: () => toast.success('Student deleted'),
      onError: (e) => toast.error(`Failed: ${(e as Error).message}`),
    })
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <Input
          placeholder="Search students…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          className="max-w-xs"
        />
        <Button variant="outline" onClick={() => void onExport()} disabled={exporting}>
          <Download className="size-4" /> {exporting ? 'Exporting…' : 'Export Excel'}
        </Button>
      </div>

      {reportQ.isLoading ? (
        <p className="text-muted-foreground text-sm">Loading…</p>
      ) : !report || report.students.length === 0 ? (
        <p className="text-muted-foreground text-sm">No students in this class yet.</p>
      ) : (
        <div className="overflow-x-auto rounded-md border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="bg-background sticky left-0 whitespace-nowrap">Student</TableHead>
                <TableHead className="whitespace-nowrap">Class</TableHead>
                <TableHead className="whitespace-nowrap">Group</TableHead>
                {report.dates.map((d) => (
                  <TableHead key={d} className="text-center whitespace-nowrap" title={d}>
                    {d.slice(5)}
                  </TableHead>
                ))}
              </TableRow>
            </TableHeader>
            <TableBody>
              {visibleStudents.length === 0 ? (
                <TableRow>
                  <TableCell
                    colSpan={3 + report.dates.length}
                    className="text-muted-foreground text-center text-sm"
                  >
                    No matches.
                  </TableCell>
                </TableRow>
              ) : (
                visibleStudents.map((s) => (
                  <TableRow key={s.id}>
                    <TableCell className="bg-background sticky left-0 font-medium whitespace-nowrap">
                      <span className="flex items-center gap-2">
                        {s.full_name}
                        <button
                          type="button"
                          onClick={() => onDelete(s)}
                          className="text-muted-foreground hover:text-destructive"
                          aria-label={`Delete ${s.full_name}`}
                        >
                          <Trash2 className="size-3.5" />
                        </button>
                      </span>
                    </TableCell>
                    <TableCell className="text-muted-foreground whitespace-nowrap">{s.class_name}</TableCell>
                    <TableCell className="text-muted-foreground whitespace-nowrap">{s.group_name}</TableCell>
                    {report.dates.map((d) => {
                      const cell = report.cells[s.id]?.[d]
                      const note = cell?.note ?? ''
                      const score = cell?.score ?? null
                      const display =
                        score !== null ? (
                          score
                        ) : note ? (
                          '✎'
                        ) : (
                          <span className="text-muted-foreground/40">·</span>
                        )
                      return (
                        <TableCell key={d} className="text-center tabular-nums">
                          {note ? (
                            <span
                              className="cursor-help underline decoration-dotted underline-offset-2"
                              title={note}
                            >
                              {display}
                            </span>
                          ) : (
                            display
                          )}
                        </TableCell>
                      )
                    })}
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>
        </div>
      )}

      <p className="text-muted-foreground text-xs">
        Cells show the Contribution score (0–3); ✎ = has a remark (hover to read); · = not assessed.
        The exported Excel uses one sheet; each date spans two columns — Score and Remark.
      </p>
    </div>
  )
}
