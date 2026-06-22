import { useState } from 'react'
import { RefreshCw, TriangleAlert } from 'lucide-react'
import { toast } from 'sonner'
import { nextWeekMonday } from '@/lib/date'
import {
  useAppSettings,
  useIsSessionWeek,
  useNextSession,
  useRunSummarize,
  useRunWeeklyCheck,
  useUpdateAppSettings,
  useWeekAvailability,
  useWeekCoverage,
} from '@/hooks/use-scheduling'
import type { AppSettings } from '@/types'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { Checkbox } from '@/components/ui/checkbox'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

interface SavePatch {
  reminders_enabled: boolean
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
      <div>
        <Button size="sm" disabled={saving} onClick={() => onSave({ reminders_enabled: enabled })}>
          {saving ? 'Saving…' : 'Save settings'}
        </Button>
      </div>
      <p className="text-muted-foreground text-xs">
        When on, reminders go out only on real class weeks — term breaks are skipped automatically from
        the course calendar.
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
  const { data: isSessionWeek } = useIsSessionWeek(week)
  const { data: nextSession } = useNextSession()
  const isBreak = isSessionWeek === false

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
  const openCoverage = coverage.filter((c) => c.status === 'open').length
  const needsAttention = !isBreak && (openCoverage > 0 || noResponse > 0)
  const allClear = !isBreak && avail.length > 0 && openCoverage === 0 && noResponse === 0

  return (
    <div className="flex flex-col gap-6">
      <div className="flex justify-end">
        <Button
          variant="outline"
          size="sm"
          disabled={availQ.isFetching || coverQ.isFetching}
          onClick={() => {
            void availQ.refetch()
            void coverQ.refetch()
          }}
        >
          <RefreshCw
            className={`size-4 ${availQ.isFetching || coverQ.isFetching ? 'animate-spin' : ''}`}
          />
          Refresh
        </Button>
      </div>
      {needsAttention && (
        <Card className="border-amber-400/60 bg-amber-50 dark:bg-amber-950/20">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base text-amber-700 dark:text-amber-400">
              <TriangleAlert className="size-4" /> Action needed — week of {week}
            </CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-1.5 text-sm">
            {openCoverage > 0 && (
              <p>
                <b>{openCoverage}</b> coverage request{openCoverage > 1 ? 's' : ''} still{' '}
                <b>unclaimed</b> — assign someone in <b>Groups &amp; Assignments</b> if no volunteer
                claims it.
              </p>
            )}
            {noResponse > 0 && (
              <p>
                <b>{noResponse}</b> volunteer{noResponse > 1 ? 's' : ''} haven&apos;t responded —
                non-responders don&apos;t trigger a coverage request, so follow up if needed.
              </p>
            )}
          </CardContent>
        </Card>
      )}
      {allClear && (
        <Card className="border-green-500/40">
          <CardContent className="py-4 text-sm text-green-700 dark:text-green-400">
            ✓ Nothing to action this week — no unclaimed coverage and everyone has responded.
          </CardContent>
        </Card>
      )}

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
            onClick={() => {
              if (
                !window.confirm(
                  'Run the weekly availability check now? It notifies ALL volunteers in-app (no email is sent).',
                )
              )
                return
              runWeekly.mutate(undefined, {
                onSuccess: (n) => toast.success(`Weekly check done — ${n} volunteer(s) notified`),
                onError: (e) => toast.error(`Failed: ${(e as Error).message}`),
              })
            }}
          >
            Run weekly availability check
          </Button>
          <Button
            variant="outline"
            size="sm"
            disabled={runSummarize.isPending}
            onClick={() => {
              if (
                !window.confirm(
                  'Run the coverage summary now? It creates coverage requests and notifies volunteers in-app (no email is sent).',
                )
              )
                return
              runSummarize.mutate(undefined, {
                onSuccess: (n) => toast.success(`Summary done — ${n} open coverage request(s)`),
                onError: (e) => toast.error(`Failed: ${(e as Error).message}`),
              })
            }}
          >
            Run coverage summary
          </Button>
          <p className="text-muted-foreground w-full text-xs">
            {isBreak
              ? `Next week (${week}) is a term break — a run is skipped.`
              : `Targets the week of ${week}.`}{' '}
            Normally these run automatically via pg_cron — availability Thu/Fri, coverage Sat/Sun (by curriculum).
          </p>
        </CardContent>
      </Card>

      {isBreak ? (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Next week</CardTitle>
          </CardHeader>
          <CardContent className="text-muted-foreground text-sm">
            The week of {week} is a term break — no class, so no reminders are sent.
            {nextSession && (
              <>
                {' '}
                Reminders resume the week of{' '}
                <span className="text-foreground font-medium">{nextSession}</span>.
              </>
            )}
          </CardContent>
        </Card>
      ) : (
        <>
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
        </>
      )}
    </div>
  )
}
