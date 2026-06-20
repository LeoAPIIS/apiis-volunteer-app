import { Routes, Route, Navigate } from 'react-router-dom'
import { useAuth, roleHome } from '@/lib/auth'
import { ProtectedRoute } from '@/components/protected-route'
import { RequireRole } from '@/components/require-role'
import { Layout } from '@/components/layout'
import { LoginPage } from '@/pages/LoginPage'
import { ResetPasswordPage } from '@/pages/ResetPasswordPage'
import { DashboardPage } from '@/pages/DashboardPage'
import { AdminPage } from '@/pages/AdminPage'
import { GroupAttendancePage } from '@/pages/GroupAttendancePage'
import { NotificationsPage } from '@/pages/NotificationsPage'
import { AccountPage } from '@/pages/AccountPage'

/** 已登录时，根据角色跳到对应首页。 */
function HomeRedirect() {
  const { profile } = useAuth()
  return <Navigate to={roleHome(profile?.role)} replace />
}

function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route path="/reset-password" element={<ResetPasswordPage />} />
      <Route element={<ProtectedRoute />}>
        <Route path="/" element={<HomeRedirect />} />
        <Route element={<Layout />}>
          <Route
            path="/dashboard"
            element={
              <RequireRole role="volunteer">
                <DashboardPage />
              </RequireRole>
            }
          />
          <Route
            path="/admin"
            element={
              <RequireRole role="admin">
                <AdminPage />
              </RequireRole>
            }
          />
          <Route path="/groups/:groupId" element={<GroupAttendancePage />} />
          <Route path="/notifications" element={<NotificationsPage />} />
          <Route path="/account" element={<AccountPage />} />
        </Route>
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}

export default App
