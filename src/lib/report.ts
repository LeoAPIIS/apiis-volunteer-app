import { supabase } from '@/lib/supabase'

export interface ReportStudent {
  id: string
  full_name: string
  group_name: string
  class_name: string
}

export interface ReportCell {
  score: number | null // contribution 0-3
  note: string // 志愿者备注 / remark
}

export interface ReportData {
  students: ReportStudent[]
  dates: string[] // 排序后的去重上课日期（自动跳过没课的周）
  cells: Record<string, Record<string, ReportCell>>
}

/** 拉取并透视为「学员 × 周」报表（含 Contribution 分数与备注）。传 classId 限定班级，否则全部。 */
export async function fetchReportData(classId?: string): Promise<ReportData> {
  let studentQuery = supabase
    .from('students')
    .select('id, full_name, groups!inner(name, cohort_id, cohorts(name))')
    .order('full_name')
  if (classId) studentQuery = studentQuery.eq('groups.cohort_id', classId)
  const { data: sData, error: sErr } = await studentQuery
  if (sErr) throw sErr

  const students: ReportStudent[] = (sData ?? []).map((r) => {
    const rec = r as unknown as {
      id: string
      full_name: string
      groups: { name: string; cohorts: { name: string } | null } | null
    }
    return {
      id: rec.id,
      full_name: rec.full_name,
      group_name: rec.groups?.name ?? '',
      class_name: rec.groups?.cohorts?.name ?? '',
    }
  })
  students.sort(
    (a, b) =>
      a.class_name.localeCompare(b.class_name) ||
      a.group_name.localeCompare(b.group_name, undefined, { numeric: true }) ||
      a.full_name.localeCompare(b.full_name),
  )

  let attQuery = supabase
    .from('attendance_records')
    .select('student_id, session_date, contribution, notes, groups!inner(cohort_id)')
  if (classId) attQuery = attQuery.eq('groups.cohort_id', classId)
  const { data: aData, error: aErr } = await attQuery
  if (aErr) throw aErr

  const records = (aData ?? []) as unknown as {
    student_id: string
    session_date: string
    contribution: number | null
    notes: string | null
  }[]

  const dateSet = new Set<string>()
  const cells: ReportData['cells'] = {}
  for (const rec of records) {
    dateSet.add(rec.session_date)
    const note = rec.notes ?? ''
    const score = rec.contribution ?? null
    if (score !== null || note.trim() !== '') {
      cells[rec.student_id] ??= {}
      cells[rec.student_id][rec.session_date] = { score, note }
    }
  }
  return { students, dates: Array.from(dateSet).sort(), cells }
}

/** 导出 Excel：sheet 1「Contribution」分数；sheet 2「Remarks」备注。均为 学员 × 周。返回学员数。 */
export async function exportStudentMatrix(opts: { classId?: string; fileName?: string }): Promise<number> {
  const { students, dates, cells } = await fetchReportData(opts.classId)

  // 动态导入：xlsx 较大，仅在导出时加载。
  const XLSX = await import('xlsx')

  // 两行表头：每个日期占两列（Score / Remark），日期作为合并的上层标题。
  const top: (string | number)[] = ['Class', 'Group', 'Student']
  const sub: (string | number)[] = ['', '', '']
  for (const d of dates) {
    top.push(d, '')
    sub.push('Score', 'Remark')
  }
  const aoa: (string | number)[][] = [top, sub]
  for (const s of students) {
    const row: (string | number)[] = [s.class_name, s.group_name, s.full_name]
    for (const d of dates) {
      const c = cells[s.id]?.[d]
      row.push(c && c.score !== null ? c.score : '', c?.note ?? '')
    }
    aoa.push(row)
  }

  const ws = XLSX.utils.aoa_to_sheet(aoa)
  const merges: { s: { r: number; c: number }; e: { r: number; c: number } }[] = []
  for (let c = 0; c < 3; c++) merges.push({ s: { r: 0, c }, e: { r: 1, c } }) // Class/Group/Student 竖向合并
  for (let i = 0; i < dates.length; i++) {
    const c = 3 + i * 2
    merges.push({ s: { r: 0, c }, e: { r: 0, c: c + 1 } }) // 日期横跨 Score+Remark 两列
  }
  ws['!merges'] = merges

  const wb = XLSX.utils.book_new()
  XLSX.utils.book_append_sheet(wb, ws, 'Report')
  XLSX.writeFile(wb, opts.fileName ?? 'students-report.xlsx')
  return students.length
}
