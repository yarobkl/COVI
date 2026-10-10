import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react'
import type { AuthChangeEvent, Session } from '@supabase/supabase-js'
import { forgetPersistedSession, persistedUserId, supabase } from '../../lib/supabase'
import { listenForDesktopOAuth } from '../../lib/desktopAuth'
import { cachedShop, rememberShop, setSyncUser, withTimeout } from '../../lib/offline'
import { clearPrivateCaches } from '../../lib/pwa'
import type { Shop } from '../../lib/types'
import { CreateShopForm } from './CreateShopForm'
import { LoginForm, type AuthMode } from './LoginForm'

/**
 * - `ready`: the till opens on `shop`. `confirmed` is false while it is the copy remembered on this
 *   device (no network, or session waiting for its token refresh).
 * - `no-shop`: the server answered, with a valid session, that this account has no shop yet.
 * - `error`: the shop could not be loaded and none is remembered: never the creation form.
 */
type Gate =
  | { status: 'loading' }
  | { status: 'signed-out' }
  | { status: 'ready'; userId: string; shop: Shop; confirmed: boolean }
  | { status: 'no-shop'; userId: string }
  | { status: 'error'; userId: string; message: string }

const SHOP_TIMEOUT_MS = 15000
const OFFLINE_FIRST_LAUNCH =
  'Pas de connexion. COVI a besoin d’Internet une première fois pour charger votre commerce sur cet appareil. Réessayez dès que le réseau revient.'
const SHOP_LOAD_FAILED =
  'Impossible de charger votre commerce. Vérifiez votre connexion puis réessayez.'

/** Opens straight on the remembered shop when this device has a persisted session for it. */
function initialGate(): Gate {
  const userId = persistedUserId()
  const shop = userId ? cachedShop<Shop>(userId) : null
  return userId && shop
    ? { status: 'ready', userId, shop, confirmed: false }
    : { status: 'loading' }
}

/**
 * Renders the sign-in screens until a session and its shop are available, then hands the shop to
 * `children`. Offline, a persisted session (even with an expired token) and the shop remembered on
 * this device are enough to open the till; the session is refreshed when the network is back.
 */
export function AuthGate({
  children,
  onSimulation,
}: {
  children: (
    shop: Shop,
    signOut: () => Promise<void>,
    updateShop: (shop: Shop) => void,
  ) => ReactNode
  onSimulation: () => void
}) {
  const [gate, setGate] = useState<Gate>(initialGate)
  const [mode, setMode] = useState<AuthMode>('login')
  const [message, setMessage] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const gateRef = useRef(gate)
  useEffect(() => {
    gateRef.current = gate
  }, [gate])
  const loadSeq = useRef(0)
  useEffect(() => {
    let dispose: () => void = () => {}
    let active = true
    void listenForDesktopOAuth((message) => setMessage(message))
      .then((unlisten) => {
        if (active) dispose = unlisten
        else unlisten()
      })
      .catch(() => setMessage('Impossible d’initialiser le retour de connexion.'))
    return () => {
      active = false
      dispose()
    }
  }, [])

  const loadShop = useCallback(async (userId: string) => {
    const seq = ++loadSeq.current
    let data: Shop | null = null,
      failed = false
    try {
      const result = await withTimeout(
        Promise.resolve(
          supabase.from('shops').select('id,name,city,country,currency').limit(1).maybeSingle(),
        ),
        SHOP_TIMEOUT_MS,
      )
      if (result.error) failed = true
      else data = result.data
    } catch {
      failed = true
    }
    if (seq !== loadSeq.current) return
    const cached = cachedShop<Shop>(userId)
    if (data) void rememberShop(userId, data)
    const next: Gate = data
      ? { status: 'ready', userId, shop: data, confirmed: true }
      : cached
        ? // Failure, or an empty answer although this account had a shop here: keep the copy.
          { status: 'ready', userId, shop: cached, confirmed: false }
        : failed
          ? { status: 'error', userId, message: SHOP_LOAD_FAILED }
          : { status: 'no-shop', userId }
    // Signed out while the request was running: stay signed out.
    setGate((current) => (current.status === 'signed-out' ? current : next))
  }, [])

  /** Applies the session reported by supabase-js (null: none, or not refreshable right now). */
  const applySession = useCallback(
    (event: AuthChangeEvent | 'RETRY', session: Session | null) => {
      if (session) {
        const userId = session.user.id,
          current = gateRef.current
        // Hourly token refresh of a confirmed shop: nothing to reload.
        if (
          event === 'TOKEN_REFRESHED' &&
          current.status === 'ready' &&
          current.userId === userId &&
          current.confirmed
        )
          return
        if (!(current.status === 'ready' && current.userId === userId)) {
          const cached = cachedShop<Shop>(userId)
          setGate(
            cached
              ? { status: 'ready', userId, shop: cached, confirmed: false }
              : { status: 'loading' },
          )
        }
        void loadShop(userId)
        return
      }
      const userId = event === 'SIGNED_OUT' ? null : persistedUserId()
      loadSeq.current++
      if (!userId) {
        if (event === 'SIGNED_OUT') void clearPrivateCaches()
        setGate({ status: 'signed-out' })
        return
      }
      // Session kept on the device but its token cannot be refreshed now (offline).
      const cached = cachedShop<Shop>(userId)
      setGate(
        cached
          ? { status: 'ready', userId, shop: cached, confirmed: false }
          : {
              status: 'error',
              userId,
              message: navigator.onLine ? SHOP_LOAD_FAILED : OFFLINE_FIRST_LAUNCH,
            },
      )
    },
    [loadShop],
  )

  /** Refreshes the session (supabase-js refreshes an expired token) and reloads the shop. */
  const retry = useCallback(async () => {
    const { data } = await supabase.auth.getSession().catch(() => ({ data: { session: null } }))
    applySession('RETRY', data.session)
  }, [applySession])

  useEffect(() => {
    let active = true
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, session) => {
      // Deferred: calling supabase from inside this callback would wait on its own auth lock.
      setTimeout(() => {
        if (active) applySession(event, session)
      }, 0)
    })
    // Back online or in the foreground with an unconfirmed shop: refresh the session and reload it.
    const reconnect = () => {
      const current = gateRef.current
      const pending =
        (current.status === 'ready' && !current.confirmed) || current.status === 'error'
      if (pending && navigator.onLine && document.visibilityState === 'visible') void retry()
    }
    window.addEventListener('online', reconnect)
    document.addEventListener('visibilitychange', reconnect)
    return () => {
      active = false
      subscription.unsubscribe()
      window.removeEventListener('online', reconnect)
      document.removeEventListener('visibilitychange', reconnect)
    }
  }, [applySession, retry])

  const signOut = useCallback(async () => {
    try {
      const { error } = await withTimeout(
        supabase.auth.signOut(navigator.onLine ? undefined : { scope: 'local' }),
        5000,
      )
      if (!error) return
    } catch {
      // handled below
    }
    // Offline with an expired token, supabase-js first tries to refresh it and gives up without
    // signing out: forget the session of this device ourselves. Queued sales are kept for this
    // account and sent after its next sign-in.
    forgetPersistedSession()
    setSyncUser(null)
    void clearPrivateCaches()
    setGate({ status: 'signed-out' })
  }, [])

  if (gate.status === 'loading')
    return (
      <div className="authshell">
        <div className="authcard">
          <h1>COVI</h1>
          <p>Chargement de votre commerce…</p>
        </div>
      </div>
    )
  if (gate.status === 'signed-out')
    return (
      <LoginForm
        mode={mode}
        onModeChange={setMode}
        showPassword={showPassword}
        onShowPasswordChange={setShowPassword}
        message={message}
        onMessage={setMessage}
        onSimulation={onSimulation}
      />
    )
  if (gate.status === 'error')
    return (
      <div className="authshell">
        <div className="authcard" role="alert">
          <h1>COVI</h1>
          <p>{gate.message}</p>
          <button
            className="primary"
            type="button"
            onClick={() => {
              setGate({ status: 'loading' })
              void retry()
            }}
          >
            Réessayer
          </button>
          <button className="authswitch" type="button" onClick={signOut}>
            Se déconnecter
          </button>
        </div>
      </div>
    )
  if (gate.status === 'no-shop') {
    const userId = gate.userId
    return (
      <CreateShopForm
        message={message}
        onMessage={setMessage}
        onCreated={(shop) => {
          void rememberShop(userId, shop)
          setGate({ status: 'ready', userId, shop, confirmed: true })
        }}
      />
    )
  }
  const { userId } = gate
  return (
    <>
      {children(gate.shop, signOut, (shop) => {
        void rememberShop(userId, shop)
        setGate({ status: 'ready', userId, shop, confirmed: true })
      })}
    </>
  )
}
