import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { ArrowLeft, Video } from 'lucide-react'
import { useAuth } from '@/lib/auth'
import { useGroup, useStudents } from '@/hooks/use-groups'
import { useAttendance } from '@/hooks/use-attendance'
import {
  curriculumForClass,
  currentWeek,
  sessionDateForWeek,
  weekLabel,
  weeksForCurriculum,
} from '@/lib/calendar'
import { todaySG } from '@/lib/date'
import { AttendanceForm } from '@/components/attendance-form'
import { FullPageSpinner } from '@/components/full-page-spinner'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'

export function GroupAttendancePage() {
  const { groupId } = useParams<{ groupId: string }>()
  const { user, profile } = useAuth()
  const iAmSuper = profile?.role === 'super_admin'
  const [picked, setPicked] = useState<string | null>(null)

  const groupQ = useGroup(groupId)
  const studentsQ = useStudents(groupId)

  const group = groupQ.data
  const className = group?.cohort?.name ?? null
  const curriculum = curriculumForClass(className)
  const today = todaySG()
  // 当前周(非超管只能记当前周)；周二班的日期 = 周一锚点 +1 天；无法识别课程时退回普通日期选择
  const curWeek = curriculum ? currentWeek(curriculum, today) : null
  const defaultDate =
    curriculum && curWeek !== null ? sessionDateForWeek(curriculum, curWeek, className) : today
  const sessionDate = picked ?? defaultDate ?? today

  const attendanceQ = useAttendance(groupId, sessionDate)

  if (groupQ.isLoading || studentsQ.isLoading) return <FullPageSpinner />
  if (groupQ.isError || !group) {
    return (
      <p className="text-muted-foreground text-sm">
        Group not found, or you may not have access.
      </p>
    )
  }

  const students = studentsQ.data ?? []

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-2">
        <Link
          to="/"
          className="text-muted-foreground hover:text-foreground inline-flex w-fit items-center gap-1 text-sm"
        >
          <ArrowLeft className="size-4" /> Back
        </Link>
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">{group.name}</h1>
          <p className="text-muted-foreground mt-1 flex flex-wrap items-center gap-1 text-sm">
            <span>{group.cohort?.name}</span>
            {group.meeting_day && <span>· {group.meeting_day}</span>}
            {group.zoom_link && (
              <>
                <span>·</span>
                <a
                  href={group.zoom_link}
                  target="_blank"
                  rel="noreferrer"
                  className="hover:text-foreground inline-flex items-center gap-1"
                >
                  <Video className="size-3.5" /> Zoom
                </a>
              </>
            )}
          </p>
        </div>
      </div>

      <div className="flex flex-col gap-2">
        <Label htmlFor="session-week">Session week</Label>
        {curriculum ? (
          <>
            <Select value={sessionDate} onValueChange={setPicked}>
              <SelectTrigger id="session-week" className="w-[260px]">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {weeksForCurriculum(curriculum).map((w) => {
                  const d = sessionDateForWeek(curriculum, w.week, className) ?? w.date
                  return (
                    <SelectItem key={w.week} value={d} disabled={!iAmSuper && w.week !== curWeek}>
                      {weekLabel(w.week)} · {d}
                    </SelectItem>
                  )
                })}
              </SelectContent>
            </Select>
            <p className="text-muted-foreground text-xs">
              {iAmSuper
                ? 'Super admin: you can record any week.'
                : 'You can record the current week only.'}
            </p>
          </>
        ) : (
          <Input
            id="session-week"
            type="date"
            value={sessionDate}
            onChange={(e) => setPicked(e.target.value)}
            className="w-[180px]"
          />
        )}
      </div>

      {students.length === 0 ? (
        <p className="text-muted-foreground text-sm">
          No students found for this group, or you may not have access.
        </p>
      ) : attendanceQ.isLoading ? (
        <p className="text-muted-foreground text-sm">Loading attendance…</p>
      ) : (
        <AttendanceForm
          key={`${groupId}:${sessionDate}`}
          students={students}
          existing={attendanceQ.data ?? []}
          groupId={groupId as string}
          sessionDate={sessionDate}
          volunteerId={user?.id ?? ''}
        />
      )}
    </div>
  )
}
