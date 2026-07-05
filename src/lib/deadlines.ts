// 可用性 / 补位的截止时间。全部按组织时区 UTC+8 的“墙上时间”定义，
// 计算成 UTC 毫秒瞬间，便于与 Date.now() 比较（与浏览器所在时区无关）。

const TZ = 8 // UTC+8

/** 以「该周周一(ISO)+ 天数偏移」的那一天、UTC+8 的 hour:minute，返回 UTC 毫秒瞬间。 */
function instant(weekMondayISO: string, dayOffset: number, hour: number, minute: number): number {
  const [y, m, d] = weekMondayISO.split('-').map(Number)
  const day = new Date(Date.UTC(y, m - 1, d + dayOffset)) // 规整加减天数(跨月/跨年安全)
  return Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), hour - TZ, minute)
}

/** 可用性回复截止：该周周六 22:59（UTC+8）。 */
export function availabilityDeadline(weekMondayISO: string): number {
  return instant(weekMondayISO, -2, 22, 59)
}

/**
 * 补位认领截止（按班级，UTC+8）：
 *   MMin 6P → 周日 22:00 · MMin 6L → 周二 14:00 · MMin 7L → 周一 14:00 · MMin 7P → 周一 22:00
 * 识别不到班级返回 null（不设截止）。
 */
export function coverageDeadline(weekMondayISO: string, className: string): number | null {
  const code = (className.match(/MMin\s*(6P|6L|7P|7L)/i)?.[1] ?? '').toUpperCase()
  switch (code) {
    case '6P':
      return instant(weekMondayISO, -1, 22, 0) // Sunday 10pm
    case '6L':
      return instant(weekMondayISO, 1, 14, 0) // Tuesday 2pm
    case '7L':
      return instant(weekMondayISO, 0, 14, 0) // Monday 2pm
    case '7P':
      return instant(weekMondayISO, 0, 22, 0) // Monday 10pm
    default:
      return null
  }
}

export function isPast(deadlineMs: number): boolean {
  return Date.now() > deadlineMs
}

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
const pad = (n: number) => String(n).padStart(2, '0')

/** 把截止瞬间格式化成 UTC+8 墙上时间标签，如 "Sat 06-27 19:59"。 */
export function formatDeadline(deadlineMs: number): string {
  const d = new Date(deadlineMs + TZ * 3600 * 1000) // 偏到 UTC+8 后用 UTC 取值
  return `${DAYS[d.getUTCDay()]} ${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`
}
