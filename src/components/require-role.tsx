import type { ReactNode } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuth, roleHome } from '@/lib/auth'
import type { UserRole } from '@/types'

/** 限制只有指定角色可访问；角色不符则重定向到该用户自己的首页。 */
export function RequireRole({ role, children }: { role: UserRole; children: ReactNode }) {
  const { profile } = useAuth()
  if (!profile) return null
  // admin 区域同时允许 super_admin
  const allowed =
    role === 'admin'
      ? profile.role === 'admin' || profile.role === 'super_admin'
      : profile.role === role
  if (!allowed) return <Navigate to={roleHome(profile.role)} replace />
  return <>{children}</>
}
