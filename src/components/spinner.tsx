import { Loader2 } from 'lucide-react'
import { cn } from '@/lib/utils'

/** 就地加载指示器（转圈 + 文字）。用于标签页/列表等区域内的加载状态。 */
export function Spinner({ label = 'Loading…', className }: { label?: string; className?: string }) {
  return (
    <div
      className={cn(
        'text-muted-foreground flex items-center justify-center gap-2 py-12 text-sm',
        className,
      )}
      role="status"
      aria-live="polite"
    >
      <Loader2 className="size-5 animate-spin" />
      <span>{label}</span>
    </div>
  )
}
