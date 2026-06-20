import { useState } from 'react'
import { toast } from 'sonner'
import { useSaveAttendance } from '@/hooks/use-attendance'
import type { AttendanceUpsert } from '@/hooks/use-attendance'
import type { AttendanceRecord } from '@/types'
import type { GroupStudent } from '@/hooks/use-groups'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'

interface RowState {
  contribution: number | null
  notes: string
}

interface Props {
  students: GroupStudent[]
  existing: AttendanceRecord[]
  groupId: string
  sessionDate: string
  volunteerId: string
}

const RUBRIC: { score: number; text: string }[] = [
  { score: 0, text: 'No video on, or did not participate in the discussion.' },
  {
    score: 1,
    text: 'Video on, but the discussion was not meaningful — repeating others, or not understanding the question.',
  },
  {
    score: 2,
    text: 'Video on and prepared, but only reading copied answers with no personal insight.',
  },
  {
    score: 3,
    text: 'Video on, prepared, actively participating, with own insights and real-life examples.',
  },
]

export function AttendanceForm({ students, existing, groupId, sessionDate, volunteerId }: Props) {
  const save = useSaveAttendance()

  // useState 初始化器从已有记录构建表单；父组件用 key={groupId:date} 控制重挂载。
  const [rows, setRows] = useState<Record<string, RowState>>(() => {
    const map: Record<string, RowState> = {}
    for (const s of students) {
      const ex = existing.find((e) => e.student_id === s.id)
      map[s.id] = { contribution: ex?.contribution ?? null, notes: ex?.notes ?? '' }
    }
    return map
  })

  function update(studentId: string, patch: Partial<RowState>) {
    setRows((prev) => ({ ...prev, [studentId]: { ...prev[studentId], ...patch } }))
  }

  async function onSave() {
    const payload: AttendanceUpsert[] = students.map((s) => ({
      group_id: groupId,
      student_id: s.id,
      volunteer_id: volunteerId,
      session_date: sessionDate,
      contribution: rows[s.id]?.contribution ?? null,
      notes: rows[s.id]?.notes ?? '',
    }))
    try {
      await save.mutateAsync(payload)
      toast.success('Assessment saved')
    } catch (e) {
      toast.error(`Save failed: ${(e as Error).message}`)
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="bg-muted/40 rounded-md border p-3 text-sm">
        <p className="mb-1 font-medium">Contribution scoring guide</p>
        <ul className="text-muted-foreground space-y-0.5">
          {RUBRIC.map((r) => (
            <li key={r.score}>
              <span className="text-foreground font-medium">{r.score}</span> — {r.text}
            </li>
          ))}
        </ul>
      </div>

      <div className="overflow-x-auto rounded-md border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Student</TableHead>
              <TableHead className="w-40">Contribution</TableHead>
              <TableHead>Notes</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {students.map((s) => {
              const r = rows[s.id]
              return (
                <TableRow key={s.id}>
                  <TableCell className="font-medium">{s.full_name}</TableCell>
                  <TableCell>
                    <Select
                      value={r.contribution === null ? 'none' : String(r.contribution)}
                      onValueChange={(v) =>
                        update(s.id, { contribution: v === 'none' ? null : Number(v) })
                      }
                    >
                      <SelectTrigger className="w-32">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="none">— Not assessed</SelectItem>
                        <SelectItem value="0">0</SelectItem>
                        <SelectItem value="1">1</SelectItem>
                        <SelectItem value="2">2</SelectItem>
                        <SelectItem value="3">3</SelectItem>
                      </SelectContent>
                    </Select>
                  </TableCell>
                  <TableCell>
                    <Input
                      value={r.notes}
                      onChange={(e) => update(s.id, { notes: e.target.value })}
                      placeholder="Optional"
                    />
                  </TableCell>
                </TableRow>
              )
            })}
          </TableBody>
        </Table>
      </div>

      <div className="flex justify-end">
        <Button onClick={() => void onSave()} disabled={save.isPending}>
          {save.isPending ? 'Saving…' : 'Save assessment'}
        </Button>
      </div>
    </div>
  )
}
