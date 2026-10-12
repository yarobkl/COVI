import { useState } from 'react'
import { ManualCheckoutFlow } from './ManualCheckoutFlow'
import { PublicOrderInbox } from './PublicOrderInbox'
import { PublicOrderLinksPanel } from './PublicOrderLinksPanel'

type Tab = 'manual' | 'orders' | 'links'

/** The future owner-only checkout workspace. Retains the existing notebook DA.
 * The whole workspace is behind VITE_COVI_CATEGORY_CHECKOUT_ENABLED=true.
 * The classic /vendre cashier remains untouched and the flag is off by default.
 */
export function NotebookCheckoutHub({ shopId, shopName }: { shopId: string; shopName: string }) {
  const [tab, setTab] = useState<Tab>('manual')
  const tabs: readonly { id: Tab; label: string }[] = [
    { id: 'manual', label: 'Vente au comptoir' },
    { id: 'orders', label: 'Commandes reçues' },
    { id: 'links', label: 'QR & liens' },
  ]
  return (
    <section className="checkout-hub">
      <header className="checkout-hub__head">
        <p className="hand">Mon cahier de vente.</p>
        <h1>La nouvelle caisse</h1>
        <p>Une même caisse pour les ventes directes et les demandes envoyées par les clients.</p>
      </header>
      <nav className="tabs checkout-hub__tabs" aria-label="Rubriques de la caisse">
        {tabs.map((item) => (
          <button
            key={item.id}
            type="button"
            className="tabs__tab"
            aria-current={tab === item.id ? 'page' : undefined}
            onClick={() => setTab(item.id)}
          >
            {item.label}
          </button>
        ))}
      </nav>
      {tab === 'manual' && <ManualCheckoutFlow shopId={shopId} shopName={shopName} />}
      {tab === 'orders' && <PublicOrderInbox shopId={shopId} shopName={shopName} />}
      {tab === 'links' && <PublicOrderLinksPanel shopId={shopId} shopName={shopName} />}
    </section>
  )
}
