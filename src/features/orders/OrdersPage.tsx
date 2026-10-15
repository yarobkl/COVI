import { PageHead } from '../../components/ui'
import { routeHash } from '../../app/routes'
import { mobilePaymentsEnabled } from '../../lib/mobilePayments'
import type { Shop } from '../../lib/types'
import { OpenPaySettingsPanel } from './OpenPaySettingsPanel'
import { OrderChannelPanel } from './OrderChannelPanel'
import { OrdersInbox } from './OrdersInbox'

/** « Commandes » : les demandes reçues des clients, et le QR code / les liens de la boutique. */
export function OrdersPage({ shop, tab }: { shop: Shop; tab?: 'qr' }) {
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
      </nav>
      <div className="orders-page">
        <PageHead
          title="Commandes"
          sub="Les demandes reçues par le QR, WhatsApp et TikTok, et vos liens à partager."
        />
        {tab === 'qr' ? (
          <>
            <OrderChannelPanel shopId={shop.id} shopName={shop.name} />
            {mobilePaymentsEnabled && <OpenPaySettingsPanel shopId={shop.id} />}
          </>
        ) : (
          <OrdersInbox shopId={shop.id} />
        )}
      </div>
    </>
  )
}
