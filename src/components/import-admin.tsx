import { useState } from 'react'
import { toast } from 'sonner'
import { useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { mapCsvColumns, parseCsv } from '@/lib/csv'
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

export function ImportStudents() {
  const qc = useQueryClient()
  const classesQ = useClasses()
  const groupsQ = useAllGroups()
  const [csv, setCsv] = useState('')
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState<ImportResult | null>(null)

  const classes = classesQ.data ?? []
  const groups = groupsQ.data ?? []

  async function run() {
    const { body: rows, get } = mapCsvColumns(parseCsv(csv), { name: 0, class: 1, group: 2, email: 3 })
    if (rows.length === 0) {
      toast.error('Nothing to import')
      return
    }
    setBusy(true)
    setResult(null)
    const byEmail = new Map<string, { group_id: string; full_name: string; email: string }>()
    const errors: string[] = []
    for (const row of rows) {
      const name = get(row, 'name')
      const classCell = get(row, 'class')
      const groupCell = get(row, 'group')
      const email = get(row, 'email').toLowerCase().trim()
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
          One row per student: <code>Name, Class, Group, Email</code> (keep a header row — columns are
          matched by name, so order doesn&apos;t matter). <b>Email is required</b> and is the unique
          key — re-importing the same email updates that student. Class can be the full name or a
          unique part (e.g. <code>6P</code>); Group can be <code>Group 5</code> or <code>5</code>.
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
          placeholder={'Name, Class, Group, Email\nAlice Wong, MMin 6P Monday Morning, 1, alice@example.com\nBob Lee, 6L, 12, bob@example.com'}
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

export function ImportVolunteers() {
  const qc = useQueryClient()
  const classesQ = useClasses()
  const groupsQ = useAllGroups()
  const [csv, setCsv] = useState('')
  const [busy, setBusy] = useState(false)
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null)
  const [result, setResult] = useState<ImportResult | null>(null)

  const classes = classesQ.data ?? []
  const groups = groupsQ.data ?? []

  async function run() {
    const { body: rows, get } = mapCsvColumns(parseCsv(csv), { name: 0, email: 1, class: 2, group: 3 })
    if (rows.length === 0) {
      toast.error('Nothing to import')
      return
    }
    setBusy(true)
    setResult(null)

    // 先按 email 聚合:累计该志愿者在文件里出现的所有组(去重、保持顺序)。
    // 一行多组("17,18")或同一志愿者多行,都会被合并成一份完整名单。
    const byEmail = new Map<string, { name: string; groupIds: string[] }>()
    const errors: string[] = []
    for (const row of rows) {
      const name = get(row, 'name')
      const email = get(row, 'email').trim().toLowerCase()
      const classCell = get(row, 'class')
      const groupCell = get(row, 'group')
      if (!email) {
        errors.push(`${name || '(no name)'}: missing email — skipped`)
        continue
      }
      const entry = byEmail.get(email) ?? { name, groupIds: [] }
      if (name && !entry.name) entry.name = name
      if (classCell && groupCell) {
        for (const tok of groupCell
          .split(/[,;/]+/)
          .map((t) => t.trim())
          .filter(Boolean)) {
          const gid = resolveGroupId(classes, groups, classCell, tok)
          if (!gid) errors.push(`${name || email}: class/group "${classCell} / ${tok}" not found`)
          else if (!entry.groupIds.includes(gid)) entry.groupIds.push(gid)
        }
      }
      byEmail.set(email, entry)
    }

    const entries = [...byEmail.entries()]
    setProgress({ done: 0, total: entries.length })
    let ok = 0
    for (let i = 0; i < entries.length; i++) {
      const [email, { name, groupIds }] = entries[i]
      const { data: uid, error } = await supabase.rpc('admin_import_volunteer', {
        p_email: email,
        p_full_name: name,
        p_phone: null,
        p_password: '123456', // 仅用于「新账号」的初始密码；已存在的用户 RPC 不会改其密码
        p_group_id: groupIds[0] ?? null,
      })
      if (error) {
        errors.push(`${email}: ${error.message}`)
      } else {
        ok++
        // 其余小组逐个追加分配（账号已由 RPC 建好/找到）
        if (uid && groupIds.length > 1) {
          const extra = groupIds.slice(1).map((gid) => ({
            group_id: gid,
            volunteer_id: uid as string,
          }))
          const { error: aErr } = await supabase
            .from('assignments')
            .upsert(extra, { onConflict: 'group_id,volunteer_id' })
          if (aErr) errors.push(`${email}: extra groups — ${aErr.message}`)
        }
        // 幂等(按班级):只清理该志愿者「在本次导入涉及的班级内、且不在本次名单里」的旧永久分配。
        // 例如导入他在 6P 的组,不会动他在 6L 等其它班级的组;补位(coverage)分配也不受影响。
        if (uid && groupIds.length > 0) {
          const importedSet = new Set(groupIds)
          // 本次导入涉及到的班级(cohort)
          const targetCohorts = new Set(
            groupIds
              .map((gid) => groups.find((g) => g.id === gid)?.cohort_id)
              .filter((c): c is string => !!c),
          )
          // 同班级里、不在本次名单内的组 → 待清理(其它班级一律保留)
          const stale = groups
            .filter((g) => targetCohorts.has(g.cohort_id) && !importedSet.has(g.id))
            .map((g) => g.id)
          if (stale.length > 0) {
            const { error: dErr } = await supabase
              .from('assignments')
              .delete()
              .eq('volunteer_id', uid as string)
              .is('coverage_week', null)
              .in('group_id', stale)
            if (dErr) errors.push(`${email}: cleanup old groups — ${dErr.message}`)
          }
        }
      }
      setProgress({ done: i + 1, total: entries.length })
    }
    setBusy(false)
    setResult({ ok, errors })
    if (ok > 0) {
      void qc.invalidateQueries({ queryKey: ['all-users'] })
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
          One row per volunteer: <code>Name, Email, Class, Group</code> (keep a header row — columns are
          matched by name). A volunteer can have <b>several groups</b> in one cell — write{' '}
          <code>&quot;17,18&quot;</code> (quoted) or <code>17;18</code>. New accounts are created with
          initial password <code>123456</code>; existing volunteers are only updated (their password
          isn&apos;t changed). <b>Re-importing updates that volunteer&apos;s groups only for the classes
          in the file</b> — their groups in other classes are left untouched — so the roster won&apos;t
          pile up duplicates.
        </p>
        <div className="flex flex-col gap-1">
          <Label>Upload a CSV file (or paste below)</Label>
          <CsvFileInput onText={setCsv} />
        </div>
        <Textarea
          rows={7}
          placeholder={'Name, Email, Class, Group\nAlice Wong, alice@example.com, MMin 6P Monday Morning, 1\nBob Lee, bob@example.com, MMin 6L Tuesday Night, 12'}
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

