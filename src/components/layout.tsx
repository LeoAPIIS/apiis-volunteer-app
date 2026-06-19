import { Link, Outlet } from 'react-router-dom'
import { Bell } from 'lucide-react'
import { useAuth } from '@/lib/auth'
import { useUnreadCount } from '@/hooks/use-scheduling'
import { ApiisLogo } from '@/components/apiis-logo'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'

function initialsOf(name: string): string {
  const trimmed = name.trim()
  return trimmed ? trimmed.slice(0, 2).toUpperCase() : '?'
}

export function Layout() {
  const { profile, signOut } = useAuth()
  const { data: unread = 0 } = useUnreadCount()
  const roleLabel =
    profile?.role === 'super_admin' ? 'Super Admin' : profile?.role === 'admin' ? 'Admin' : 'Volunteer'

  return (
    <div className="flex min-h-svh flex-col">
      <header className="bg-background/80 supports-[backdrop-filter]:bg-background/65 sticky top-0 z-40 border-b backdrop-blur">
        <div className="mx-auto flex h-14 w-full max-w-6xl items-center justify-between px-4">
          <Link to="/" className="flex items-center gap-2.5" aria-label="APIIS Volunteers — home">
            <ApiisLogo className="h-9 w-auto" />
            <span aria-hidden className="bg-border hidden h-5 w-px sm:block" />
            <span className="text-muted-foreground hidden text-sm font-medium sm:inline">Volunteers</span>
          </Link>
          <div className="flex items-center gap-1">
            <Button variant="ghost" size="icon" asChild className="relative">
              <Link to="/notifications" aria-label="Notifications">
                <Bell className="size-5" />
                {unread > 0 && (
                  <span className="bg-primary text-primary-foreground absolute -top-0.5 -right-0.5 flex size-4 items-center justify-center rounded-full text-[10px] leading-none">
                    {unread > 9 ? '9+' : unread}
                  </span>
                )}
              </Link>
            </Button>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="ghost" className="gap-2 px-2">
                  <Avatar className="size-7">
                    <AvatarFallback className="text-xs">
                      {initialsOf(profile?.full_name ?? '')}
                    </AvatarFallback>
                  </Avatar>
                  <span className="hidden text-sm sm:inline">{profile?.full_name}</span>
                  <Badge variant="secondary">{roleLabel}</Badge>
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-48">
                <DropdownMenuLabel className="truncate">{profile?.full_name}</DropdownMenuLabel>
                <DropdownMenuSeparator />
                <DropdownMenuItem asChild>
                  <Link to="/account">Account</Link>
                </DropdownMenuItem>
                <DropdownMenuItem onClick={() => void signOut()}>Sign out</DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>
      </header>
      <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-6">
        <Outlet />
      </main>
    </div>
  )
}
