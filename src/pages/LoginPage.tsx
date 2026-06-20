import { useState } from 'react'
import type { FormEvent } from 'react'
import { Navigate } from 'react-router-dom'
import { Eye, EyeOff } from 'lucide-react'
import { toast } from 'sonner'
import { useAuth, roleHome } from '@/lib/auth'
import { supabase } from '@/lib/supabase'
import { FullPageSpinner } from '@/components/full-page-spinner'
import { ApiisLogo } from '@/components/apiis-logo'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

function translateAuthError(msg: string): string {
  const m = msg.toLowerCase()
  if (m.includes('invalid login credentials')) return 'Incorrect email or password'
  if (m.includes('email not confirmed')) return 'Email not confirmed. Please contact an administrator.'
  if (m.includes('rate limit')) return 'Too many attempts. Please try again later.'
  return msg
}

export function LoginPage() {
  const { loading, session, profile, signIn } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  if (loading) return <FullPageSpinner />
  if (session && profile) return <Navigate to={roleHome(profile.role)} replace />

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setSubmitting(true)
    setError(null)
    const { error } = await signIn(email, password)
    if (error) {
      setError(translateAuthError(error))
      setSubmitting(false)
    }
    // 成功后 auth 状态更新，上方的 <Navigate> 会自动跳转到对应首页
  }

  async function onForgot() {
    if (!email) {
      toast.error('Enter your email above first, then tap “Forgot password?”')
      return
    }
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/reset-password`,
    })
    if (error) {
      toast.error(translateAuthError(error.message))
      return
    }
    toast.success('If that email has an account, a password reset link is on its way.')
  }

  return (
    <div className="relative flex min-h-svh items-center justify-center overflow-hidden bg-gradient-to-br from-[#0d2438] via-[#0c3c60] to-[#0a2c49] p-4">
      {/* 柔光点缀，纯 CSS 渐变、零额外资源 */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-24 -right-24 size-96 rounded-full opacity-25 blur-3xl"
        style={{ background: 'radial-gradient(closest-side, #1690D0, transparent)' }}
      />
      <div
        aria-hidden
        className="pointer-events-none absolute -bottom-28 -left-24 size-96 rounded-full opacity-20 blur-3xl"
        style={{ background: 'radial-gradient(closest-side, #7CB518, transparent)' }}
      />

      <div className="relative z-10 w-full max-w-sm">
        <div className="mb-6 flex flex-col items-center text-center">
          <ApiisLogo className="h-24 w-auto" />
          <p className="mt-4 text-sm text-white/70">
            21st Century Training. For Christians. For Free
          </p>
        </div>

        <Card className="w-full shadow-xl">
        <CardHeader className="text-center">
          <CardTitle className="text-xl">Sign in</CardTitle>
        </CardHeader>
        <CardContent>
          <form onSubmit={onSubmit} className="flex flex-col gap-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                autoComplete="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@example.com"
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="password">Password</Label>
              <div className="relative">
                <Input
                  id="password"
                  type={showPassword ? 'text' : 'password'}
                  autoComplete="current-password"
                  required
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className="pr-10"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword((v) => !v)}
                  className="text-muted-foreground hover:text-foreground absolute inset-y-0 right-0 flex items-center px-3"
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                  aria-pressed={showPassword}
                  tabIndex={-1}
                >
                  {showPassword ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
                </button>
              </div>
            </div>
            <button
              type="button"
              onClick={() => void onForgot()}
              className="text-brand -mt-1 self-end text-xs hover:underline"
            >
              Forgot password?
            </button>
            {error && <p className="text-destructive text-sm">{error}</p>}
            <Button type="submit" disabled={submitting} className="w-full">
              {submitting ? 'Signing in…' : 'Sign in'}
            </Button>
          </form>
        </CardContent>
        </Card>

        <p className="mt-6 text-center text-xs text-white/45">APIIS Volunteer Management</p>
      </div>
    </div>
  )
}
