import { useEffect, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../../lib/supabase'
import { listenForDesktopOAuth } from '../../lib/desktopAuth'
import type { Shop } from '../../lib/types'
import { CreateShopForm } from './CreateShopForm'
import { categoryCheckoutEnabled } from '../../lib/checkoutFeatureFlag'
import { myCashierShops, type CashierMembership } from '../../lib/cashierAccounts'
import { CashierWorkspace } from '../checkout/CashierWorkspace'
import { CashierJoinPage } from '../checkout/CashierJoinPage'
import { LoginForm, type AuthMode } from './LoginForm'

/**
 * Renders the sign-in screens until a session and its shop are available, then hands the shop to
 * `children`.
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
  const [session, setSession] = useState<Session | null>(null)
  const [shop, setShop] = useState<Shop | null>(null)
  const [cashierShops, setCashierShops] = useState<CashierMembership[]>([])
  const [cashierRefresh, setCashierRefresh] = useState(0)
  const [wantShop, setWantShop] = useState(false)
  const [loading, setLoading] = useState(true)
  const [mode, setMode] = useState<AuthMode>('login')
  const [message, setMessage] = useState('')
  const [showPassword, setShowPassword] = useState(false)
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
    } = supabase.auth.onAuthStateChange((_e, s) => setSession(s))
    return () => subscription.unsubscribe()
  }, [])
  useEffect(() => {
    if (!session) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- reset when signed out (unchanged behaviour)
      setShop(null)
      setCashierShops([])
      setLoading(false)
      return
    }
    setLoading(true)
    let active = true
    void (async () => {
      const { data, error } = await supabase
        .from('shops')
        .select('id,name,city,country,currency')
        .limit(1)
        .maybeSingle()
      if (!active) return
      if (error) {
        setMessage('Impossible de charger votre commerce. Vérifiez votre connexion puis réessayez.')
      }
      setShop(data)
      if (categoryCheckoutEnabled && !data) {
        try {
          const memberships = await myCashierShops()
          if (active) setCashierShops(memberships)
        } catch (reason) {
          if (active)
            setMessage(
              reason instanceof Error
                ? reason.message
                : 'La gestion des caissiers est indisponible.',
            )
        }
      } else {
        setCashierShops([])
      }
      if (active) setLoading(false)
    })()
    return () => {
      active = false
    }
  }, [session, cashierRefresh])
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
  if (!shop) {
    if (categoryCheckoutEnabled && cashierShops.length) {
      return (
        <CashierWorkspace
          shops={cashierShops}
          onRefresh={() => setCashierRefresh((value) => value + 1)}
          signOut={async () => {
            await supabase.auth.signOut()
          }}
        />
      )
    }
    if (categoryCheckoutEnabled && !wantShop) {
      return (
        <CashierJoinPage
          onJoined={() => setCashierRefresh((value) => value + 1)}
          onCreateShop={() => setWantShop(true)}
          signOut={async () => {
            await supabase.auth.signOut()
          }}
        />
      )
    }
    return <CreateShopForm message={message} onMessage={setMessage} onCreated={setShop} />
  }
  return (
    <>
      {children(
        shop,
        async () => {
          await supabase.auth.signOut()
        },
        setShop,
      )}
    </>
  )
}
