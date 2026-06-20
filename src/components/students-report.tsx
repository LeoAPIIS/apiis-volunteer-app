import { useMemo, useState } from 'react'
import { Download, Trash2, Upload } from 'lucide-react'
import { toast } from 'sonner'
import { useAuth } from '@/lib/auth'
import { useAttendanceReport } from '@/hooks/use-attendance'
import { useDeleteStudent } from '@/hooks/use-groups'
import { exportStudentMatrix } from '@/lib/report'
import type { ReportCell } from '@/lib/report'
import { curriculumForClass, weekForDate } from '@/lib/calendar'
import { ImportStudents } from '@/components/import-admin'
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

interface WeekColumn {
  key: string
  label: string
  title: string
  sort: number
}

export function StudentsReport({ classFilter }: { classFilter: string }) {
  const [exporting, setExporting] = useState(false)
  const [showImport, setShowImport] = useState(false)
  const [query, setQuery] = useState('')
  const isAll = classFilter === 'all'
  const reportQ = useAttendanceReport(isAll ? undefined : classFilter)
  const del = useDeleteStudent()
  const report = reportQ.data
  const { profile } = useAuth()
  const iAmSuper = profile?.role === 'super_admin'

  // 搜索(姓名/邮箱/班级/组)+ 按姓名 a→z
  const visibleStudents = useMemo(() => {
    const list = report?.students ?? []
    const q = query.trim().toLowerCase()
    const filtered = q
      ? list.filter(
          (s) =>
            s.full_name.toLowerCase().includes(q) ||
            s.email.toLowerCase().includes(q) ||
            s.class_name.toLowerCase().includes(q) ||
            s.group_name.toLowerCase().includes(q),
        )
      : list
    return [...filtered].sort((a, b) =>
      a.full_name.localeCompare(b.full_name, undefined, { sensitivity: 'base', numeric: true }),
    )
  }, [report, query])

  // 把每条记录的日期映射成「周次」(按学生所属课程)，只保留有数据的周列
  const { columns, cellByStudent } = useMemo(() => {
    const colMap = new Map<string, WeekColumn>()
    const byStudent: Record<string, Record<string, ReportCell>> = {}
    for (const s of visibleStudents) {
      const cur = curriculumForClass(s.class_name)
      const dateCells = report?.cells[s.id] ?? {}
      const dest: Record<string, ReportCell> = {}
      for (const [dateISO, cell] of Object.entries(dateCells)) {
        const wk = cur ? weekForDate(cur, dateISO) : null
        const col: WeekColumn =
          wk !== null
            ? { key: `w${wk}`, label: `Wk ${wk}`, title: `Week ${wk} · ${dateISO}`, sort: wk }
            : {
                key: `d${dateISO}`,
                label: dateISO.slice(5),
                title: dateISO,
                sort: 1000 + (Date.parse(dateISO) || 0) / 8.64e7,
              }
        colMap.set(col.key, col)
        dest[col.key] = cell
      }
      byStudent[s.id] = dest
    }
    const columns = [...colMap.values()].sort((a, b) => a.sort - b.sort)
    return { columns, cellByStudent: byStudent }
  }, [visibleStudents, report])

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
        {isAll ? (
          <p className="text-muted-foreground text-sm">Select a class above to view attendance and export.</p>
        ) : (
          <Input
            placeholder="Search students…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="max-w-xs"
          />
        )}
        <div className="flex items-center gap-2">
          {iAmSuper && (
            <Button
              variant={showImport ? 'secondary' : 'outline'}
              onClick={() => setShowImport((v) => !v)}
            >
              <Upload className="size-4" /> Import CSV
            </Button>
          )}
          {!isAll && (
            <Button variant="outline" onClick={() => void onExport()} disabled={exporting}>
              <Download className="size-4" /> {exporting ? 'Exporting…' : 'Export Excel'}
            </Button>
          )}
        </div>
      </div>

      {iAmSuper && showImport && <ImportStudents />}

      {isAll ? (
        <p className="text-muted-foreground rounded-md border border-dashed p-8 text-center text-sm">
          Choose a class from the filter above to see its per-week attendance matrix and export it to
          Excel. The matrix is per class — each class has its own weekly calendar, so weeks only line up
          within a single class.
        </p>
      ) : reportQ.isLoading ? (
        <p className="text-muted-foreground text-sm">Loading…</p>
      ) : !report || report.students.length === 0 ? (
        <p className="text-muted-foreground text-sm">No students in this class yet.</p>
      ) : (
        <div className="overflow-x-auto rounded-md border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="bg-background sticky left-0 whitespace-nowrap">Student</TableHead>
                <TableHead className="whitespace-nowrap">Email</TableHead>
                <TableHead className="whitespace-nowrap">Class</TableHead>
                <TableHead className="whitespace-nowrap">Group</TableHead>
                {columns.map((c) => (
                  <TableHead key={c.key} className="text-center whitespace-nowrap" title={c.title}>
                    {c.label}
                  </TableHead>
                ))}
              </TableRow>
            </TableHeader>
            <TableBody>
              {visibleStudents.length === 0 ? (
                <TableRow>
                  <TableCell
                    colSpan={4 + columns.length}
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
                        {iAmSuper && (
                          <button
                            type="button"
                            onClick={() => onDelete(s)}
                            className="text-muted-foreground hover:text-destructive"
                            aria-label={`Delete ${s.full_name}`}
                          >
                            <Trash2 className="size-3.5" />
                          </button>
                        )}
                      </span>
                    </TableCell>
                    <TableCell className="text-muted-foreground whitespace-nowrap">{s.email}</TableCell>
                    <TableCell className="text-muted-foreground whitespace-nowrap">{s.class_name}</TableCell>
                    <TableCell className="text-muted-foreground whitespace-nowrap">{s.group_name}</TableCell>
                    {columns.map((c) => {
                      const cell = cellByStudent[s.id]?.[c.key]
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
                        <TableCell key={c.key} className="text-center tabular-nums">
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

      {!isAll && (
        <p className="text-muted-foreground text-xs">
          Columns are program weeks (Wk N) — hover a column header for its date. Cells show the
          Contribution score (0–3); ✎ = has a remark (hover to read); · = not assessed. The exported
          Excel uses one sheet; each week spans two columns — Score and Remark.
        </p>
      )}
    </div>
  )
}
