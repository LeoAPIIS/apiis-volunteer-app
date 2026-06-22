import { useState } from 'react'
import type { FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { useAuth } from '@/lib/auth'
import { useSubmitFeedback } from '@/hooks/use-feedback'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'

export function FeedbackPage() {
  const { user, profile } = useAuth()
  const submit = useSubmitFeedback()
  const navigate = useNavigate()
  const [message, setMessage] = useState('')

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    const text = message.trim()
    if (!user || text.length === 0) return
    try {
      await submit.mutateAsync({ userId: user.id, fullName: profile?.full_name ?? '', message: text })
      toast.success('Thanks! Your feedback was sent.')
      navigate(-1)
    } catch (err) {
      toast.error(`Failed: ${(err as Error).message}`)
    }
  }

  return (
    <div className="mx-auto w-full max-w-xl">
      <Card>
        <CardHeader>
          <CardTitle>Send feedback</CardTitle>
          <CardDescription>
            Tell us about a problem or a suggestion — an admin will read it.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={onSubmit} className="flex flex-col gap-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor="feedback-msg">Your feedback</Label>
              <Textarea
                id="feedback-msg"
                rows={6}
                required
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                placeholder="What's working, what's not, ideas to improve…"
              />
            </div>
            <div className="flex justify-end gap-2">
              <Button type="button" variant="outline" onClick={() => navigate(-1)}>
                Cancel
              </Button>
              <Button type="submit" disabled={submit.isPending || !message.trim()}>
                {submit.isPending ? 'Sending…' : 'Send feedback'}
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
