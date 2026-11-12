import { useEffect, useRef, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { myAccountDeletion, type AccountDeletion } from '../../lib/account'
import { supabase } from '../../lib/supabase'
import { DeletionPendingScreen } from '../account/DeletionPendingScreen'
import { listenForDesktopOAuth } from '../../lib/desktopAuth'
import { listenForNativeOAuth } from '../../lib/nativeOAuth'
import { clearCounterMode } from '../../lib/counterMode'
import { closeTillSession, myMemberShops, type MemberShop } from '../../lib/team'
import { closeSharedCashierTill } from '../../lib/sharedCashiers'
import { clearTillSession, peekTillSession } from '../../lib/tillSession'
import type { Shop } from '../../lib/types'
import { CashierApp } from '../team/CashierApp'
import { myRestaurantStaffSpaces, type RestaurantStaffSpace } from '../../lib/restaurantStaff'
import { RestaurantStaffJoinPage } from '../restaurant/RestaurantStaffJoinPage'
import { RestaurantStaffApp } from '../restaurant/RestaurantStaffApp'
import { salonApi, type SalonSpace } from '../../lib/salon'
import { SalonStaffApp } from '../salon/SalonStaffApp'
import { SalonStaffJoinPage } from '../salon/SalonStaffJoinPage'
import { JoinPage } from '../team/JoinPage'
import { SpaceChooser, type SpaceChoice } from '../team/SpaceChooser'
import { CreateShopForm } from './CreateShopForm'
import { AddEstablishmentForm } from './AddEstablishmentForm'
import { LoginForm, type AuthMode } from './LoginForm'
import { BrandMark } from '../../components/Brand'

/** Signs out after closing the till session of a shared device (best effort, never blocks). */
async function signOutEverywhere() {
  const till = peekTillSession()
  clearTillSession()
  if (till) {
    const close = till.cashierProfileId ? closeSharedCashierTill : closeTillSession
    await close(till.shopId, till.token).catch(() => false)
  }
  const { error } = await supabase.auth.signOut()
  if (error) throw error
}

/**
 * Renders the sign-in screens until a session and its shop are available, then hands the shop to
 * `children`. A cashier (member of someone else's shop, my_member_shops) gets the cashier space;
 * an account that is both owner and cashier chooses first.
 */
export function AuthGate({
  children,
  onSimulation,
}: {
  children: (
    shop: Shop,
    signOut: () => Promise<void>,
    updateShop: (shop: Shop) => void,
    /** The signed-in account of the validated session (sales and carts are tied to it). */
    userId: string,
    addEstablishment: () => void,
    ownedEstablishments?: Shop[],
    selectEstablishment?: (shopId: string) => void,
  ) => ReactNode
  onSimulation: () => void
}) {
  const [session, setSession] = useState<Session | null>(null)
  const [shop, setShop] = useState<Shop | null>(null)
  const [loading, setLoading] = useState(true)
  // Development-only visual QA entrypoints. Never enabled in production builds.
  const previewMode = import.meta.env.DEV && typeof window !== 'undefined'
    ? new URLSearchParams(window.location.search).get('covi-ios-preview')
    : null
  const [mode, setMode] = useState<AuthMode>(previewMode === 'signup' ? 'signup' : 'login')
  const [showWelcome, setShowWelcome] = useState(previewMode !== 'login' && previewMode !== 'signup')
  const [message, setMessage] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [memberships, setMemberships] = useState<MemberShop[]>([])
  const [restaurantSpaces, setRestaurantSpaces] = useState<RestaurantStaffSpace[]>([])
  const [salonSpaces, setSalonSpaces] = useState<SalonSpace[]>([])
  // Suppression du compte programmée : seul l'écran d'annulation reste accessible.
  const [deletion, setDeletion] = useState<AccountDeletion>({ pending: false })
  const [choice, setChoice] = useState<SpaceChoice | null>(null)
  const [joining, setJoining] = useState(false)
  const [joiningRestaurant, setJoiningRestaurant] = useState(false)
  const [joiningSalon, setJoiningSalon] = useState(false)
  const [addingEstablishment, setAddingEstablishment] = useState(false)
  const [ownedShops, setOwnedShops] = useState<Shop[]>([])
  const [membershipsVersion, setMembershipsVersion] = useState(0)
  const loadedFor = useRef<string | null>(null)
  const userId = session?.user.id ?? null
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
  useEffect(() => {
    let active = true
    let dispose = () => undefined
    void listenForNativeOAuth(setMessage).then((unlisten) => {
      if (active) dispose = unlisten
      else unlisten()
    }).catch(() => setMessage('Impossible d’initialiser la connexion iOS.'))
    return () => { active = false; dispose() }
  }, [])
  useEffect(() => {
    supabase.auth.getSession().then(async ({ data }) => {
      if (document.documentElement.dataset.coviPlatform === 'ios' && localStorage.getItem('covi-ios-remember-session') === 'false' && data.session) {
        await supabase.auth.signOut()
        setSession(null)
      } else setSession(data.session)
    })
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, s) => {
      // The till token of a shared device never outlives the owner's session. The counter mode
      // ends too: coming back asks for the account password.
      if (event === 'SIGNED_OUT') {
        clearTillSession()
        clearCounterMode()
      }
      setSession(s)
    })
    return () => subscription.unsubscribe()
  }, [])
  useEffect(() => {
    if (!userId) {
      loadedFor.current = null
      // eslint-disable-next-line react-hooks/set-state-in-effect -- reset when signed out (unchanged behaviour)
      setShop(null)
      setMemberships([])
      setRestaurantSpaces([])
      setSalonSpaces([])
      setOwnedShops([])
      setAddingEstablishment(false)
      setChoice(null)
      setJoining(false)
      setJoiningRestaurant(false)
      setJoiningSalon(false)
      setLoading(false)
      return
    }
    // Loading screen only for a new account: a token refresh or a membership reload keeps the
    // open space mounted (a cashier is not sent back to the PIN screen).
    if (loadedFor.current !== userId) setLoading(true)
    void Promise.all([
      // Owned shop only (members may read other rows later): same query as before the team.
      supabase
        .from('shops')
        .select('id,name,city,country,currency,business_kind')
        .eq('owner_id', userId)
        .order('created_at', { ascending: true }),
      // Cashier memberships. A failure (old server, network) leaves the owner flow unchanged.
      myMemberShops().catch(() => [] as MemberShop[]),
      myRestaurantStaffSpaces().catch(() => [] as RestaurantStaffSpace[]),
      // Salon : un serveur pas encore à jour (fonction absente) ne bloque rien.
      salonApi
        .mySpaces()
        .then((v) => (Array.isArray(v) ? v : []))
        .catch(() => [] as SalonSpace[]),
      // A failure (server not migrated yet, network) never blocks the application.
      myAccountDeletion().catch((): AccountDeletion => ({ pending: false })),
    ]).then(([{ data, error }, members, spaces, salons, pendingDeletion]) => {
      setDeletion(pendingDeletion)
      if (error)
        setMessage('Impossible de charger votre commerce. Vérifiez votre connexion puis réessayez.')
      const shops = Array.isArray(data) ? data : []
      setOwnedShops(shops)
      setShop(shops[0] ?? null)
      setMemberships(members)
      setRestaurantSpaces(spaces)
      setSalonSpaces(salons)
      setLoading(false)
      loadedFor.current = userId
    })
  }, [userId, membershipsVersion])
  const reloadMemberships = () => setMembershipsVersion((n) => n + 1)
  const isIOSApp =
    typeof document !== 'undefined' && document.documentElement.dataset.coviPlatform === 'ios'
  if (loading)
    return (
      <div className="authshell" role="status">
        <div className="authcard">
          <h1>COVI</h1>
          <p>Ouverture de la boutique…</p>
        </div>
      </div>
    )
  const hasLinkedSpace =
    shop !== null || memberships.length > 0 || restaurantSpaces.length > 0 || salonSpaces.length > 0
  if (isIOSApp && showWelcome && (!session || !hasLinkedSpace))
    return (
      <div className="auth auth--welcome">
        <main className="auth__welcome" aria-labelledby="welcome-title">
          <div className="auth__welcome-brand">
            <BrandMark size={64} />
            <div className="auth__welcome-brand-label"><strong>COVI</strong><span>COMMERCE &amp; VIE</span></div>
          </div>
          <h1 id="welcome-title">Gérez votre commerce <em>simplement.</em></h1>
          <p>Ventes, stock, clients et équipe, tout au même endroit.</p>
          <div className="auth__welcome-highlights" aria-label="Activités COVI">
            <span><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M5 8h14l1 12H4L5 8Z"/><path d="M9 9V6a3 3 0 0 1 6 0v3"/></svg><strong>Boutique</strong></span><span><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M4 3v7a3 3 0 0 0 6 0V3M7 3v18M16 3c-2 3-3 6-3 10h5V3M18 13v8"/></svg><strong>Restaurant</strong></span><span><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><circle cx="6" cy="17" r="3"/><circle cx="18" cy="17" r="3"/><path d="M8.5 15 19 4M15.5 15 5 4"/></svg><strong>Salon</strong></span>
          </div>
          <div className="auth__welcome-photo">
            <img src="/covi-commercante.jpg" alt="Commerçante utilisant sa tablette dans sa boutique" />
          </div>
          <div className="auth__welcome-actions" aria-label="Accès COVI">
            <button
              type="button"
              className="button button--primary button--lg button--block"
              data-auth-entry="signup"
              onClick={() => {
                setMode('signup')
                setShowWelcome(false)
              }}
            >
              Commencer
            </button>
            <button
              type="button"
              className="button button--secondary button--lg button--block"
              data-auth-entry="login"
              onClick={() => {
                setMode('login')
                setShowWelcome(false)
              }}
            >
              Se connecter
            </button>
          </div>
        </main>
      </div>
    )
  if (!session)
    return (
      <LoginForm
        mode={mode}
        onModeChange={setMode}
        showPassword={showPassword}
        onShowPasswordChange={setShowPassword}
        message={message}
        onMessage={setMessage}
        onSimulation={onSimulation}
        onAuthSuccess={() => {
          void supabase.auth.getSession().then(({ data }) => setSession(data.session))
        }}
        onBackToWelcome={() => setShowWelcome(true)}
      />
    )
  if (deletion.pending)
    return (
      <DeletionPendingScreen
        purgeAfter={deletion.purgeAfter}
        onCancelled={() => setDeletion({ pending: false })}
        onSignOut={() => void signOutEverywhere()}
      />
    )
  if (joiningRestaurant)
    return (
      <RestaurantStaffJoinPage
        onBack={() => setJoiningRestaurant(false)}
        onJoined={(joinedShopId) => {
          setJoiningRestaurant(false)
          setChoice({ kind: 'restaurant-staff', shopId: joinedShopId })
          reloadMemberships()
        }}
      />
    )
  if (joiningSalon)
    return (
      <SalonStaffJoinPage
        onBack={() => setJoiningSalon(false)}
        onJoined={(joinedShopId) => {
          setJoiningSalon(false)
          setChoice({ kind: 'salon-staff', shopId: joinedShopId })
          reloadMemberships()
        }}
      />
    )
  if (joining)
    return (
      <JoinPage
        onBack={() => setJoining(false)}
        onJoined={(joined) => {
          setJoining(false)
          setChoice({ kind: 'cashier', shopId: joined.shop_id })
          reloadMemberships()
        }}
      />
    )
  // Which space: owner only (unchanged), cashier only, or a choice when both exist.
  const cashierOf = (shopId: string) => memberships.find((m) => m.shop_id === shopId) ?? null
  const restaurantOf = (shopId: string) =>
    restaurantSpaces.find((m) => m.shop_id === shopId) ?? null
  const salonOf = (shopId: string) => salonSpaces.find((m) => m.shop_id === shopId) ?? null
  let space: SpaceChoice | null = choice
  if (space?.kind === 'cashier' && !cashierOf(space.shopId)) space = null
  if (space?.kind === 'restaurant-staff' && !restaurantOf(space.shopId)) space = null
  if (space?.kind === 'salon-staff' && !salonOf(space.shopId)) space = null
  if (space?.kind === 'owner' && !shop) space = null
  if (!space) {
    const others = memberships.length + restaurantSpaces.length + salonSpaces.length
    if (shop && others === 0) space = { kind: 'owner' }
    else if (!shop && others === 1 && restaurantSpaces.length === 1)
      space = { kind: 'restaurant-staff', shopId: restaurantSpaces[0].shop_id }
    else if (!shop && others === 1 && memberships.length === 1)
      space = { kind: 'cashier', shopId: memberships[0].shop_id }
    else if (!shop && others === 1 && salonSpaces.length === 1)
      space = { kind: 'salon-staff', shopId: salonSpaces[0].shop_id }
  }
  if (addingEstablishment && session)
    return (
      <AddEstablishmentForm
        count={ownedShops.length}
        onCancel={() => setAddingEstablishment(false)}
        onCreated={(created) => {
          setOwnedShops((current) => [...current, created])
          setShop(created)
          setAddingEstablishment(false)
        }}
      />
    )
  if (!space) {
    if (
      !shop &&
      memberships.length === 0 &&
      restaurantSpaces.length === 0 &&
      salonSpaces.length === 0
    )
      return (
        <CreateShopForm
          message={message}
          onMessage={setMessage}
          onCreated={setShop}
          onJoin={() => setJoining(true)}
          onRestaurantJoin={() => setJoiningRestaurant(true)}
          onSalonJoin={() => setJoiningSalon(true)}
          accountMetadata={session.user.user_metadata}
        />
      )
    return (
      <SpaceChooser
        shop={shop}
        memberships={memberships}
        restaurantSpaces={restaurantSpaces}
        salonSpaces={salonSpaces}
        onRestaurantJoin={() => setJoiningRestaurant(true)}
        onSalonJoin={() => setJoiningSalon(true)}
        onChoose={setChoice}
        onJoin={() => setJoining(true)}
        onSignOut={() => void signOutEverywhere()}
      />
    )
  }
  if (space.kind === 'salon-staff') {
    const salonSpace = salonOf(space.shopId)!
    return (
      <SalonStaffApp
        key={salonSpace.shop_id}
        space={salonSpace}
        signOut={signOutEverywhere}
        onLostAccess={reloadMemberships}
        onSwitch={
          shop || memberships.length > 0 || restaurantSpaces.length > 0 || salonSpaces.length > 1
            ? () => {
                setChoice(null)
                reloadMemberships()
              }
            : undefined
        }
      />
    )
  }
  if (space.kind === 'restaurant-staff') {
    const restaurantSpace = restaurantOf(space.shopId)!
    return (
      <RestaurantStaffApp
        key={restaurantSpace.shop_id}
        space={restaurantSpace}
        signOut={signOutEverywhere}
        onLostAccess={reloadMemberships}
        onSwitch={
          shop || memberships.length > 0 || restaurantSpaces.length > 1
            ? () => {
                setChoice(null)
                reloadMemberships()
              }
            : undefined
        }
      />
    )
  }
  if (space.kind === 'cashier') {
    const membership = cashierOf(space.shopId)!
    return (
      <CashierApp
        key={membership.member_id}
        userId={session.user.id}
        membership={membership}
        signOut={signOutEverywhere}
        onLostAccess={reloadMemberships}
        onSwitchSpace={
          shop || memberships.length > 1
            ? () => {
                setChoice(null)
                reloadMemberships()
              }
            : undefined
        }
      />
    )
  }
  return (
    <>
      {children(
        shop!,
        signOutEverywhere,
        (updatedShop) => {
          setShop(updatedShop)
          setOwnedShops((current) =>
            current.map((establishment) =>
              establishment.id === updatedShop.id ? updatedShop : establishment,
            ),
          )
        },
        session.user.id,
        () => {
          if (ownedShops.length < 3) setAddingEstablishment(true)
        },
        ownedShops,
        (shopId) => {
          const next = ownedShops.find((establishment) => establishment.id === shopId)
          if (next) setShop(next)
        },
      )}
    </>
  )
}
