import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { Button, Notice } from '../../components/ui'
import {
  chooseShop,
  forgetActiveShop,
  readActiveShop,
  readActiveShopCopy,
  rememberActiveShop,
} from '../../lib/activeShop'
import { rejectedSales } from '../../lib/offline'
import { supabase } from '../../lib/supabase'
import { listenForDesktopOAuth } from '../../lib/desktopAuth'
import {
  addShopBlockedReason,
  isSubscriptionInactive,
  loadSubscriptionAccess,
  OPEN_ACCESS,
  onSubscriptionInactive,
  type SubscriptionAccess,
} from '../../lib/subscription'
import type { Shop } from '../../lib/types'
import { AuthPage } from './AuthPage'
import { CreateShopForm } from './CreateShopForm'
import { LoginForm, type AuthMode } from './LoginForm'
import { ShopPicker } from './ShopPicker'

/** What the shell needs to know about the account beyond the open shop. */
export type ShopAccount = {
  /** Shops of the account (1 when the list could not be loaded: only the open one is known). */
  shopCount: number
  /** Back to « Choisir une boutique » (only with several shops). */
  switchShop?: () => void
  /** « Ajouter une boutique »: `create_my_shop`, within the subscription quota (needs the list). */
  addShop?: () => void
  /** Why adding a shop is not possible (suspended, not active, quota reached): button disabled. */
  addShopBlocked?: string
  /** Subscription suspended or over: data can be read, nothing can be written. */
  readOnly: boolean
  /**
   * The subscription could not be checked (covi_my_subscription_state failed): only said, nothing
   * blocked, never shown as active or suspended. Gone as soon as a check succeeds.
   */
  subscriptionUnverified?: boolean
}

/** While the subscription is unverified, it is asked again at this pace (and when back online). */
const RECHECK_MS = 60_000

/** A shop list request that never answers (weak network) is treated as a failure. */
const SHOPS_TIMEOUT_MS = 12_000
const SHOP_COLUMNS = 'id,name,city,country,currency'

const LOAD_FAILED =
  'Impossible de charger vos boutiques : le réseau ne répond pas. Vérifiez la connexion puis réessayez.'

type Shops =
  /** Not loaded yet for this user. */
  | { status: 'idle' }
  /** The list returned by the database (RLS: this account's shops only), oldest first. */
  | { status: 'loaded'; userId: string; list: Shop[] }
  /** The request failed or timed out: NOT the same as « no shop ». */
  | { status: 'failed'; userId: string }

function fetchShops() {
  return Promise.race([
    Promise.resolve(
      supabase
        .from('shops')
        .select(SHOP_COLUMNS)
        .order('created_at', { ascending: true })
        .order('id', { ascending: true }),
    ),
    new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error('timeout')), SHOPS_TIMEOUT_MS),
    ),
  ])
}

/**
 * Renders the sign-in screens until a session and its shop are available, then hands the shop to
 * `children`. An account may hold several shops (multi-shop subscription): the one opened last on
 * this device is reopened (lib/activeShop.ts), otherwise the owner chooses.
 */
export function AuthGate({
  children,
  onSimulation,
}: {
  children: (
    shop: Shop,
    signOut: () => Promise<void>,
    updateShop: (shop: Shop) => void,
    account: ShopAccount,
  ) => ReactNode
  onSimulation: () => void
}) {
  const [session, setSession] = useState<Session | null>(null)
  const [sessionKnown, setSessionKnown] = useState(false)
  const [shops, setShops] = useState<Shops>({ status: 'idle' })
  // The open shop, with the account it belongs to: never shown to another account.
  const [active, setActive] = useState<{ userId: string; shop: Shop } | null>(null)
  const [adding, setAdding] = useState(false)
  const [access, setAccess] = useState<SubscriptionAccess>(OPEN_ACCESS)
  const [mode, setMode] = useState<AuthMode>('login')
  const [message, setMessage] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const loadSeq = useRef(0)
  const userId = session?.user.id ?? null

  useEffect(() => {
    let dispose: () => void = () => {}
    let alive = true
    void listenForDesktopOAuth((message) => setMessage(message))
      .then((unlisten) => {
        if (alive) dispose = unlisten
        else unlisten()
      })
      .catch(() => setMessage('Impossible d’initialiser le retour de connexion.'))
    return () => {
      alive = false
      dispose()
    }
  }, [])
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setSessionKnown(true)
    })
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_e, s) => {
      setSession(s)
      setSessionKnown(true)
    })
    return () => subscription.unsubscribe()
  }, [])

  // A write refused for the subscription (P0001), here or at the sync of an offline sale: the
  // server is the authority, the shop switches to read only.
  useEffect(() => {
    const readOnly = () => setAccess((a) => ({ ...a, readOnly: true }))
    const since = new Date().toISOString()
    // An offline sale refused at its sync (lib/offline.ts keeps it with its reason).
    const checkSync = () => {
      if (rejectedSales().some((x) => x.rejectedAt >= since && isSubscriptionInactive(x.reason)))
        readOnly()
    }
    window.addEventListener('covi-sync', checkSync)
    const stop = onSubscriptionInactive(readOnly)
    return () => {
      window.removeEventListener('covi-sync', checkSync)
      stop()
    }
  }, [])

  const loadShops = useCallback(async (uid: string) => {
    const seq = ++loadSeq.current
    let list: Shop[] | null = null
    try {
      const { data, error } = await fetchShops()
      if (!error && data) list = data
    } catch {
      list = null
    }
    if (seq !== loadSeq.current) return
    if (!list) {
      // No network: keep the shop already open for this account, or this account's own copy
      // of its active shop on this device. Never another shop, never « create your shop ».
      setShops({ status: 'failed', userId: uid })
      setActive((current) => {
        if (current?.userId === uid) return current
        const copy = readActiveShopCopy<Shop>(uid)
        return copy ? { userId: uid, shop: copy } : null
      })
      return
    }
    const remembered = readActiveShop(uid)
    // The preference is not an authorization: an id that is not in the list is dropped.
    if (remembered && !list.some((s) => s.id === remembered)) forgetActiveShop(uid)
    const choice = chooseShop(list, remembered)
    setShops({ status: 'loaded', userId: uid, list })
    if (choice.kind === 'open') {
      rememberActiveShop(uid, choice.shop)
      setActive({ userId: uid, shop: choice.shop })
    } else setActive(null)
  }, [])

  useEffect(() => {
    if (!userId) {
      loadSeq.current++
      // eslint-disable-next-line react-hooks/set-state-in-effect -- reset when signed out
      setShops({ status: 'idle' })
      setActive(null)
      setAdding(false)
      setAccess(OPEN_ACCESS)
      return
    }
    // Another account than the one shown: nothing of the previous one stays on screen.
    setShops({ status: 'idle' })
    setActive((current) => (current?.userId === userId ? current : null))
    setAccess(OPEN_ACCESS)
    void loadShops(userId)
    let alive = true
    void loadSubscriptionAccess(userId).then((a) => {
      if (alive) setAccess((current) => ({ ...a, readOnly: a.readOnly || current.readOnly }))
    })
    return () => {
      alive = false
    }
  }, [userId, loadShops])

  // Unverified (network, server error): asked again until a check answers. The read-only state
  // confirmed by the server (P0001) is kept; nothing is written, the offline queue is not touched.
  const unverified = access.unverified === true
  useEffect(() => {
    if (!userId || !unverified) return
    let alive = true
    let asking = false
    const recheck = () => {
      if (asking || document.visibilityState === 'hidden') return
      asking = true
      void loadSubscriptionAccess(userId)
        .then((a) => {
          if (alive) setAccess((current) => ({ ...a, readOnly: a.readOnly || current.readOnly }))
        })
        .finally(() => {
          asking = false
        })
    }
    const timer = window.setInterval(recheck, RECHECK_MS)
    window.addEventListener('online', recheck)
    document.addEventListener('visibilitychange', recheck)
    return () => {
      alive = false
      window.clearInterval(timer)
      window.removeEventListener('online', recheck)
      document.removeEventListener('visibilitychange', recheck)
    }
  }, [userId, unverified])

  const signOut = async () => {
    await supabase.auth.signOut()
  }

  if (!sessionKnown)
    return (
      <div className="authshell" role="status">
        <div className="authcard">
          <h1>COVI</h1>
          <p>Ouverture de la boutique…</p>
        </div>
      </div>
    )
  if (!session || !userId)
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

  const list = shops.status === 'loaded' && shops.userId === userId ? shops.list : null
  const open = (shop: Shop) => {
    rememberActiveShop(userId, shop)
    setActive({ userId, shop })
    setAdding(false)
  }
  // Known before trying (covi_my_subscription_state); the server still refuses on its own.
  const addBlocked = list ? addShopBlockedReason(access, list.length) : null
  const startAdding =
    list && !addBlocked
      ? () => {
          setMessage('')
          setAdding(true)
        }
      : undefined
  // A new shop changes what the account may still do (quota): asked again.
  const refreshAccess = () =>
    void loadSubscriptionAccess(userId).then((a) =>
      setAccess((current) => ({ ...a, readOnly: a.readOnly || current.readOnly })),
    )

  if (adding && list && !addBlocked)
    return (
      <CreateShopForm
        message={message}
        onMessage={setMessage}
        adding={{
          existingIds: list.map((s) => s.id),
          shopLimit: access.shopLimit,
          onCancel: () => {
            setMessage('')
            setAdding(false)
          },
        }}
        onCreated={(shop) => {
          setMessage('')
          setShops({ status: 'loaded', userId, list: [...list, shop] })
          open(shop)
          refreshAccess()
        }}
      />
    )

  const current = active?.userId === userId ? active.shop : null
  if (current)
    return (
      <>
        {children(
          current,
          signOut,
          (shop) => {
            if (list)
              setShops({
                status: 'loaded',
                userId,
                list: list.map((s) => (s.id === shop.id ? shop : s)),
              })
            open(shop)
          },
          {
            shopCount: list?.length ?? 1,
            switchShop: list && list.length > 1 ? () => setActive(null) : undefined,
            addShop: startAdding,
            addShopBlocked: addBlocked ?? undefined,
            readOnly: access.readOnly,
            subscriptionUnverified: unverified && !access.readOnly,
          },
        )}
      </>
    )

  if (shops.status === 'failed' && shops.userId === userId)
    return (
      <AuthPage title="Vos boutiques ne s’affichent pas" lead={LOAD_FAILED}>
        <Notice title="Rien n’est perdu.">
          <p>
            Vos boutiques et leurs ventes sont gardées par COVI. Réessayez quand le réseau revient.
          </p>
        </Notice>
        <div className="shop-picker__foot">
          <Button
            variant="primary"
            onClick={() => {
              setShops({ status: 'idle' })
              void loadShops(userId)
            }}
          >
            Réessayer
          </Button>
          <button type="button" className="btn btn--ghost" onClick={() => void signOut()}>
            Se déconnecter
          </button>
        </div>
      </AuthPage>
    )

  if (!list)
    return (
      <div className="authshell" role="status">
        <div className="authcard">
          <h1>COVI</h1>
          <p>Ouverture de la boutique…</p>
        </div>
      </div>
    )

  if (list.length === 0)
    return (
      <CreateShopForm
        message={message}
        onMessage={setMessage}
        onCreated={(shop) => {
          setShops({ status: 'loaded', userId, list: [shop] })
          open(shop)
          refreshAccess()
        }}
      />
    )

  return (
    <ShopPicker
      shops={list}
      currentId={readActiveShop(userId)}
      onChoose={open}
      onAdd={startAdding}
      addBlocked={addBlocked}
      onSignOut={() => void signOut()}
    />
  )
}
