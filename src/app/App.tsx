import { useEffect, useId, useRef, useState } from 'react'
import { BrandMark } from '../components/Brand'
import { MenuIcon, PlusIcon } from '../components/icons'
import { Button, ButtonLink, cx, Dialog, LabelCard } from '../components/ui'
import { AccountDeletionPanel } from '../features/account/AccountDeletionPanel'
import { ArrivalsPage } from '../features/arrivals/ArrivalsPage'
import { AssistantPage } from '../features/assistant/AssistantPage'
import { useCurrentUser } from '../features/auth/useCurrentUser'
import { DashboardPage } from '../features/dashboard/DashboardPage'
import { useProfilePhoto } from '../features/profile/useProfilePhoto'
import { ExpensesPage } from '../features/expenses/ExpensesPage'
import { EmployeesPage } from '../features/staff/EmployeesPage'
import { HistoryPage } from '../features/history/HistoryPage'
import { NotificationBell } from '../features/notifications/NotificationBell'
import { useShopNotifications } from '../features/notifications/useShopNotifications'
import { OrdersPage } from '../features/orders/OrdersPage'
import { RestaurantTablesPage } from '../features/restaurant/RestaurantTablesPage'
import { RestaurantMenuPage } from '../features/restaurant/RestaurantMenuPage'
import { RestaurantOrdersPage } from '../features/restaurant/RestaurantOrdersPage'
import { RestaurantStaffPanel } from '../features/restaurant/RestaurantStaffPanel'
import { SalonServicesPage } from '../features/salon/SalonServicesPage'
import { SalonAgendaPage } from '../features/salon/SalonAgendaPage'
import { SalonCheckoutPage } from '../features/salon/SalonCheckoutPage'
import { SalonClientsPage } from '../features/salon/SalonClientsPage'
import { SalonHomePage } from '../features/salon/SalonHomePage'
import { SalonReportsPage } from '../features/salon/SalonReportsPage'
import { SalonSettingsPage } from '../features/salon/SalonSettingsPage'
import { SalonStockPage } from '../features/salon/SalonStockPage'
import { SalonTeamPage } from '../features/salon/SalonTeamPage'
import { SectorHomePage } from '../features/sectors/SectorHomePage'
import { TillSwitch } from '../features/team/TillSwitch'
import { SettingsPage } from '../features/settings/SettingsPage'
import { StatisticsPage } from '../features/statistics/StatisticsPage'
import { StockPage } from '../features/stock/StockPage'
import { NetStatus } from '../features/sync/NetStatus'
import { TeamPanel } from '../features/team/TeamPanel'
import { SharedCashiersPanel } from '../features/team/SharedCashiersPanel'
import { useSyncState } from '../features/sync/useSyncState'
import { plural } from '../lib/format'
import { legalLinks } from '../lib/legal'
import type { Shop } from '../lib/types'
import { initials, ownerName, shortName } from './identity'
import { pages } from './navigation'
import { availableInSector, navigationFor, sectorOf } from './sectorNavigation'
import { routeHash, routeKey, type ArrivalFilter, type PageId, type Route } from './routes'
import { useHashRoute } from './useHashRoute'

type PageContext = {
  shop: Shop
  /** The signed-in account of the validated session (AuthGate). */
  userId: string
  updateShop: (shop: Shop) => void
  navigate: (route: Route) => void
  onSimulation: () => void
  /** Owner's user id: groups their own sales in « Ventes par caissier ». */
  ownerId: string | null
  signOut: () => Promise<void>
}

/** Real app routes: shortcuts never use demo data or fake actions. */
const iosShortcuts: Record<'retail' | 'restaurant' | 'salon', readonly PageId[]> = {
  retail: ['vendre', 'stock', 'commandes', 'bilan'],
  restaurant: ['restaurant-orders', 'restaurant-tables', 'restaurant-menu', 'personnel'],
  salon: ['salon-bookings', 'salon-caisse', 'salon-clients', 'salon-services'],
}

function NativeHomeShortcuts({ sector }: { sector: 'retail' | 'restaurant' | 'salon' }) {
  return (
    <nav className="ios-shortcuts" aria-label="Accès rapide">
      {iosShortcuts[sector].map((page) => {
        const Icon = pages[page].icon
        return (
          <a key={page} href={routeHash({ page })} className="ios-shortcut">
            <span className="ios-shortcut__icon"><Icon /></span>
            <span>{pages[page].label}</span>
          </a>
        )
      })}
    </nav>
  )
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
      <ArrivalsPage
        shopId={shopId}
        kind={
          filter === 'commandes' ? 'supplier_order' : filter === 'ballons' ? 'balloon' : undefined
        }
      />
    </>
  )
}

function renderPage(route: Route, { shop, updateShop, onSimulation, ownerId }: PageContext) {
  const sector = sectorOf(shop.business_kind)
  const home =
    sector === 'retail' ? (
      <DashboardPage shop={shop} onSimulation={onSimulation} />
    ) : sector === 'salon' ? (
      <SalonHomePage shopId={shop.id} shopName={shop.name} role="owner" />
    ) : (
      <SectorHomePage shop={shop} />
    )
  if (!availableInSector(sector, route.page)) return home
  switch (route.page) {
    case 'accueil':
      return home
    case 'restaurant-orders':
      return <RestaurantOrdersPage shopId={shop.id} />
    case 'restaurant-tables':
      return <RestaurantTablesPage shopId={shop.id} />
    case 'restaurant-menu':
      return <RestaurantMenuPage shopId={shop.id} />
    case 'salon-services':
      return <SalonServicesPage shopId={shop.id} role="owner" />
    case 'salon-bookings':
      return <SalonAgendaPage shopId={shop.id} role="owner" />
    case 'salon-caisse':
      return <SalonCheckoutPage shopId={shop.id} role="owner" />
    case 'salon-clients':
      return <SalonClientsPage shopId={shop.id} role="owner" />
    case 'salon-equipe':
      return <SalonTeamPage shopId={shop.id} role="owner" />
    case 'salon-stock':
      return <SalonStockPage shopId={shop.id} role="owner" />
    case 'salon-rapports':
      return <SalonReportsPage shopId={shop.id} />
    case 'salon-reglages':
      return <SalonSettingsPage shopId={shop.id} />
    case 'vendre':
      return <TillSwitch shopId={shop.id} />
    case 'stock':
      return <StockPage shopId={shop.id} />
    case 'arrivages':
      return (
        <ArrivalsScreen
          shopId={shop.id}
          filter={
            route.filter === 'commandes' || route.filter === 'ballons' ? route.filter : undefined
          }
        />
      )
    case 'commandes':
      return (
        <OrdersPage
          shop={shop}
          tab={route.filter === 'qr' || route.filter === 'sites' ? route.filter : undefined}
        />
      )
    case 'ventes':
      return <HistoryPage shopId={shop.id} ownerId={ownerId} />
    case 'charges':
      return <ExpensesPage shopId={shop.id} />
    case 'personnel':
      return <EmployeesPage shopId={shop.id} />
    case 'bilan':
      return <StatisticsPage shopId={shop.id} />
    case 'assistant':
      return <AssistantPage shop={shop} />
    case 'boutique':
      return (
        <div className="page-stack">
          <SettingsPage shopId={shop.id} onShopUpdated={updateShop} />
          {sector === 'restaurant' && <RestaurantStaffPanel shopId={shop.id} />}
          {sector === 'retail' && (
            <>
              <SharedCashiersPanel shopId={shop.id} />
              <TeamPanel shopId={shop.id} shopName={shop.name} />
            </>
          )}
          <AccountDeletionPanel
            shopId={shop.id}
            shopName={shop.name}
            onScheduled={() => window.location.reload()}
          />
        </div>
      )
  }
}

/** Aide, conditions et confidentialité : toujours à portée de main (App Store). */
function LegalLinks() {
  return (
    <nav className="legal-links" aria-label="Informations légales">
      {legalLinks.map((l) => (
        <a key={l.href} href={l.href}>
          {l.label}
        </a>
      ))}
    </nav>
  )
}

/** The notebook label: shop name, place and who keeps it. */
function ShopLabel({ shop, owner }: { shop: Shop; owner: string | null }) {
  return (
    <LabelCard className="shop-label">
      <p className="sommaire__shop-kicker">
        {sectorOf(shop.business_kind) === 'retail' ? 'Cahier de caisse' : 'Cahier de gestion'}
      </p>
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
  userId,
  signOut,
  updateShop,
  onSimulation,
  onAddEstablishment,
  ownedEstablishments,
  onSelectEstablishment,
}: {
  shop: Shop
  /** The signed-in account of the validated session (AuthGate). */
  userId: string
  signOut: () => Promise<void>
  updateShop: (shop: Shop) => void
  onSimulation: () => void
  onAddEstablishment?: () => void
  ownedEstablishments?: Shop[]
  onSelectEstablishment?: (shopId: string) => void
}) {
  const { route, navigate } = useHashRoute()
  const sector = sectorOf(shop.business_kind)
  const visibleNavigation = navigationFor(sector)
  const iosApp = document.documentElement.dataset.coviPlatform === 'ios'
  const sync = useSyncState()
  const notifications = useShopNotifications(shop.id)
  const user = useCurrentUser()
  const owner = ownerName(user?.user_metadata)
  const profilePhotoUrl = useProfilePhoto(user)
  // The menu belongs to the page it was opened on: changing page (back button too) closes it.
  const [menuFor, setMenuFor] = useState<string | null>(null)
  const menuOpen = menuFor === routeKey(route)
  const setMenuOpen = (open: boolean) => setMenuFor(open ? routeKey(route) : null)
  const [signOutOpen, setSignOutOpen] = useState(false)
  const [shopSelectorOpen, setShopSelectorOpen] = useState(false)
  const shopSelectorTitle = useId()
  const selectableShops = ownedEstablishments?.length ? ownedEstablishments : [shop]
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
  const ctx: PageContext = {
    shop,
    userId,
    updateShop,
    navigate,
    onSimulation,
    ownerId: user?.id ?? userId,
    signOut,
  }

  return (
    <div className="shell">
      <a className="skip-link" href="#contenu">
        Aller au contenu
      </a>

      <header className="topbar">
        {iosApp ? (
          <div className="topbar__ios-brand">
            <BrandMark size={44} />
            <div className="topbar__ios-identity">
              <strong className="topbar__ios-title">COVI</strong>
              <button
                type="button"
                className="topbar__ios-shop ios-shop-trigger"
                aria-haspopup="dialog"
                aria-label="Changer d’établissement"
                onClick={() => setShopSelectorOpen(true)}
              >
                <span>{shop.name}</span>
                <span className="ios-shop-trigger__chevron" aria-hidden="true">
                  ⌄
                </span>
              </button>
            </div>
          </div>
        ) : (
          <p className="topbar__shop">{shop.name}</p>
        )}
        <NetStatus state={sync} shopId={shop.id} />
        <NotificationBell state={notifications} />
        <button
          type="button"
          className="avatar"
          aria-label="Ma boutique"
          aria-haspopup="dialog"
          onClick={() => setMenuOpen(true)}
        >
          {profilePhotoUrl ? <img src={profilePhotoUrl} alt="" /> : initials(owner ?? shop.name)}
        </button>
      </header>

      <nav className="sommaire" aria-label="Sommaire">
        <ShopLabel shop={shop} owner={owner} />
        <div className="sommaire__sale">
          <ButtonLink
            variant="sale"
            href={routeHash({ page: visibleNavigation.primary })}
            aria-current={current(visibleNavigation.primary)}
            icon={<PlusIcon />}
          >
            {sector === 'retail'
              ? 'Nouvelle vente'
              : sector === 'restaurant'
                ? 'Mes tables'
                : 'Ouvrir l’agenda'}
          </ButtonLink>
        </div>
        <NotificationBell state={notifications} className="bell--sommaire" withLabel />
        <h2 className="sommaire__title">Sommaire</h2>
        <ul className="sommaire__list">
          {visibleNavigation.sommaire.map(({ page, label, icon: Icon }) => (
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
          {sector === 'retail' && (
            <button type="button" className="btn btn--ghost sommaire__quiet" onClick={onSimulation}>
              Voir une boutique d’exemple
            </button>
          )}
          <button type="button" className="btn btn--ghost sommaire__quiet" onClick={askSignOut}>
            Se déconnecter
          </button>
          <button
            type="button"
            className="btn btn--ghost sommaire__quiet"
            onClick={() => onAddEstablishment?.()}
          >
            Ajouter un établissement
          </button>
          <LegalLinks />
        </div>
      </nav>

      <main
        className={cx('shell__page seyes margin-rule', `page--${route.page}`)}
        id="contenu"
        ref={main}
        tabIndex={-1}
      >
        {iosApp && route.page === 'accueil' && sector === 'retail' && (
          <div className="ios-page-heading">
            <h1>Vue d’ensemble</h1>
            <p>Vos chiffres et les actions essentielles.</p>
          </div>
        )}
        {iosApp && route.page === 'accueil' && (
          <section className="ios-home-actions" aria-label="Actions du commerce">
            <h2>Accès rapide</h2>
            <NativeHomeShortcuts sector={sector} />
          </section>
        )}
        <div key={routeKey(route)} className="page">
          {renderPage(route, ctx)}
        </div>
      </main>

      <nav className="bottom-nav" aria-label="Navigation principale">
        {visibleNavigation.bottomBar.map(({ page, label, icon: Icon }) =>
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
          aria-current={
            visibleNavigation.morePages.some((p) => p.page === route.page) ? 'page' : undefined
          }
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
            {visibleNavigation.morePages.map(({ page, label, icon: Icon }) => (
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
            {sector === 'retail' && (
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
            )}
            <Button variant="danger" onClick={askSignOut}>
              Se déconnecter
            </Button>
            <Button
              variant="secondary"
              onClick={() => {
                setMenuOpen(false)
                onAddEstablishment?.()
              }}
            >
              Ajouter un établissement
            </Button>
            <LegalLinks />
          </div>
        </div>
      </Dialog>

      {iosApp && (
        <Dialog
          open={shopSelectorOpen}
          onClose={() => setShopSelectorOpen(false)}
          labelledBy={shopSelectorTitle}
          sheet
        >
          <div className="dialog__body ios-shop-sheet">
            <h2 id={shopSelectorTitle} className="dialog__title">
              Mes établissements
            </h2>
            <div className="ios-shop-sheet__list">
              {selectableShops.map((establishment) => {
                const kind = sectorOf(establishment.business_kind)
                return (
                  <button
                    type="button"
                    key={establishment.id}
                    className="ios-shop-choice"
                    aria-current={establishment.id === shop.id ? 'true' : undefined}
                    disabled={
                      establishment.id !== shop.id && (sync.pending > 0 || !onSelectEstablishment)
                    }
                    onClick={() => {
                      if (establishment.id !== shop.id) {
                        window.location.hash = '#/'
                        onSelectEstablishment?.(establishment.id)
                      }
                      setShopSelectorOpen(false)
                    }}
                  >
                    <span className="ios-shop-choice__details">
                      <strong>{establishment.name}</strong>
                      <small>
                        {kind === 'retail'
                          ? 'Boutique'
                          : kind === 'restaurant'
                            ? 'Restaurant'
                            : 'Salon de coiffure'}
                      </small>
                    </span>
                    {establishment.id === shop.id && <span>Actuel</span>}
                  </button>
                )
              })}
            </div>
            {sync.pending > 0 && (
              <p role="status" className="ios-shop-sheet__hint">
                Des ventes sont à synchroniser sur cet appareil. Terminez la synchronisation avant
                de changer d’établissement.
              </p>
            )}
            {selectableShops.length < 3 && onAddEstablishment && (
              <Button
                variant="secondary"
                onClick={() => {
                  setShopSelectorOpen(false)
                  onAddEstablishment()
                }}
              >
                Ajouter un établissement
              </Button>
            )}
          </div>
        </Dialog>
      )}

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
