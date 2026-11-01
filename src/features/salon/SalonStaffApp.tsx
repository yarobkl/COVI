import { useEffect, useState } from 'react'
import { Button } from '../../components/ui'
import { salonApi, type SalonSpace } from '../../lib/salon'
import { SalonAgendaPage } from './SalonAgendaPage'
import { SalonCheckoutPage } from './SalonCheckoutPage'
import { SalonClientsPage } from './SalonClientsPage'
import { SalonHomePage } from './SalonHomePage'
import { SalonReportsPage } from './SalonReportsPage'
import { SalonServicesPage } from './SalonServicesPage'
import { SalonStockPage } from './SalonStockPage'
import { SalonTeamPage } from './SalonTeamPage'
import { roleLabels } from './salonFormat'
import { tabFromHash, tabLabels, tabsFor, type StaffTab } from './salonStaffTabs'

/** Espace d'un collaborateur du salon (son propre compte COVI), selon son rôle. */
export function SalonStaffApp({
  space,
  signOut,
  onSwitch,
  onLostAccess,
}: {
  space: SalonSpace
  signOut: () => Promise<void>
  onSwitch?: () => void
  onLostAccess: () => void
}) {
  const tabs = tabsFor(space.role)
  const [tab, setTab] = useState<StaffTab>(tabs[0])
  const shopId = space.shop_id

  // Les liens de l'accueil (#/salon-caisse…) ouvrent l'onglet correspondant, s'il est permis.
  useEffect(() => {
    const onHash = () => {
      const next = tabFromHash(window.location.hash)
      if (next && tabs.includes(next)) setTab(next)
    }
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [tabs])

  // Accès retiré par le propriétaire pendant la journée : on revient au choix des espaces.
  useEffect(() => {
    let alive = true
    const check = () =>
      salonApi.role(shopId).then(
        (role) => {
          if (alive && role !== space.role) onLostAccess()
        },
        () => undefined,
      )
    const timer = setInterval(check, 60000)
    return () => {
      alive = false
      clearInterval(timer)
    }
  }, [shopId, space.role, onLostAccess])

  return (
    <div className="shell salon-staff">
      <header className="salon-staff__head">
        <div>
          <p className="sommaire__shop-kicker">{roleLabels[space.role]}</p>
          <p className="sommaire__shop-name">{space.shop_name}</p>
          <p className="entry__meta">{space.display_name}</p>
        </div>
        <div className="row-actions">
          {onSwitch && (
            <Button variant="ghost" onClick={onSwitch}>
              Changer d’espace
            </Button>
          )}
          <Button variant="ghost" onClick={() => void signOut()}>
            Se déconnecter
          </Button>
        </div>
      </header>
      {tabs.length > 1 && (
        <nav className="tabs page-tabs" aria-label="Salon">
          {tabs.map((t) => (
            <button
              key={t}
              type="button"
              className="tabs__tab"
              aria-selected={tab === t}
              onClick={() => setTab(t)}
            >
              {tabLabels[t]}
            </button>
          ))}
        </nav>
      )}
      <main className="shell__page salon-staff__page">
        {tab === 'home' && (
          <SalonHomePage shopId={shopId} shopName={space.shop_name} role={space.role} />
        )}
        {tab === 'agenda' && <SalonAgendaPage shopId={shopId} role={space.role} />}
        {tab === 'caisse' && <SalonCheckoutPage shopId={shopId} role={space.role} />}
        {tab === 'clients' && <SalonClientsPage shopId={shopId} role={space.role} />}
        {tab === 'services' && <SalonServicesPage shopId={shopId} role={space.role} />}
        {tab === 'team' && <SalonTeamPage shopId={shopId} role={space.role} />}
        {tab === 'stock' && <SalonStockPage shopId={shopId} role={space.role} />}
        {tab === 'reports' && <SalonReportsPage shopId={shopId} />}
      </main>
    </div>
  )
}
