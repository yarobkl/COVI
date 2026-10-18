import { ButtonLink, PageHead, Sheet, Notice } from '../../components/ui'
import type { Shop } from '../../lib/types'

/** No fabricated KPIs: business-specific financial metrics require verified transactions. */
export function SectorHomePage({ shop }: { shop: Shop }) {
  const isRestaurant = shop.business_kind === 'restaurant'
  return (
    <div className="page-stack">
      <PageHead
        title={shop.name}
        sub="Outils de gestion opérationnelle, financière et humaine des PME"
      />
      <Sheet>
        <h2 className="section-title">
          {isRestaurant ? 'Bienvenue dans votre restaurant' : 'Bienvenue dans votre salon'}
        </h2>
        <p>
          {isRestaurant
            ? 'Configurez vos tables et votre carte. Chaque restaurant garde ses prix, son personnel et ses données.'
            : 'Commencez par vos prestations, puis préparez votre lien de réservation et votre agenda.'}
        </p>
        <div className="row-actions">
          {isRestaurant ? (
            <>
              <ButtonLink variant="primary" href="#/restaurant-tables">
                Configurer les tables
              </ButtonLink>
              <ButtonLink href="#/restaurant-menu">Créer ma carte</ButtonLink>
            </>
          ) : (
            <>
              <ButtonLink variant="primary" href="#/salon-services">
                Mes prestations
              </ButtonLink>
              <ButtonLink href="#/salon-bookings">Mes rendez-vous</ButtonLink>
            </>
          )}
        </div>
      </Sheet>
      <Notice tone="calm">
        <p>
          Les bénéfices, encaissements et états de commande ne seront affichés que lorsqu’ils
          pourront être calculés et confirmés à partir de transactions réelles. Aucun chiffre fictif
          n'apparaît dans votre gestion.
        </p>
      </Notice>
    </div>
  )
}
