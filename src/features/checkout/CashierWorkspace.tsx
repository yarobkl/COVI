import { useState } from 'react'
import { Button, Sheet } from '../../components/ui'
import type { CashierMembership } from '../../lib/cashierAccounts'
import { CashierPinSetup } from './CashierPinSetup'
import { PublicOrderInbox } from './PublicOrderInbox'

/** A cashier cannot reach the owner's stock, financial reports, settings,
 * link rotation, or invitations. Every cashier RPC verifies membership again.
 */
export function CashierWorkspace({
  shops,
  signOut,
  onRefresh,
}: {
  shops: CashierMembership[]
  signOut: () => Promise<void>
  onRefresh: () => void
}) {
  const [current, setCurrent] = useState(shops[0]?.shopId ?? '')
  const selected = shops.find(shop => shop.shopId === current) ?? shops[0]
  const [pinReady, setPinReady] = useState<Record<string, boolean>>({})
  if (!selected) return null
  const ready = pinReady[selected.shopId] ?? selected.pinConfigured
  return (
    <main className="checkout-guest seyes margin-rule">
      <Sheet>
        <p className="hand">COVI — Caisse</p>
        <h1>{selected.shopName}</h1>
        <p>Bonjour {selected.firstName}. Vous avez accès uniquement aux commandes à encaisser de cette boutique.</p>
        {shops.length > 1 && (
          <label>Choisir la boutique{' '}
            <select value={selected.shopId} onChange={(event) => setCurrent(event.target.value)}>
              {shops.map(shop => <option key={shop.shopId} value={shop.shopId}>{shop.shopName}</option>)}
            </select>
          </label>
        )}
        <Button variant="secondary" onClick={() => { void signOut() }}>Se déconnecter</Button>
      </Sheet>
      {!ready && (
        <CashierPinSetup
          shopId={selected.shopId}
          hasPin={false}
          onSaved={() => {
            setPinReady(value => ({ ...value, [selected.shopId]: true }))
            onRefresh()
          }}
        />
      )}
      {ready && (
        <>
          <PublicOrderInbox
            key={selected.shopId}
            shopId={selected.shopId}
            shopName={selected.shopName}
            verifiedCashierFirstName={selected.firstName}
            requirePin
          />
          <CashierPinSetup shopId={selected.shopId} hasPin
            onSaved={() => onRefresh()} />
        </>
      )}
    </main>
  )
}
