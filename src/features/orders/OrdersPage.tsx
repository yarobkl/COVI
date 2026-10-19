import { PageHead } from '../../components/ui'
import { routeHash } from '../../app/routes'
import { mobilePaymentsEnabled } from '../../lib/mobilePayments'
import type { Shop } from '../../lib/types'
import { OpenPaySettingsPanel } from './OpenPaySettingsPanel'
import { BlockedCustomersPanel } from './BlockedCustomersPanel'
import { OrderChannelPanel } from './OrderChannelPanel'
import { OrdersInbox } from './OrdersInbox'
import { WebsiteConnectPanel } from './WebsiteConnectPanel'

/** « Commandes » : les demandes reçues des clients, et le QR code / les liens de la boutique. */
export function OrdersPage({ shop, tab }: { shop: Shop; tab?: 'qr' | 'sites' }) {
  return (
    <>
      <nav className="tabs page-tabs" aria-label="Commandes">
        <a
          className="tabs__tab"
          href={routeHash({ page: 'commandes' })}
          aria-current={tab ? undefined : 'page'}
        >
          Commandes reçues
        </a>
        <a
          className="tabs__tab"
          href={routeHash({ page: 'commandes', filter: 'qr' })}
          aria-current={tab === 'qr' ? 'page' : undefined}
        >
          QR &amp; liens
        </a>
        <a
          className="tabs__tab"
          href={routeHash({ page: 'commandes', filter: 'sites' })}
          aria-current={tab === 'sites' ? 'page' : undefined}
        >
          Sites web
        </a>
      </nav>
      <div className="orders-page">
        <PageHead
          title="Commandes"
          sub="Demandes par QR, réseaux sociaux ou sites web, avec les connexions à gérer."
        />
        {tab === 'sites' ? (
          <WebsiteConnectPanel shopId={shop.id} />
        ) : tab === 'qr' ? (
          <>
            <OrderChannelPanel shopId={shop.id} shopName={shop.name} />
            <BlockedCustomersPanel shopId={shop.id} />
            {mobilePaymentsEnabled && <OpenPaySettingsPanel shopId={shop.id} />}
          </>
        ) : (
          <OrdersInbox shopId={shop.id} />
        )}
      </div>
    </>
  )
}
