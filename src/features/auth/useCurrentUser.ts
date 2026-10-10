import { useEffect, useState } from 'react'
import type { User } from '@supabase/supabase-js'
import { supabase } from '../../lib/supabase'

/** The signed-in account, read from the local session (no network call). */
export function useCurrentUser() {
  const [user, setUser] = useState<User | null>(null)
  useEffect(() => {
    let active = true
    void supabase.auth.getSession().then(({ data }) => {
      if (active) setUser(data.session?.user ?? null)
    })
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => setUser(session?.user ?? null))
    return () => {
      active = false
      subscription.unsubscribe()
    }
  }, [])
  return user
}
