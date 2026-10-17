import { useEffect, useRef, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { myAccountDeletion, type AccountDeletion } from '../../lib/account'
import { supabase } from '../../lib/supabase'
import { DeletionPendingScreen } from '../account/DeletionPendingScreen'
import { listenForDesktopOAuth } from '../../lib/desktopAuth'
import { clearCounterMode } from '../../lib/counterMode'
import { closeTillSession, myMemberShops, type MemberShop } from '../../lib/team'
import { closeSharedCashierTill } from '../../lib/sharedCashiers'
import { clearTillSession, peekTillSession } from '../../lib/tillSession'
import type { Shop } from '../../lib/types'
import { CashierApp } from '../team/CashierApp'
import { myRestaurantStaffSpaces, type RestaurantStaffSpace } from '../../lib/restaurantStaff'
import { RestaurantStaffJoinPage } from '../restaurant/RestaurantStaffJoinPage'
import { RestaurantStaffApp } from '../restaurant/RestaurantStaffApp'
import { JoinPage } from '../team/JoinPage'
import { SpaceChooser, type SpaceChoice } from '../team/SpaceChooser'
import { CreateShopForm } from './CreateShopForm'
import { LoginForm, type AuthMode } from './LoginForm'

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
  ) => ReactNode
  onSimulation: () => void
}) {
  const [session, setSession] = useState<Session | null>(null)
  const [shop, setShop] = useState<Shop | null>(null)
  const [loading, setLoading] = useState(true)
  const [mode, setMode] = useState<AuthMode>('login')
  const [message, setMessage] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [memberships, setMemberships] = useState<MemberShop[]>([])
  const [restaurantSpaces, setRestaurantSpaces] = useState<RestaurantStaffSpace[]>([])
  // Suppression du compte programmée : seul l'écran d'annulation reste accessible.
  const [deletion, setDeletion] = useState<AccountDeletion>({ pending: false })
  const [choice, setChoice] = useState<SpaceChoice | null>(null)
  const [joining, setJoining] = useState(false)
  const [joiningRestaurant, setJoiningRestaurant] = useState(false)
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
    supabase.auth.getSession().then(({ data }) => setSession(data.session))
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
      setChoice(null)
      setJoining(false)
      setJoiningRestaurant(false)
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
        .limit(1)
        .maybeSingle(),
      // Cashier memberships. A failure (old server, network) leaves the owner flow unchanged.
      myMemberShops().catch(() => [] as MemberShop[]),
      myRestaurantStaffSpaces().catch(() => [] as RestaurantStaffSpace[]),
      // A failure (server not migrated yet, network) never blocks the application.
      myAccountDeletion().catch((): AccountDeletion => ({ pending: false })),
    ]).then(([{ data, error }, members, spaces, pendingDeletion]) => {
      setDeletion(pendingDeletion)
      if (error)
        setMessage('Impossible de charger votre commerce. Vérifiez votre connexion puis réessayez.')
      setShop(data)
      setMemberships(members)
      setRestaurantSpaces(spaces)
      setLoading(false)
      loadedFor.current = userId
    })
  }, [userId, membershipsVersion])
  const reloadMemberships = () => setMembershipsVersion((n) => n + 1)
  if (loading)
    return (
      <div className="authshell" role="status">
        <div className="authcard">
          <h1>COVI</h1>
          <p>Ouverture de la boutique…</p>
        </div>
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
  const restaurantOf = (shopId: string) => restaurantSpaces.find((m) => m.shop_id === shopId) ?? null
  let space: SpaceChoice | null = choice
  if (space?.kind === 'cashier' && !cashierOf(space.shopId)) space = null
  if (space?.kind === 'restaurant-staff' && !restaurantOf(space.shopId)) space = null
  if (space?.kind === 'owner' && !shop) space = null
  if (!space) {
    if (shop && memberships.length === 0 && restaurantSpaces.length === 0)
      space = { kind: 'owner' }
    else if (!shop && memberships.length === 0 && restaurantSpaces.length === 1)
      space = { kind: 'restaurant-staff', shopId: restaurantSpaces[0].shop_id }
    else if (!shop && memberships.length === 1 && restaurantSpaces.length === 0)
      space = { kind: 'cashier', shopId: memberships[0].shop_id }
  }
  if (!space) {
    if (!shop && memberships.length === 0 && restaurantSpaces.length === 0)
      return (
        <CreateShopForm
          message={message}
          onMessage={setMessage}
          onCreated={setShop}
          onJoin={() => setJoining(true)}
          onRestaurantJoin={() => setJoiningRestaurant(true)}
        />
      )
    return (
      <SpaceChooser
        shop={shop}
        memberships={memberships}
        restaurantSpaces={restaurantSpaces}
        onRestaurantJoin={() => setJoiningRestaurant(true)}
        onChoose={setChoice}
        onJoin={() => setJoining(true)}
        onSignOut={() => void signOutEverywhere()}
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
        onSwitch={shop || memberships.length > 0 || restaurantSpaces.length > 1
          ? () => { setChoice(null); reloadMemberships() }
          : undefined}
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
  return <>{children(shop!, signOutEverywhere, setShop, session.user.id)}</>
}
