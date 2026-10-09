import { useState } from 'react'
import { Menu } from 'lucide-react'
import { Brand } from '../components/Brand'
import { ArrivalsPage } from '../features/arrivals/ArrivalsPage'
import { DashboardPage } from '../features/dashboard/DashboardPage'
import { ExpensesPage } from '../features/expenses/ExpensesPage'
import { HistoryPage } from '../features/history/HistoryPage'
import { SalePage } from '../features/sale/SalePage'
import { SettingsPage } from '../features/settings/SettingsPage'
import { StatisticsPage } from '../features/statistics/StatisticsPage'
import { StockPage } from '../features/stock/StockPage'
import { SyncStatus } from '../features/sync/SyncStatus'
import type { Shop } from '../lib/types'
import { bottomNavigation, defaultPage, sideNavigation, type Page } from './navigation'

// Rendered as a plain call (not a component) so that each page keeps its position in the tree.
// Note: the three arrival pages share the same component and position, so React keeps their local
// state when switching between them (pre-existing behaviour).
function renderPage(page: Page, shop: Shop, updateShop: (shop: Shop) => void) {
  switch (page) {
    case 'Tableau de bord':
      return <DashboardPage shopId={shop.id} />
    case 'Mon stock':
      return <StockPage shopId={shop.id} />
    case 'Mes arrivages':
      return <ArrivalsPage shopId={shop.id} />
    case 'Nouvelle vente':
      return <SalePage shopId={shop.id} />
    case 'Mes commandes':
      return <ArrivalsPage shopId={shop.id} kind="supplier_order" />
    case 'Mes ballons':
      return <ArrivalsPage shopId={shop.id} kind="balloon" />
    case 'Charges de la boutique':
      return <ExpensesPage shopId={shop.id} />
    case 'Produits vendus':
      return <HistoryPage shopId={shop.id} />
    case 'Statistiques':
      return <StatisticsPage shopId={shop.id} />
    case 'Paramètres':
      return <SettingsPage shopId={shop.id} onShopUpdated={updateShop} />
  }
}

/** Signed-in shell: side navigation, header, page content and mobile bottom navigation. */
export function App({
  shop,
  signOut,
  updateShop,
  onSimulation,
}: {
  shop: Shop
  signOut: () => Promise<void>
  updateShop: (shop: Shop) => void
  onSimulation: () => void
}) {
  const [page, setPage] = useState<Page>(defaultPage)
  const [open, setOpen] = useState(false)
  return (
    <div className="app">
      <aside className={open ? 'open' : ''}>
        <Brand />
        <p className="tag">
          Le système d’exploitation
          <br />
          de votre commerce.
        </p>
        <nav>
          {sideNavigation.map(({ page: target, icon: Icon }) => (
            <button
              className={page === target ? 'active' : ''}
              onClick={() => {
                setPage(target)
                setOpen(false)
              }}
              key={target}
            >
              <Icon />
              {target}
            </button>
          ))}
        </nav>
        <div className="shop">
          <span>MA BOUTIQUE</span>
          <b>{shop.name}</b>
          <small>
            {shop.city || 'Ville non renseignée'} · {shop.currency}
          </small>
          <button
            className="demo-entry"
            onClick={() => {
              setOpen(false)
              onSimulation()
            }}
          >
            Découvrir la simulation · 3 mois
          </button>
        </div>
      </aside>
      <main>
        <header>
          <button className="menub" onClick={() => setOpen(!open)}>
            <Menu />
          </button>
          <div className="mobilebrand">
            <Brand />
          </div>
          <SyncStatus />
          <button className="avatar" onClick={signOut} title="Se déconnecter">
            RB
          </button>
        </header>
        <div className="content">{renderPage(page, shop, updateShop)}</div>
      </main>
      <div className="bottom">
        {bottomNavigation.map(({ label, icon: Icon, page: target }) => (
          <button
            className={page === target ? 'active' : ''}
            onClick={() => setPage(target)}
            key={label}
          >
            <Icon />
            {label}
          </button>
        ))}
      </div>
    </div>
  )
}
