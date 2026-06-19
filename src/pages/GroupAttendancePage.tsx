import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { ArrowLeft, Video } from 'lucide-react'
import { useAuth } from '@/lib/auth'
import { useGroup, useStudents } from '@/hooks/use-groups'
import { useAttendance } from '@/hooks/use-attendance'
import { AttendanceForm } from '@/components/attendance-form'
import { FullPageSpinner } from '@/components/full-page-spinner'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

function todayLocal(): string {
  return new Date().toLocaleDateString('en-CA') // YYYY-MM-DD
}

export function GroupAttendancePage() {
  const { groupId } = useParams<{ groupId: string }>()
  const { user } = useAuth()
  const [sessionDate, setSessionDate] = useState(todayLocal())

  const groupQ = useGroup(groupId)
  const studentsQ = useStudents(groupId)
  const attendanceQ = useAttendance(groupId, sessionDate)

  if (groupQ.isLoading || studentsQ.isLoading) return <FullPageSpinner />
  if (groupQ.isError || !groupQ.data) {
    return (
      <p className="text-muted-foreground text-sm">
        Group not found, or you may not have access.
      </p>
    )
  }

  const group = groupQ.data
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
        <Label htmlFor="session-date">Session date</Label>
        <Input
          id="session-date"
          type="date"
          value={sessionDate}
          onChange={(e) => setSessionDate(e.target.value)}
          className="w-[180px]"
        />
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
