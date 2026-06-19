import logoUrl from '@/assets/apiis-logo.png'
import { cn } from '@/lib/utils'

/**
 * APIIS 官方 logo（地球徽标 + APIIS 字标）。
 * 源图经裁剪透明边 + 缩放 + 调色板量化压缩到 ~16KB（原 264KB），
 * 作为 Vite 打包的同源资源引入（不受 CSP 外链限制），h-* 由调用方控制显示高度。
 */
export function ApiisLogo({ className }: { className?: string }) {
  return (
    <img
      src={logoUrl}
      alt="APIIS"
      width={243}
      height={300}
      draggable={false}
      className={cn('h-8 w-auto select-none', className)}
    />
  )
}
