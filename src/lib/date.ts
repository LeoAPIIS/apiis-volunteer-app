/** 机构所在时区(新加坡 = UTC+8)的「今天」(YYYY-MM-DD)。
 *  用它而非浏览器本地日期,确保各地志愿者在同一时刻(新加坡的午夜)翻周。 */
export function todaySG(): string {
  return new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Singapore' })
}

/** 下周一的日期 (YYYY-MM-DD)，与 SQL 的 next_week_monday() 一致：本周一 + 7 天(按新加坡时间)。 */
export function nextWeekMonday(): string {
  const [y, m, d] = todaySG().split('-').map(Number)
  const base = new Date(Date.UTC(y, m - 1, d)) // 用 UTC 锚定该日历日,避免本地时区把日期挪掉
  const daysSinceMonday = (base.getUTCDay() + 6) % 7 // 周一=0 … 周日=6
  base.setUTCDate(base.getUTCDate() - daysSinceMonday + 7)
  return base.toISOString().slice(0, 10)
}
