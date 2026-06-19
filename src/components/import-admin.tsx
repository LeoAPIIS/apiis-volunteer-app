import { useState } from 'react'
import { toast } from 'sonner'
import { useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { dropHeader, parseCsv } from '@/lib/csv'
import { useAllGroups, useClasses } from '@/hooks/use-groups'
import type { GroupWithCohort } from '@/hooks/use-groups'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

interface ImportResult {
  ok: number
  errors: string[]
}

function ResultBox({ result, noun }: { result: ImportResult; noun: string }) {
  return (
    <div className="text-sm">
      <p className="font-medium">
        {result.ok} {noun} imported/updated
        {result.errors.length > 0 ? `, ${result.errors.length} note(s)` : ''}.
      </p>
      {result.errors.length > 0 && (
        <ul className="text-destructive mt-1 max-h-40 list-disc space-y-0.5 overflow-y-auto pl-5">
          {result.errors.map((e, i) => (
            <li key={i}>{e}</li>
          ))}
        </ul>
      )}
    </div>
  )
}

function CsvFileInput({ onText }: { onText: (text: string) => void }) {
  return (
    <Input
      type="file"
      accept=".csv,text/csv,text/plain"
      className="cursor-pointer"
      onChange={async (e) => {
        const file = e.target.files?.[0]
        if (file) onText(await file.text())
        e.target.value = ''
      }}
    />
  )
}

function normGroup(s: string): string {
  const t = s.trim().toLowerCase().replace(/\s+/g, ' ')
  return /^\d+$/.test(t) ? `group ${t}` : t
}

function resolveClassId(classes: { id: string; name: string }[], cell: string): string | null {
  const t = cell.toLowerCase().trim()
  const exact = classes.find((c) => c.name.toLowerCase() === t)
  if (exact) return exact.id
  const contains = classes.filter((c) => c.name.toLowerCase().includes(t))
  return contains.length === 1 ? contains[0].id : null
}

function resolveGroupId(
  classes: { id: string; name: string }[],
  groups: GroupWithCohort[],
  classCell: string,
  groupCell: string,
): string | null {
  const cid = resolveClassId(classes, classCell)
  if (!cid) return null
  const want = normGroup(groupCell)
  return groups.find((g) => g.cohort_id === cid && g.name.toLowerCase() === want)?.id ?? null
}

function ImportStudents() {
  const qc = useQueryClient()
  const classesQ = useClasses()
  const groupsQ = useAllGroups()
  const [csv, setCsv] = useState('')
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState<ImportResult | null>(null)

  const classes = classesQ.data ?? []
  const groups = groupsQ.data ?? []

  async function run() {
    const rows = dropHeader(parseCsv(csv))
    if (rows.length === 0) {
      toast.error('Nothing to import')
      return
    }
    setBusy(true)
    setResult(null)
    const byEmail = new Map<string, { group_id: string; full_name: string; email: string }>()
    const errors: string[] = []
    for (const row of rows) {
      const name = row[0] ?? ''
      const classCell = row[1] ?? ''
      const groupCell = row[2] ?? ''
      const email = (row[3] ?? '').toLowerCase().trim()
      if (!name) {
        errors.push('(missing name) — row skipped')
        continue
      }
      if (!email) {
        errors.push(`${name}: missing email — row skipped`)
        continue
      }
      const gid = resolveGroupId(classes, groups, classCell, groupCell)
      if (!gid) {
        errors.push(`${name} <${email}>: unknown class/group "${classCell} / ${groupCell}"`)
        continue
      }
      byEmail.set(email, { group_id: gid, full_name: name, email })
    }

    const toUpsert = [...byEmail.values()]
    if (toUpsert.length > 0) {
      const { error } = await supabase.from('students').upsert(toUpsert, { onConflict: 'email' })
      if (error) {
        setBusy(false)
        setResult({ ok: 0, errors: [error.message, ...errors] })
        toast.error('Import failed')
        return
      }
      void qc.invalidateQueries({ queryKey: ['students'] })
      void qc.invalidateQueries({ queryKey: ['attendance-report'] })
    }
    setBusy(false)
    setResult({ ok: toUpsert.length, errors })
    if (toUpsert.length > 0) toast.success(`Imported / updated ${toUpsert.length} student(s)`)
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Import students</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <p className="text-muted-foreground text-sm">
          One row per student: <code>Name, Class, Group, Email</code>. <b>Email is required</b> and is
          the unique key — re-importing the same email updates that student. Class can be the full
          name or a unique part (e.g. <code>6P</code>); Group can be <code>Group 5</code> or{' '}
          <code>5</code>.
        </p>
        {classes.length > 0 && (
          <p className="text-muted-foreground text-xs">
            Classes: {classes.map((c) => c.name).join(' · ')}
          </p>
        )}
        <div className="flex flex-col gap-1">
          <Label>Upload a CSV file (or paste below)</Label>
          <CsvFileInput onText={setCsv} />
        </div>
        <Textarea
          rows={7}
          placeholder={'Alice Wong, MMin 6P Monday Morning, Group 1, alice@example.com\nBob Lee, 6L, 12, bob@example.com'}
          value={csv}
          onChange={(e) => setCsv(e.target.value)}
          className="font-mono text-xs"
        />
        <div className="flex justify-end">
          <Button onClick={() => void run()} disabled={busy || !csv.trim()}>
            {busy ? 'Importing…' : 'Import students'}
          </Button>
        </div>
        {result && <ResultBox result={result} noun="student(s)" />}
      </CardContent>
    </Card>
  )
}

function ImportVolunteers() {
  const qc = useQueryClient()
  const classesQ = useClasses()
  const groupsQ = useAllGroups()
  const [csv, setCsv] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null)
  const [result, setResult] = useState<ImportResult | null>(null)

  const classes = classesQ.data ?? []
  const groups = groupsQ.data ?? []

  async function run() {
    const rows = dropHeader(parseCsv(csv))
    if (rows.length === 0) {
      toast.error('Nothing to import')
      return
    }
    if (password.trim().length < 6) {
      toast.error('Temporary password must be at least 6 characters')
      return
    }
    setBusy(true)
    setResult(null)
    setProgress({ done: 0, total: rows.length })
    let ok = 0
    const errors: string[] = []
    for (let i = 0; i < rows.length; i++) {
      const name = rows[i][0] ?? ''
      const email = (rows[i][1] ?? '').trim()
      const phone = rows[i][2] ?? ''
      const classCell = rows[i][3] ?? ''
      const groupCell = rows[i][4] ?? ''
      if (!email) {
        errors.push(`${name || '(no name)'}: missing email — skipped`)
      } else {
        let groupId: string | null = null
        if (classCell && groupCell) {
          groupId = resolveGroupId(classes, groups, classCell, groupCell)
          if (!groupId) {
            errors.push(`${name || email}: class/group "${classCell} / ${groupCell}" not found — created without assignment`)
          }
        }
        const { error } = await supabase.rpc('admin_import_volunteer', {
          p_email: email,
          p_full_name: name,
          p_phone: phone || null,
          p_password: password,
          p_group_id: groupId,
        })
        if (error) errors.push(`${email}: ${error.message}`)
        else ok++
      }
      setProgress({ done: i + 1, total: rows.length })
    }
    setBusy(false)
    setResult({ ok, errors })
    if (ok > 0) {
      void qc.invalidateQueries({ queryKey: ['volunteers'] })
      void qc.invalidateQueries({ queryKey: ['volunteer-activity'] })
      void qc.invalidateQueries({ queryKey: ['assignments'] })
      toast.success(`Imported / updated ${ok} volunteer(s)`)
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Import volunteers</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <p className="text-muted-foreground text-sm">
          One row per volunteer: <code>Name, Email, Phone, Class, Group</code> (Phone/Class/Group
          optional). If Class + Group are given, the volunteer is assigned to that group. New
          accounts get the temporary password below; re-importing an existing email just updates them.
        </p>
        <div className="flex flex-col gap-1">
          <Label htmlFor="temp-pw">Temporary password (for new accounts)</Label>
          <Input
            id="temp-pw"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="at least 6 characters"
            className="w-[260px]"
          />
        </div>
        <div className="flex flex-col gap-1">
          <Label>Upload a CSV file (or paste below)</Label>
          <CsvFileInput onText={setCsv} />
        </div>
        <Textarea
          rows={7}
          placeholder={'Alice Wong, alice@example.com, +12025550111, MMin 6P Monday Morning, Group 1\nBob Lee, bob@example.com, , 6L, 12'}
          value={csv}
          onChange={(e) => setCsv(e.target.value)}
          className="font-mono text-xs"
        />
        <div className="flex items-center justify-end gap-3">
          {busy && progress && (
            <span className="text-muted-foreground text-sm">
              {progress.done}/{progress.total}…
            </span>
          )}
          <Button onClick={() => void run()} disabled={busy || !csv.trim()}>
            {busy ? 'Creating…' : 'Import volunteers'}
          </Button>
        </div>
        {result && <ResultBox result={result} noun="volunteer(s)" />}
      </CardContent>
    </Card>
  )
}

export function ImportAdmin() {
  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <ImportStudents />
      <ImportVolunteers />
    </div>
  )
}
