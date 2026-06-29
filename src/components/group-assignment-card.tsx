import { useState } from 'react'
import { X } from 'lucide-react'
import { toast } from 'sonner'
import {
  useAssignVolunteer,
  useSetGroupCheckMark,
  useUnassign,
  type CheckStatus,
} from '@/hooks/use-assignments'
import type { GroupWithCohort } from '@/hooks/use-groups'
import type { Assignment, Profile } from '@/types'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'

interface Props {
  group: GroupWithCohort
  users: Profile[]
  assignments: Assignment[]
  checkStatus: CheckStatus | null
  originals: Map<string, string> // volunteer_id → 原属组短码,如 "7L-G7"(用于补位/管理员指派徽章)
}

export function GroupAssignmentCard({
  group,
  users,
  assignments,
  checkStatus,
  originals,
}: Props) {
  const assign = useAssignVolunteer()
  const unassign = useUnassign()
  const setMark = useSetGroupCheckMark()
  const [selected, setSelected] = useState('')

  const groupAssignments = assignments.filter((a) => a.group_id === group.id)
  const assignedIds = new Set(groupAssignments.map((a) => a.volunteer_id))
  // 可分配名单：排除 super_admin(itsupport);名字从「全部用户」解析,故升级为 admin 后仍正确显示
  const available = users.filter((u) => u.role !== 'super_admin' && !assignedIds.has(u.id))
  const nameOf = (id: string) => users.find((u) => u.id === id)?.full_name ?? 'Unknown'

  async function onAssign() {
    if (!selected) return
    try {
      await assign.mutateAsync({ groupId: group.id, volunteerId: selected })
      setSelected('')
      toast.success('Volunteer assigned')
    } catch (e) {
      toast.error(`Failed: ${(e as Error).message}`)
    }
  }

  async function onRemove(a: Assignment) {
    try {
      await unassign.mutateAsync(a.id)
      toast.success('Assignment removed')
    } catch (e) {
      toast.error(`Failed: ${(e as Error).message}`)
    }
  }

  // 临时标记本周「原负责志愿者到没到」(再点一次取消);不计入任何数据,每周三自动清空
  function toggleMark(next: CheckStatus) {
    setMark.mutate(
      { groupId: group.id, status: checkStatus === next ? null : next },
      { onError: (e) => toast.error(`Failed: ${(e as Error).message}`) },
    )
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center justify-between gap-2 text-base">
          <span>{group.name}</span>
          {group.cohort?.name && (
            <Badge variant="outline" className="shrink-0 font-normal">
              {group.cohort.name}
            </Badge>
          )}
        </CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <div className="flex flex-wrap gap-2">
          {groupAssignments.length === 0 ? (
            <span className="text-muted-foreground text-sm">No volunteers assigned</span>
          ) : (
            groupAssignments.map((a) => {
              // 三种来源:补位(coverage_week 非空)→ 浅绿;管理员手动指派(source=manual)→ 深蓝;
              // 导入名单/本来的负责人 → 保持原样(灰)。补位颜色优先级最高。
              const isCoverage = a.coverage_week != null
              const isManual = !isCoverage && a.source === 'manual'
              // 补位/管理员指派的人,名字后标其原属组(如 "(7L-G7)")
              const orig = isCoverage || isManual ? originals.get(a.volunteer_id) : undefined
              const tint = isCoverage
                ? ' bg-green-100 text-green-900 dark:bg-green-900/40 dark:text-green-100'
                : isManual
                  ? ' bg-blue-700 text-white dark:bg-blue-700'
                  : ''
              return (
                <Badge
                  key={a.id}
                  variant="secondary"
                  className={`gap-1 pr-1${tint}`}
                  title={
                    isCoverage
                      ? `Covering (week of ${a.coverage_week})`
                      : isManual
                        ? 'Assigned by an admin'
                        : 'From the roster'
                  }
                >
                  {nameOf(a.volunteer_id)}
                  {orig ? <span className="font-normal opacity-80">&nbsp;({orig})</span> : null}
                  <button
                    type="button"
                    onClick={() => void onRemove(a)}
                    className="hover:text-destructive rounded-sm"
                    aria-label={`Remove ${nameOf(a.volunteer_id)}`}
                  >
                    <X className="size-3" />
                  </button>
                </Badge>
              )
            })
          )}
        </div>
        {available.length > 0 ? (
          <div className="flex items-center gap-2">
            <Select value={selected} onValueChange={setSelected}>
              <SelectTrigger className="w-[220px]">
                <SelectValue placeholder="Choose someone" />
              </SelectTrigger>
              <SelectContent>
                {available.map((v) => (
                  <SelectItem key={v.id} value={v.id}>
                    {v.full_name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Button onClick={() => void onAssign()} disabled={!selected || assign.isPending}>
              Assign
            </Button>
          </div>
        ) : (
          <span className="text-muted-foreground text-sm">All volunteers assigned</span>
        )}

        <div className="flex flex-wrap items-center gap-2 border-t pt-3">
          <span className="text-muted-foreground text-xs">This week — original showed up?</span>
          <Button
            size="sm"
            variant="outline"
            className={
              checkStatus === 'present' ? 'bg-brand-green hover:bg-brand-green/90 text-white' : ''
            }
            disabled={setMark.isPending}
            onClick={() => toggleMark('present')}
          >
            Came
          </Button>
          <Button
            size="sm"
            variant="outline"
            className={
              checkStatus === 'absent' ? 'bg-destructive hover:bg-destructive/90 text-white' : ''
            }
            disabled={setMark.isPending}
            onClick={() => toggleMark('absent')}
          >
            No-show
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}
