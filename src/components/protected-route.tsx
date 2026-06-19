import { Navigate, Outlet } from 'react-router-dom'
import { useAuth } from '@/lib/auth'
import { FullPageSpinner } from '@/components/full-page-spinner'
import { Button } from '@/components/ui/button'

export function ProtectedRoute() {
  const { loading, session, profile, signOut } = useAuth()

  if (loading) return <FullPageSpinner />
  if (!session) return <Navigate to="/login" replace />

  // 已登录但加载不到 profile（异常）：提示并允许重新登录
  if (!profile) {
    return (
      <div className="flex min-h-svh flex-col items-center justify-center gap-4 p-6 text-center">
        <p className="text-muted-foreground text-sm">
          Couldn&apos;t load your profile. Please contact an administrator or sign in again.
        </p>
        <Button variant="outline" onClick={() => void signOut()}>
          Sign in again
        </Button>
      </div>
    )
  }

  return <Outlet />
}
