import { useState } from 'react'
import { Button } from '../../components/ui'
import { LegacyPage } from '../../app/LegacyPage'
import type { MemberShop } from '../../lib/team'
import { HistoryPage } from '../history/HistoryPage'
import { SalePage } from '../sale/SalePage'
import { NetStatus } from '../sync/NetStatus'
import { useSyncState } from '../sync/useSyncState'
import { PinLockScreen, PinSetupScreen } from './PinScreens'
import { useInactivityLock } from './useInactivityLock'

export { INACTIVITY_MS } from './useInactivityLock'

type Page = 'vendre' | 'ventes'
type Gate = 'locked' | 'setup' | 'change' | 'open'

/**
 * Cashier space on their own account (personal device): Vendre and « Mes ventes » only. The
 * till opens with THEIR PIN, locks again after 5 minutes without activity, and asks for a PIN
 * first when none is set (first time, or after a reset by the owner). The server enforces the
 * same rules (no sale without a PIN, maximum discount, own sales only).
 */
export function CashierApp({
  membership,
  signOut,
  onLostAccess,
  onSwitchSpace,
}: {
  membership: MemberShop
  signOut: () => Promise<void>
  /** The PIN state changed or the membership may be gone: reload my_member_shops. */
  onLostAccess: () => void
  /** Owner of another shop too: back to the chooser. */
  onSwitchSpace?: () => void
}) {
  const needsPin = !membership.pin_set
  const [gate, setGate] = useState<Gate>(needsPin ? 'setup' : 'locked')
  const [page, setPage] = useState<Page>('vendre')
  const sync = useSyncState()

  // Inactivity lock: any touch, click or key restarts the 5 minutes.
  useInactivityLock(gate === 'open', () => setGate('locked'))

  const leave = () => void signOut()

  if (gate === 'setup' || gate === 'change')
    return (
      <PinSetupScreen
        shopId={membership.shop_id}
        shopName={membership.shop_name}
        askCurrent={gate === 'change'}
        reset={gate === 'setup' && membership.pin_must_change}
        onDone={() => {
          setGate('open')
          if (needsPin) onLostAccess()
        }}
        onCancel={gate === 'change' ? () => setGate('open') : undefined}
      />
    )
  if (gate === 'locked')
    return (
      <PinLockScreen
        shopId={membership.shop_id}
        shopName={membership.shop_name}
        cashierName={membership.display_name}
        onUnlocked={() => setGate('open')}
        onNotSet={() => setGate('setup')}
        onSignOut={leave}
      />
    )

  return (
    <div className="cashier">
      <header className="cashier__top">
        <div>
          <p className="cashier__shop">{membership.shop_name}</p>
          <p className="cashier__who">
            Caisse de <b>{membership.display_name}</b>
            {membership.max_discount_pct > 0 && ` · remise max ${membership.max_discount_pct} %`}
          </p>
        </div>
        <NetStatus state={sync} shopId={membership.shop_id} />
        <Button variant="secondary" onClick={() => setGate('locked')}>
          Verrouiller
        </Button>
      </header>
      <nav className="tabs cashier__tabs" aria-label="Caisse">
        {(
          [
            ['vendre', 'Vendre'],
            ['ventes', 'Mes ventes'],
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
        {page === 'vendre' ? (
          <SalePage
            shopId={membership.shop_id}
            shopName={membership.shop_name}
            seller={{
              name: membership.display_name,
              maxDiscountPct: membership.max_discount_pct,
            }}
          />
        ) : (
          <LegacyPage>
            <HistoryPage shopId={membership.shop_id} mine />
          </LegacyPage>
        )}
      </main>
      <footer className="cashier__foot">
        <Button variant="ghost" onClick={() => setGate('change')}>
          Changer mon code PIN
        </Button>
        {onSwitchSpace && (
          <Button variant="ghost" onClick={onSwitchSpace}>
            Changer de boutique
          </Button>
        )}
        <Button variant="ghost" onClick={leave}>
          Se déconnecter
        </Button>
      </footer>
    </div>
  )
}
