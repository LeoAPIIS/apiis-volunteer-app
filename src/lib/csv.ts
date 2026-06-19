/** 解析 CSV 文本为二维数组（支持双引号字段与 "" 转义）。 */
export function parseCsv(text: string): string[][] {
  const rows: string[][] = []
  for (const line of text.split(/\r?\n/)) {
    if (line.trim() === '') continue
    const fields: string[] = []
    let cur = ''
    let inQuotes = false
    for (let i = 0; i < line.length; i++) {
      const ch = line[i]
      if (inQuotes) {
        if (ch === '"') {
          if (line[i + 1] === '"') {
            cur += '"'
            i++
          } else inQuotes = false
        } else cur += ch
      } else if (ch === '"') inQuotes = true
      else if (ch === ',') {
        fields.push(cur)
        cur = ''
      } else cur += ch
    }
    fields.push(cur)
    rows.push(fields.map((f) => f.trim()))
  }
  return rows
}

/** 若首行看起来像表头则去掉。 */
export function dropHeader(rows: string[][]): string[][] {
  if (rows.length === 0) return rows
  const first = rows[0].join(',').toLowerCase()
  if (/\b(name|email|class|group|phone)\b|姓名|班级|组|邮箱|电话/.test(first)) {
    return rows.slice(1)
  }
  return rows
}
