import { useState } from 'react'
import { toast } from 'sonner'
import { nextWeekMonday } from '@/lib/date'
import {
  useAppSettings,
  useRunSummarize,
  useRunWeeklyCheck,
  useUpdateAppSettings,
  useWeekAvailability,
  useWeekCoverage,
} from '@/hooks/use-scheduling'
import type { AppSettings } from '@/types'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Checkbox } from '@/components/ui/checkbox'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

interface SavePatch {
  reminders_enabled: boolean
  term_break_start: string | null
  term_break_end: string | null
}

function SettingsForm({
  settings,
  onSave,
  saving,
}: {
  settings: AppSettings
  onSave: (p: SavePatch) => void
  saving: boolean
}) {
  const [enabled, setEnabled] = useState(settings.reminders_enabled)
  const [start, setStart] = useState(settings.term_break_start ?? '')
  const [end, setEnd] = useState(settings.term_break_end ?? '')

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center gap-2">
        <Checkbox
          id="reminders"
          checked={enabled}
          onCheckedChange={(v) => setEnabled(v === true)}
        />
        <Label htmlFor="reminders">Weekly reminders enabled</Label>
      </div>
      <div className="flex flex-wrap items-end gap-3">
        <div className="flex flex-col gap-1">
          <Label htmlFor="bs">Term break start</Label>
          <Input id="bs" type="date" value={start} onChange={(e) => setStart(e.target.value)} className="w-[170px]" />
        </div>
        <div className="flex flex-col gap-1">
          <Label htmlFor="be">Term break end</Label>
          <Input id="be" type="date" value={end} onChange={(e) => setEnd(e.target.value)} className="w-[170px]" />
        </div>
        <Button
          size="sm"
          disabled={saving}
          onClick={() =>
            onSave({
              reminders_enabled: enabled,
              term_break_start: start || null,
              term_break_end: end || null,
            })
          }
        >
          {saving ? 'Saving…' : 'Save settings'}
        </Button>
      </div>
      <p className="text-muted-foreground text-xs">
        Weekly reminders are skipped for weeks within the term break.
      </p>
    </div>
  )
}

export function SchedulingAdmin() {
  const week = nextWeekMonday()
  const settingsQ = useAppSettings()
  const updateSettings = useUpdateAppSettings()
  const runWeekly = useRunWeeklyCheck()
  const runSummarize = useRunSummarize()
  const availQ = useWeekAvailability(week)
  const coverQ = useWeekCoverage(week)

  function saveSettings(p: SavePatch) {
    updateSettings.mutate(p, {
      onSuccess: () => toast.success('Settings saved'),
      onError: (e) => toast.error(`Failed: ${(e as Error).message}`),
    })
  }

  const avail = availQ.data ?? []
  const available = avail.filter((a) => a.is_available === true).length
  const unavailable = avail.filter((a) => a.is_available === false).length
  const noResponse = avail.filter((a) => a.is_available === null).length
  const coverage = coverQ.data ?? []

  return (
    <div className="flex flex-col gap-6">
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Reminder settings</CardTitle>
        </CardHeader>
        <CardContent>
          {settingsQ.data ? (
            <SettingsForm settings={settingsQ.data} onSave={saveSettings} saving={updateSettings.isPending} />
          ) : (
            <p className="text-muted-foreground text-sm">Loading…</p>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Run now (manual)</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-2">
          <Button
            variant="outline"
            size="sm"
            disabled={runWeekly.isPending}
            onClick={() =>
              runWeekly.mutate(undefined, {
                onSuccess: (n) => toast.success(`Weekly check done — ${n} volunteer(s) notified`),
                onError: (e) => toast.error(`Failed: ${(e as Error).message}`),
              })
            }
          >
            Run weekly availability check
          </Button>
          <Button
            variant="outline"
            size="sm"
            disabled={runSummarize.isPending}
            onClick={() =>
              runSummarize.mutate(undefined, {
                onSuccess: (n) => toast.success(`Summary done — ${n} open coverage request(s)`),
                onError: (e) => toast.error(`Failed: ${(e as Error).message}`),
              })
            }
          >
            Run coverage summary
          </Button>
          <p className="text-muted-foreground w-full text-xs">
            Targets the week of {week}. Normally these run automatically (Sat/Sun) via pg_cron.
          </p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Availability — week of {week}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-4 text-sm">
          <span className="text-green-600">Available: {available}</span>
          <span className="text-destructive">Unavailable: {unavailable}</span>
          <span className="text-muted-foreground">No response: {noResponse}</span>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Coverage requests — week of {week}</CardTitle>
        </CardHeader>
        <CardContent>
          {coverage.length === 0 ? (
            <p className="text-muted-foreground text-sm">No coverage requests.</p>
          ) : (
            <div className="flex flex-col gap-2">
              {coverage.map((c) => (
                <div
                  key={c.id}
                  className="flex items-center justify-between gap-2 rounded-md border p-2 text-sm"
                >
                  <span>
                    <span className="font-medium">{c.group_name}</span>
                    <span className="text-muted-foreground"> · {c.class_name}</span>
                  </span>
                  {c.status === 'open' ? (
                    <Badge variant="outline">Open</Badge>
                  ) : (
                    <Badge variant="secondary">Covered by {c.coverer ?? '—'}</Badge>
                  )}
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
