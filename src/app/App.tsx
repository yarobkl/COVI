import { useEffect, useId, useRef, useState } from 'react'
import { MenuIcon, PlusIcon } from '../components/icons'
import { Button, ButtonLink, cx, Dialog, LabelCard } from '../components/ui'
import { ArrivalsPage } from '../features/arrivals/ArrivalsPage'
import { useCurrentUser } from '../features/auth/useCurrentUser'
import { DashboardPage } from '../features/dashboard/DashboardPage'
import { ExpensesPage } from '../features/expenses/ExpensesPage'
import { HistoryPage } from '../features/history/HistoryPage'
import { SalePage } from '../features/sale/SalePage'
import { SettingsPage } from '../features/settings/SettingsPage'
import { StatisticsPage } from '../features/statistics/StatisticsPage'
import { StockPage } from '../features/stock/StockPage'
import { NetStatus } from '../features/sync/NetStatus'
import { useSyncState } from '../features/sync/useSyncState'
import { plural } from '../lib/format'
import type { Shop } from '../lib/types'
import { initials, ownerName, shortName } from './identity'
import { LegacyPage } from './LegacyPage'
import { bottomBar, morePages, pages, sommaire } from './navigation'
import { routeHash, routeKey, type ArrivalFilter, type PageId, type Route } from './routes'
import { useHashRoute } from './useHashRoute'

type PageContext = {
  shop: Shop
  updateShop: (shop: Shop) => void
  navigate: (route: Route) => void
  onSimulation: () => void
}

/** « Tous · Commandes · Ballons »: filters of Arrivages (each one keeps its own state). */
const arrivalFilters: readonly { filter?: ArrivalFilter; label: string }[] = [
  { label: 'Tous' },
  { filter: 'commandes', label: 'Commandes' },
  { filter: 'ballons', label: 'Ballons' },
]

function ArrivalsScreen({ shopId, filter }: { shopId: string; filter?: ArrivalFilter }) {
  return (
    <>
      <nav className="tabs page-tabs" aria-label="Filtrer les arrivages">
        {arrivalFilters.map((f) => (
          <a
            key={f.label}
            className="tabs__tab"
            href={routeHash({ page: 'arrivages', filter: f.filter })}
            aria-current={filter === f.filter ? 'page' : undefined}
          >
            {f.label}
          </a>
        ))}
      </nav>
      <LegacyPage>
        <ArrivalsPage
          shopId={shopId}
          kind={
            filter === 'commandes' ? 'supplier_order' : filter === 'ballons' ? 'balloon' : undefined
          }
        />
      </LegacyPage>
    </>
  )
}

function renderPage(route: Route, { shop, updateShop }: PageContext) {
  switch (route.page) {
    case 'accueil':
      return (
        <LegacyPage>
          <DashboardPage shopId={shop.id} />
        </LegacyPage>
      )
    case 'vendre':
      return <SalePage shopId={shop.id} shopName={shop.name} />
    case 'stock':
      return (
        <LegacyPage>
          <StockPage shopId={shop.id} />
        </LegacyPage>
      )
    case 'arrivages':
      return <ArrivalsScreen shopId={shop.id} filter={route.filter} />
    case 'ventes':
      return (
        <LegacyPage>
          <HistoryPage shopId={shop.id} />
        </LegacyPage>
      )
    case 'charges':
      return (
        <LegacyPage>
          <ExpensesPage shopId={shop.id} />
        </LegacyPage>
      )
    case 'bilan':
      return (
        <LegacyPage>
          <StatisticsPage shopId={shop.id} />
        </LegacyPage>
      )
    case 'boutique':
      return (
        <LegacyPage>
          <SettingsPage shopId={shop.id} onShopUpdated={updateShop} />
        </LegacyPage>
      )
  }
}

/** The notebook label: shop name, place and who keeps it. */
function ShopLabel({ shop, owner }: { shop: Shop; owner: string | null }) {
  return (
    <LabelCard className="shop-label">
      <p className="sommaire__shop-kicker">Cahier de caisse</p>
      <p className="sommaire__shop-name">{shop.name}</p>
      {shop.city ? (
        <p className="sommaire__shop-place">{shop.city}</p>
      ) : (
        <p className="sommaire__shop-place">
          <a href={routeHash({ page: 'boutique' })}>Ajouter la ville</a>
        </p>
      )}
      {owner && (
        <p className="sommaire__shop-owner">
          Tenu par <span className="hand">{shortName(owner)}</span>
        </p>
      )}
    </LabelCard>
  )
}

/** « Se déconnecter de Chez Mama Grâce ? », with a warning when sales are still waiting. */
function SignOutDialog({
  open,
  onClose,
  shopName,
  pending,
  signOut,
}: {
  open: boolean
  onClose: () => void
  shopName: string
  pending: number
  signOut: () => Promise<void>
}) {
  const titleId = useId()
  const [busy, setBusy] = useState(false)
  const leave = async () => {
    setBusy(true)
    try {
      await signOut()
    } finally {
      setBusy(false)
    }
  }
  return (
    <Dialog open={open} onClose={onClose} labelledBy={titleId}>
      <div className="dialog__body">
        <h2 className="dialog__title" id={titleId}>
          Se déconnecter de {shopName} ?
        </h2>
        {pending > 0 ? (
          <p className="dialog__text">
            {pending > 1
              ? `${plural(pending, 'vente')} ne sont pas encore envoyées.`
              : '1 vente n’est pas encore envoyée.'}{' '}
            Attendez le réseau avant de vous déconnecter, sinon elle restera sur ce téléphone.
          </p>
        ) : (
          <p className="dialog__text">
            Pour revenir, connectez-vous avec la même adresse : vous retrouverez tout.
          </p>
        )}
        <div className="dialog__actions">
          <Button variant="secondary" onClick={onClose} autoFocus>
            {pending > 0 ? 'Attendre' : 'Rester'}
          </Button>
          <Button variant="danger" solid busy={busy} onClick={() => void leave()}>
            {pending > 0 ? 'Me déconnecter quand même' : 'Se déconnecter'}
          </Button>
        </div>
      </div>
    </Dialog>
  )
}

/**
 * Signed-in shell. Phone: top strip (shop, network, menu), page, bottom bar Accueil · Vendre ·
 * Stock · Plus. Computer (≥ 1024 px): the notebook « Sommaire » on the left, the page laid on the
 * table. The page follows the URL hash, so the Android back button works.
 */
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
  const { route, navigate } = useHashRoute()
  const sync = useSyncState()
  const user = useCurrentUser()
  const owner = ownerName(user?.user_metadata)
  // The menu belongs to the page it was opened on: changing page (back button too) closes it.
  const [menuFor, setMenuFor] = useState<string | null>(null)
  const menuOpen = menuFor === routeKey(route)
  const setMenuOpen = (open: boolean) => setMenuFor(open ? routeKey(route) : null)
  const [signOutOpen, setSignOutOpen] = useState(false)
  const menuTitle = useId()
  const main = useRef<HTMLElement>(null)
  const firstRoute = useRef(true)

  // Each page change: top of the page, focus on the page for screen readers.
  useEffect(() => {
    document.title = route.page === 'accueil' ? 'COVI' : `${pages[route.page].label} · COVI`
    if (firstRoute.current) {
      firstRoute.current = false
      return
    }
    window.scrollTo(0, 0)
    main.current?.focus({ preventScroll: true })
  }, [route])

  const current = (page: PageId) => (route.page === page ? 'page' : undefined)
  const askSignOut = () => {
    setMenuOpen(false)
    setSignOutOpen(true)
  }
  const ctx: PageContext = { shop, updateShop, navigate, onSimulation }

  return (
    <div className="shell">
      <a className="skip-link" href="#contenu">
        Aller au contenu
      </a>

      <header className="topbar">
        <p className="topbar__shop">{shop.name}</p>
        <NetStatus state={sync} shopId={shop.id} />
        <button
          type="button"
          className="avatar"
          aria-label="Ma boutique"
          aria-haspopup="dialog"
          onClick={() => setMenuOpen(true)}
        >
          {initials(owner ?? shop.name)}
        </button>
      </header>

      <nav className="sommaire" aria-label="Sommaire">
        <ShopLabel shop={shop} owner={owner} />
        <div className="sommaire__sale">
          <ButtonLink
            variant="sale"
            href={routeHash({ page: 'vendre' })}
            aria-current={current('vendre')}
            icon={<PlusIcon />}
          >
            Nouvelle vente
          </ButtonLink>
        </div>
        <h2 className="sommaire__title">Sommaire</h2>
        <ul className="sommaire__list">
          {sommaire.map(({ page, label, icon: Icon }) => (
            <li key={page}>
              <a className="sommaire__link" href={routeHash({ page })} aria-current={current(page)}>
                <Icon />
                <span>{label}</span>
              </a>
            </li>
          ))}
        </ul>
        <div className="sommaire__foot">
          <NetStatus state={sync} shopId={shop.id} />
          <button type="button" className="btn btn--ghost sommaire__quiet" onClick={onSimulation}>
            Voir une boutique d’exemple
          </button>
          <button type="button" className="btn btn--ghost sommaire__quiet" onClick={askSignOut}>
            Se déconnecter
          </button>
        </div>
      </nav>

      <main
        className={cx('shell__page seyes margin-rule', `page--${route.page}`)}
        id="contenu"
        ref={main}
        tabIndex={-1}
      >
        <div key={routeKey(route)} className="page">
          {renderPage(route, ctx)}
        </div>
      </main>

      <nav className="bottom-nav" aria-label="Navigation principale">
        {bottomBar.map(({ page, label, icon: Icon }) =>
          page === 'vendre' ? (
            <a
              key={page}
              className="bottom-nav__item bottom-nav__item--sale"
              href={routeHash({ page })}
              aria-current={current(page)}
            >
              <span className="bottom-nav__key">
                <Icon />
              </span>
              {label}
            </a>
          ) : (
            <a
              key={page}
              className="bottom-nav__item"
              href={routeHash({ page })}
              aria-current={current(page)}
            >
              <Icon />
              {label}
            </a>
          ),
        )}
        <button
          type="button"
          className="bottom-nav__item"
          aria-haspopup="dialog"
          aria-expanded={menuOpen}
          aria-current={morePages.some((p) => p.page === route.page) ? 'page' : undefined}
          onClick={() => setMenuOpen(true)}
        >
          <MenuIcon />
          Plus
        </button>
      </nav>

      <Dialog open={menuOpen} onClose={() => setMenuOpen(false)} labelledBy={menuTitle} sheet>
        <div className="dialog__body menu-sheet">
          <h2 className="visually-hidden" id={menuTitle}>
            Menu
          </h2>
          <ShopLabel shop={shop} owner={owner} />
          <ul className="sommaire__list">
            {morePages.map(({ page, label, icon: Icon }) => (
              <li key={page}>
                <a
                  className="sommaire__link"
                  href={routeHash({ page })}
                  aria-current={current(page)}
                  onClick={() => setMenuOpen(false)}
                >
                  <Icon />
                  <span>{label}</span>
                </a>
              </li>
            ))}
          </ul>
          <div className="menu-sheet__foot">
            <button
              type="button"
              className="btn btn--ghost"
              onClick={() => {
                setMenuOpen(false)
                onSimulation()
              }}
            >
              Voir une boutique d’exemple
            </button>
            <Button variant="danger" onClick={askSignOut}>
              Se déconnecter
            </Button>
          </div>
        </div>
      </Dialog>

      <SignOutDialog
        open={signOutOpen}
        onClose={() => setSignOutOpen(false)}
        shopName={shop.name}
        pending={sync.pending}
        signOut={signOut}
      />
    </div>
  )
}
