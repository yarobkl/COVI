import { createClient } from '@supabase/supabase-js'
import type { Database } from './database.types'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL ?? 'https://bmbwmwgfzrijglzcgjut.supabase.co'
const supabasePublishableKey =
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ?? 'sb_publishable_DoBPQwskWNP7Wo8sjbWUwA_BrDO4z0m'

export const supabase = createClient<Database>(supabaseUrl, supabasePublishableKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    flowType: 'pkce',
  },
})

/** localStorage key of the persisted session (supabase-js default: `sb-<project ref>-auth-token`). */
export const authStorageKey = `sb-${new URL(supabaseUrl).hostname.split('.')[0]}-auth-token`

/**
 * Account of the session persisted on this device, even when its access token has expired and
 * cannot be refreshed (no network). supabase-js keeps such a session and refreshes it when the
 * network is back; it removes it (SIGNED_OUT) on sign-out or when the server refuses the refresh
 * token. Read synchronously, so that the till can open offline without waiting for supabase-js,
 * whose token refresh retries for about 25 s before giving up.
 */
export function persistedUserId(): string | null {
  try {
    const raw = localStorage.getItem(authStorageKey)
    if (!raw) return null
    const session = JSON.parse(raw) as {
      refresh_token?: unknown
      user?: { id?: unknown } | null
    } | null
    const id = session?.user?.id
    return typeof id === 'string' && id && typeof session?.refresh_token === 'string' ? id : null
  } catch {
    return null
  }
}

/**
 * Removes the session persisted on this device, for a sign-out that supabase-js cannot complete
 * (offline with an expired token, it tries to refresh the token first and gives up).
 */
export function forgetPersistedSession() {
  for (const suffix of ['', '-code-verifier', '-user'])
    try {
      localStorage.removeItem(authStorageKey + suffix)
    } catch {
      // ignored: storage disabled
    }
}
