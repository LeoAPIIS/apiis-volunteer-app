// 自动生成（来自 "Curriculum & Calendar19062026.xlsx"）。请勿手改。
// 每套课程 0~66 周的上课日期（均为周一，week 0 = Orientation）。
// 真实日历中两套课程日期不同、各有多个 term break（break = 被跳过的周一）。

export type Curriculum = 'MMin 6' | 'MMin 7'

export interface WeekDate {
  week: number
  date: string // 'YYYY-MM-DD'（周一）
}

export const CALENDAR: Record<Curriculum, WeekDate[]> = {
  'MMin 6': [
    { week: 0, date: '2025-02-03' },
    { week: 1, date: '2025-02-10' },
    { week: 2, date: '2025-02-17' },
    { week: 3, date: '2025-02-24' },
    { week: 4, date: '2025-03-03' },
    { week: 5, date: '2025-03-10' },
    { week: 6, date: '2025-03-17' },
    { week: 7, date: '2025-03-24' },
    { week: 8, date: '2025-04-07' },
    { week: 9, date: '2025-04-14' },
    { week: 10, date: '2025-04-21' },
    { week: 11, date: '2025-04-28' },
    { week: 12, date: '2025-05-05' },
    { week: 13, date: '2025-05-12' },
    { week: 14, date: '2025-05-19' },
    { week: 15, date: '2025-05-26' },
    { week: 16, date: '2025-06-02' },
    { week: 17, date: '2025-06-09' },
    { week: 18, date: '2025-06-30' },
    { week: 19, date: '2025-07-07' },
    { week: 20, date: '2025-07-14' },
    { week: 21, date: '2025-07-21' },
    { week: 22, date: '2025-07-28' },
    { week: 23, date: '2025-08-04' },
    { week: 24, date: '2025-08-11' },
    { week: 25, date: '2025-08-18' },
    { week: 26, date: '2025-08-25' },
    { week: 27, date: '2025-09-01' },
    { week: 28, date: '2025-09-22' },
    { week: 29, date: '2025-09-29' },
    { week: 30, date: '2025-10-06' },
    { week: 31, date: '2025-10-13' },
    { week: 32, date: '2025-10-20' },
    { week: 33, date: '2025-10-27' },
    { week: 34, date: '2025-11-03' },
    { week: 35, date: '2026-02-09' },
    { week: 36, date: '2026-02-16' },
    { week: 37, date: '2026-02-23' },
    { week: 38, date: '2026-03-02' },
    { week: 39, date: '2026-03-09' },
    { week: 40, date: '2026-03-16' },
    { week: 41, date: '2026-03-23' },
    { week: 42, date: '2026-04-13' },
    { week: 43, date: '2026-04-20' },
    { week: 44, date: '2026-04-27' },
    { week: 45, date: '2026-05-04' },
    { week: 46, date: '2026-05-11' },
    { week: 47, date: '2026-05-18' },
    { week: 48, date: '2026-05-25' },
    { week: 49, date: '2026-06-01' },
    { week: 50, date: '2026-06-08' },
    { week: 51, date: '2026-06-29' },
    { week: 52, date: '2026-07-06' },
    { week: 53, date: '2026-07-13' },
    { week: 54, date: '2026-07-20' },
    { week: 55, date: '2026-07-27' },
    { week: 56, date: '2026-08-03' },
    { week: 57, date: '2026-08-10' },
    { week: 58, date: '2026-08-17' },
    { week: 59, date: '2026-08-24' },
    { week: 60, date: '2026-09-14' },
    { week: 61, date: '2026-09-21' },
    { week: 62, date: '2026-09-28' },
    { week: 63, date: '2026-10-05' },
    { week: 64, date: '2026-10-12' },
    { week: 65, date: '2026-10-19' },
    { week: 66, date: '2026-10-26' },
  ],
  'MMin 7': [
    { week: 0, date: '2026-02-02' },
    { week: 1, date: '2026-02-09' },
    { week: 2, date: '2026-02-16' },
    { week: 3, date: '2026-02-23' },
    { week: 4, date: '2026-03-02' },
    { week: 5, date: '2026-03-09' },
    { week: 6, date: '2026-03-16' },
    { week: 7, date: '2026-03-23' },
    { week: 8, date: '2026-04-13' },
    { week: 9, date: '2026-04-20' },
    { week: 10, date: '2026-04-27' },
    { week: 11, date: '2026-05-04' },
    { week: 12, date: '2026-05-11' },
    { week: 13, date: '2026-05-18' },
    { week: 14, date: '2026-05-25' },
    { week: 15, date: '2026-06-01' },
    { week: 16, date: '2026-06-08' },
    { week: 17, date: '2026-06-29' },
    { week: 18, date: '2026-07-06' },
    { week: 19, date: '2026-07-13' },
    { week: 20, date: '2026-07-20' },
    { week: 21, date: '2026-07-27' },
    { week: 22, date: '2026-08-03' },
    { week: 23, date: '2026-08-10' },
    { week: 24, date: '2026-08-17' },
    { week: 25, date: '2026-08-24' },
    { week: 26, date: '2026-09-14' },
    { week: 27, date: '2026-09-21' },
    { week: 28, date: '2026-09-28' },
    { week: 29, date: '2026-10-05' },
    { week: 30, date: '2026-10-12' },
    { week: 31, date: '2026-10-19' },
    { week: 32, date: '2026-10-26' },
    { week: 33, date: '2027-02-08' },
    { week: 34, date: '2027-02-15' },
    { week: 35, date: '2027-02-22' },
    { week: 36, date: '2027-03-01' },
    { week: 37, date: '2027-03-08' },
    { week: 38, date: '2027-03-15' },
    { week: 39, date: '2027-03-22' },
    { week: 40, date: '2027-03-29' },
    { week: 41, date: '2027-04-12' },
    { week: 42, date: '2027-04-19' },
    { week: 43, date: '2027-04-26' },
    { week: 44, date: '2027-05-03' },
    { week: 45, date: '2027-05-10' },
    { week: 46, date: '2027-05-17' },
    { week: 47, date: '2027-05-24' },
    { week: 48, date: '2027-05-31' },
    { week: 49, date: '2027-06-07' },
    { week: 50, date: '2027-06-21' },
    { week: 51, date: '2027-06-28' },
    { week: 52, date: '2027-07-05' },
    { week: 53, date: '2027-07-12' },
    { week: 54, date: '2027-07-19' },
    { week: 55, date: '2027-07-26' },
    { week: 56, date: '2027-08-02' },
    { week: 57, date: '2027-08-09' },
    { week: 58, date: '2027-08-16' },
    { week: 59, date: '2027-08-23' },
    { week: 60, date: '2027-08-30' },
    { week: 61, date: '2027-09-06' },
    { week: 62, date: '2027-09-20' },
    { week: 63, date: '2027-09-27' },
    { week: 64, date: '2027-10-04' },
    { week: 65, date: '2027-10-11' },
    { week: 66, date: '2027-10-18' },
  ],
}

const DATE_TO_WEEK: Record<Curriculum, Record<string, number>> = {
  'MMin 6': Object.fromEntries(CALENDAR['MMin 6'].map((w) => [w.date, w.week])),
  'MMin 7': Object.fromEntries(CALENDAR['MMin 7'].map((w) => [w.date, w.week])),
}

/** 班级名 → 课程体系（名字含 "MMin 7"/"MMin 6"）。无法识别返回 null。 */
export function curriculumForClass(className: string | null | undefined): Curriculum | null {
  if (!className) return null
  if (className.includes('MMin 7')) return 'MMin 7'
  if (className.includes('MMin 6')) return 'MMin 6'
  return null
}

export function weeksForCurriculum(c: Curriculum): WeekDate[] {
  return CALENDAR[c]
}

/** 周次 → 该课程的上课日期。 */
export function dateForWeek(c: Curriculum, week: number): string | undefined {
  return CALENDAR[c].find((w) => w.week === week)?.date
}

/** 上课日期 → 周次（不是上课日返回 null）。 */
export function weekForDate(c: Curriculum, dateISO: string): number | null {
  return DATE_TO_WEEK[c][dateISO] ?? null
}

/** 标签：week 0 显示 Orientation，其余 Week N。 */
export function weekLabel(week: number): string {
  return week === 0 ? 'Orientation' : `Week ${week}`
}

/** 当前/最近一周：日期 <= today 的最大周次（用作下拉默认值）。 */
export function currentWeek(c: Curriculum, todayISO: string): number {
  let chosen = CALENDAR[c][0].week
  for (const w of CALENDAR[c]) {
    if (w.date <= todayISO) chosen = w.week
    else break
  }
  return chosen
}
