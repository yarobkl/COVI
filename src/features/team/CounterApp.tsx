import { useEffect, useState } from 'react'
import { Button, Notice } from '../../components/ui'
import { clearCounterMode } from '../../lib/counterMode'
import {
  closeTillSession,
  listShopMembers,
  openTillSession,
  pinResultMessage,
  teamErrorMessage,
  unlockTillSession,
  type TillSession,
} from '../../lib/team'
import { clearTillSession, setTillSession } from '../../lib/tillSession'
import {
  closeSharedCashierTill,
  listSharedCashiers,
  openSharedCashierTill,
  unlockSharedCashierTill,
} from '../../lib/sharedCashiers'
import type { Shop } from '../../lib/types'
import { HistoryPage } from '../history/HistoryPage'
import { SalePage } from '../sale/SalePage'
import { NetStatus } from '../sync/NetStatus'
import { useSyncState } from '../sync/useSyncState'
import { OwnerPinPrompt } from './OwnerPinScreens'
import { PinPad } from './PinPad'
import { useInactivityLock } from './useInactivityLock'
import { useTillSession } from './useTillSession'
import { OrdersInbox } from '../orders/OrdersInbox'

type Page = 'vendre' | 'commandes' | 'ventes'
/** open: selling; locked: 5 minutes without activity; pick: who holds the till; leave: owner PIN. */
type View = 'open' | 'locked' | 'pick' | 'leave'
type CashierChoice = {
  id: string
  display_name: string
  pin_set: boolean
  profile: boolean
}

/** Who holds the till: active cashiers with a PIN, then their PIN (open_till_session). */
function CashierPicker({
  shopId,
  current,
  onOpened,
  onCancel,
  onLeave,
}: {
  shopId: string
  current: TillSession | null
  onOpened: (session: TillSession) => void
  /** Back to where the picker was opened from (never unlocks a locked till). */
  onCancel?: () => void
  onLeave: () => void
}) {
  const [members, setMembers] = useState<CashierChoice[] | null>(null)
  const [loadError, setLoadError] = useState('')
  const [picked, setPicked] = useState<CashierChoice | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    let active = true
    Promise.all([listShopMembers(shopId), listSharedCashiers(shopId)]).then(
      ([registered, shared]) => {
        if (!active) return
        setMembers([
          ...shared
            .filter((m) => m.active)
            .map((m) => ({
              id: m.id,
              display_name: m.display_name,
              pin_set: m.pin_set,
              profile: true,
            })),
          ...registered
            .filter((m) => m.active)
            .map((m) => ({
              id: m.id,
              display_name: m.display_name,
              pin_set: m.pin_set,
              profile: false,
            })),
        ])
        setLoadError('')
      },
      (e) => active && setLoadError(teamErrorMessage(e)),
    )
    return () => {
      active = false
    }
  }, [shopId])

  const unlock = async (member: CashierChoice, pin: string) => {
    setBusy(true)
    setError('')
    try {
      const result = member.profile
        ? await openSharedCashierTill(shopId, member.id, pin)
        : await openTillSession(shopId, member.id, pin)
      if ('refused' in result) return setError(pinResultMessage(result.refused))
      if (current) {
        const closed = current.cashierProfileId
          ? await closeSharedCashierTill(shopId, current.token)
          : await closeTillSession(shopId, current.token)
        if (!closed) throw new Error('Impossible de fermer la caisse précédente.')
      }
      onOpened(result.session)
    } catch (e) {
      setError(teamErrorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  if (picked)
    return (
      <div className="pin-screen">
        <PinPad
          title={`Code PIN de ${picked.display_name}`}
          hint={`${picked.display_name} tape son code.`}
          error={error}
          busy={busy}
          submitLabel="Ouvrir sa caisse"
          onSubmit={(pin) => void unlock(picked, pin)}
        />
        <Button variant="ghost" onClick={() => setPicked(null)}>
          Choisir quelqu’un d’autre
        </Button>
      </div>
    )

  return (
    <div className="pin-screen counter-pick">
      <h2 className="pinpad__title">Qui tient la caisse ?</h2>
      {loadError && (
        <Notice tone="danger">
          <p>{loadError}</p>
        </Notice>
      )}
      <ul className="till-switch__list">
        {members === null && !loadError && <li className="muted">Chargement…</li>}
        {members?.map((m) => (
          <li key={m.id}>
            <Button
              variant="secondary"
              size="lg"
              block
              disabled={!m.pin_set}
              onClick={() => {
                setError('')
                setPicked(m)
              }}
            >
              {m.pin_set ? m.display_name : `${m.display_name} (code PIN à choisir)`}
            </Button>
          </li>
        ))}
      </ul>
      {onCancel && (
        <Button variant="ghost" onClick={onCancel}>
          Annuler
        </Button>
      )}
      <Button variant="ghost" onClick={onLeave}>
        Revenir au responsable
      </Button>
    </div>
  )
}

/** Till locked after 5 minutes without activity: the PIN of the cashier of the session. */
function CounterLock({
  shopId,
  session,
  onUnlocked,
  onLost,
  onChange,
  onLeave,
}: {
  shopId: string
  session: TillSession
  onUnlocked: () => void
  /** The till session is no longer valid (expired, closed, cashier deactivated). */
  onLost: () => void
  onChange: () => void
  onLeave: () => void
}) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const check = async (pin: string) => {
    setBusy(true)
    setError('')
    try {
      const result = session.cashierProfileId
        ? await unlockSharedCashierTill(shopId, session.token, pin)
        : await unlockTillSession(shopId, session.token, pin)
      if (result.status === 'ok') onUnlocked()
      else setError(pinResultMessage(result))
    } catch (e) {
      if (/till session invalid/i.test(String((e as { message?: unknown })?.message ?? '')))
        return onLost()
      setError(teamErrorMessage(e))
    } finally {
      setBusy(false)
    }
  }
  return (
    <div className="pin-screen">
      <PinPad
        title={`Caisse de ${session.displayName} verrouillée`}
        hint={`${session.displayName} tape son code PIN pour reprendre.`}
        error={error}
        busy={busy}
        submitLabel="Reprendre la caisse"
        onSubmit={(pin) => void check(pin)}
      />
      <Button variant="ghost" onClick={onChange}>
        Changer de caissier
      </Button>
      <Button variant="ghost" onClick={onLeave}>
        Revenir au responsable
      </Button>
    </div>
  )
}

/**
 * « Mode comptoir » : the owner's shared device after « Changer de caissier ». The shell behaves
 * like the cashier's: Vendre and the sales of the cashier only (or all of them when the owner
 * allowed it). Stock, Arrivages, Charges, Bilan, Ma boutique and Équipe are not rendered at all.
 * The till locks after 5 minutes without activity (cashier's PIN); only the OWNER's code, checked
 * by the server, gives the full application back.
 */
export function CounterApp({
  shop,
  userId,
  signOut,
}: {
  shop: Shop
  /** The signed-in owner (AuthGate): carts rung up at the counter are tied to this account. */
  userId: string
  signOut: () => Promise<void>
}) {
  const session = useTillSession(shop.id)
  // On refresh, a saved till must be unlocked with the cashier's PIN again.
  const [view, setView] = useState<View>('locked')
  // Where « Annuler » of the picker and the owner prompt go back to.
  const [back, setBack] = useState<'open' | 'locked'>('open')
  const [page, setPage] = useState<Page>('vendre')
  const sync = useSyncState()

  useInactivityLock(view === 'open' && Boolean(session), () => setView('locked'))

  const goPick = (from: 'open' | 'locked') => {
    setBack(from)
    setView('pick')
  }
  const goLeave = (from: 'open' | 'locked') => {
    setBack(from)
    setView('leave')
  }
  const lost = () => {
    clearTillSession()
    setBack('locked')
    setView('pick')
  }

  const screen =
    view === 'leave' ? (
      <div className="counter">
        <OwnerPinPrompt
          shopId={shop.id}
          token={session?.token}
          onLeft={() => {
            clearTillSession()
            clearCounterMode()
          }}
          onCancel={() => setView(session ? back : 'pick')}
          onSignOut={() => void signOut()}
        />
      </div>
    ) : !session || view === 'pick' ? (
      // No till session (expired, closed, page reloaded): someone must take the till first.
      <div className="counter">
        <p className="pin-screen__shop">{shop.name} · comptoir</p>
        <CashierPicker
          shopId={shop.id}
          current={session}
          onOpened={(opened) => {
            setTillSession(opened)
            setPage('vendre')
            setView('open')
          }}
          onCancel={session ? () => setView(back) : undefined}
          onLeave={() => goLeave('locked')}
        />
      </div>
    ) : view === 'locked' ? (
      <div className="counter">
        <p className="pin-screen__shop">{shop.name} · comptoir</p>
        <CounterLock
          shopId={shop.id}
          session={session}
          onUnlocked={() => setView('open')}
          onLost={lost}
          onChange={() => goPick('locked')}
          onLeave={() => goLeave('locked')}
        />
      </div>
    ) : null

  if (!session) return screen

  // The till of the current cashier stays mounted (hidden) behind the lock, the picker and the
  // owner's prompt: their cart — a cart waiting for the server's answer above all — is still
  // there when they come back. Another cashier gets a fresh till (keyed by the session).
  const ownSalesOnly = !session.canViewShopSales
  return (
    <>
      {screen}
      <div className="cashier counter" hidden={Boolean(screen)}>
        <header className="cashier__top">
          <div>
            <p className="cashier__shop">{shop.name} · comptoir</p>
            <p className="cashier__who">
              Caisse de <b>{session.displayName}</b>
            </p>
          </div>
          <NetStatus state={sync} shopId={shop.id} />
          <Button variant="secondary" onClick={() => setView('locked')}>
            Verrouiller
          </Button>
        </header>
        <nav className="tabs cashier__tabs" aria-label="Caisse">
          {(
            [
              ['vendre', 'Vendre'],
              ['commandes', 'Commandes'],
              ['ventes', ownSalesOnly ? 'Ses ventes' : 'Ventes'],
            ] as const
          ).map(([id, label]) => (
            <button
              key={id}
              type="button"
              className="tabs__tab"
              aria-current={page === id ? 'page' : undefined}
              onClick={() => setPage(id)}
            >
              {label}
            </button>
          ))}
        </nav>
        <main className="cashier__page seyes margin-rule" id="contenu">
          <div hidden={page !== 'vendre'}>
            <SalePage
              key={session.token}
              userId={userId}
              shopId={shop.id}
              shopName={shop.name}
              seller={{
                name: session.displayName,
                maxDiscountPct: session.maxDiscountPct,
                tillToken: session.token,
              }}
              paused={Boolean(screen) || page !== 'vendre'}
            />
          </div>
          {page === 'commandes' && <OrdersInbox shopId={shop.id} till={session} />}
          {page === 'ventes' && (
            <HistoryPage
              shopId={shop.id}
              mine
              // A session kept from an older version has no seller id: show nothing rather than all.
              sellerId={
                ownSalesOnly && !session.cashierProfileId ? (session.sellerId ?? '') : undefined
              }
              cashierProfileId={ownSalesOnly ? session.cashierProfileId : undefined}
            />
          )}
        </main>
        <footer className="cashier__foot">
          <Button variant="ghost" onClick={() => goPick('open')}>
            Changer de caissier
          </Button>
          <Button variant="ghost" onClick={() => goLeave('open')}>
            Revenir au responsable
          </Button>
        </footer>
      </div>
    </>
  )
}
