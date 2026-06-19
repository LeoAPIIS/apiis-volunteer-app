/** 下周一的日期 (YYYY-MM-DD)，与 SQL 的 next_week_monday() 一致：本周一 + 7 天。 */
export function nextWeekMonday(): string {
  const d = new Date()
  const daysSinceMonday = (d.getDay() + 6) % 7 // 周一=0 … 周日=6
  d.setDate(d.getDate() - daysSinceMonday + 7)
  return d.toLocaleDateString('en-CA')
}
