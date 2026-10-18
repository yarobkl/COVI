import { useEffect, useState } from 'react'
import { ButtonLink, Notice, PageHead, Sheet } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import type { Shop } from '../../lib/types'

type SetupStatus =
  | { kind: 'loading' }
  | { kind: 'error' }
  | { kind: 'ready'; tables: number; menuItems: number }

/**
 * Counts are fetched with owner-scoped RLS, not cached in a browser flag.
 * A request error must never make an incomplete restaurant appear ready.
 */
function RestaurantHome({ shop }: { shop: Shop }) {
  const [setup, setSetup] = useState<SetupStatus>({ kind: 'loading' })

  useEffect(() => {
    let mounted = true

    async function checkSetup() {
      const [tables, menu] = await Promise.all([
        supabase
          .from('restaurant_tables')
          .select('id', { count: 'exact', head: true })
          .eq('shop_id', shop.id)
          .eq('active', true),
        supabase
          .from('restaurant_menu_items')
          .select('id', { count: 'exact', head: true })
          .eq('shop_id', shop.id)
          .eq('available', true),
      ])

      if (!mounted) return
      if (tables.error || menu.error || tables.count === null || menu.count === null) {
        setSetup({ kind: 'error' })
        return
      }
      setSetup({ kind: 'ready', tables: tables.count, menuItems: menu.count })
    }

    void checkSetup().catch(() => {
      if (mounted) setSetup({ kind: 'error' })
    })
    return () => {
      mounted = false
    }
  }, [shop.id])

  const hasTables = setup.kind === 'ready' && setup.tables > 0
  const hasMenu = setup.kind === 'ready' && setup.menuItems > 0
  const completed = Number(hasTables) + Number(hasMenu)
  const next = !hasTables
    ? { href: '#/restaurant-tables', label: 'Ajouter mes tables' }
    : !hasMenu
      ? { href: '#/restaurant-menu', label: 'Créer ma carte' }
      : { href: '#/restaurant-orders', label: 'Ouvrir Service & caisse' }

  return (
    <div className="page-stack">
      <PageHead
        title={shop.name}
        sub="Outils de gestion opérationnelle, financière et humaine des PME"
      />

      <Sheet>
        <p className="sector-guide__eyebrow">BIENVENUE DANS VOTRE RESTAURANT</p>
        <h2 className="section-title">
          {setup.kind === 'ready' && completed === 2
            ? 'Votre salle et votre carte sont prêtes.'
            : 'On prépare votre premier service ?'}
        </h2>
        <p className="sector-guide__lead">
          Installez vos tables, ajoutez votre carte, puis suivez les commandes jusqu’à la caisse.
        </p>

        <div className="sector-guide__progress" aria-live="polite">
          {setup.kind === 'loading'
            ? 'Vérification de votre installation…'
            : setup.kind === 'error'
              ? 'Impossible de vérifier votre installation pour le moment.'
              : `Préparation : ${completed} étape${completed > 1 ? 's' : ''} sur 2 terminée${completed > 1 ? 's' : ''}`}
        </div>

        <ol className="sector-guide__checklist" aria-label="Préparer mon restaurant">
          <li>
            <span className="sector-guide__number" aria-hidden="true">
              {hasTables ? '✓' : '1'}
            </span>
            <div className="sector-guide__step">
              <strong>Organiser les tables</strong>
              <span>
                {hasTables
                  ? `${setup.kind === 'ready' ? setup.tables : 0} table(s) active(s) enregistrée(s).`
                  : 'Donnez un numéro à chaque table et indiquez ses places.'}
              </span>
            </div>
            {hasTables && <span className="sector-guide__done">Fait</span>}
          </li>
          <li>
            <span className="sector-guide__number" aria-hidden="true">
              {hasMenu ? '✓' : '2'}
            </span>
            <div className="sector-guide__step">
              <strong>Créer la carte</strong>
              <span>
                {hasMenu
                  ? `${setup.kind === 'ready' ? setup.menuItems : 0} plat(s) ou boisson(s) disponible(s).`
                  : 'Ajoutez vos plats, vos boissons et leurs prix en FCFA.'}
              </span>
            </div>
            {hasMenu && <span className="sector-guide__done">Fait</span>}
          </li>
        </ol>

        <div className="sector-guide__actions">
          <ButtonLink
            variant="primary"
            size="lg"
            href={setup.kind === 'error' ? '#/restaurant-tables' : next.href}
          >
            {setup.kind === 'loading'
              ? 'Commencer avec mes tables'
              : setup.kind === 'error'
                ? 'Voir mes tables'
                : next.label}
          </ButtonLink>
          <a
            className="sector-guide__secondary"
            href={hasTables ? '#/restaurant-menu' : '#/restaurant-tables'}
          >
            {hasTables ? 'Voir ma carte' : 'Voir mon plan de salle'}
          </a>
        </div>
      </Sheet>

      <Sheet>
        <h2 className="section-title">Une fois installé, comment ça marche ?</h2>
        <ol className="sector-guide__journey" aria-label="Déroulement d’un service">
          <li><b>1. Table</b><span>Un client arrive. Ouvrez sa table.</span></li>
          <li><b>2. Commande</b><span>Notez ses plats et boissons.</span></li>
          <li><b>3. Service</b><span>Indiquez ce qui a été servi.</span></li>
          <li><b>4. Caisse</b><span>Enregistrez l’argent reçu en espèces.</span></li>
        </ol>
        <p className="sector-guide__footnote">
          La table se libère après le service et le règlement complet. Les montants proviennent des opérations enregistrées.
        </p>
      </Sheet>

      <details className="sector-guide__help">
        <summary>Besoin d’une explication ?</summary>
        <p>
          Commencez par « Plan de salle » pour ajouter les tables et leurs capacités.
          Puis ouvrez « Carte & boissons » pour inscrire les articles et leurs prix.
          Pendant le service, « Service & caisse » permet d’ouvrir une table, de suivre
          les commandes et d’enregistrer les paiements en espèces.
        </p>
      </details>
    </div>
  )
}

function SalonHome({ shop }: { shop: Shop }) {
  return (
    <div className="page-stack">
      <PageHead
        title={shop.name}
        sub="Outils de gestion opérationnelle, financière et humaine des PME"
      />
      <Sheet>
        <h2 className="section-title">Bienvenue dans votre salon</h2>
        <p>
          Commencez par vos prestations, puis préparez votre lien de réservation et votre agenda.
        </p>
        <div className="row-actions">
          <ButtonLink variant="primary" href="#/salon-services">Mes prestations</ButtonLink>
          <ButtonLink href="#/salon-bookings">Mes rendez-vous</ButtonLink>
        </div>
      </Sheet>
      <Notice tone="calm">
        <p>
          Les bénéfices et les encaissements ne seront affichés qu’après confirmation de transactions réelles.
        </p>
      </Notice>
    </div>
  )
}

/** Explains the real sector workflow rather than showing invented finance metrics. */
export function SectorHomePage({ shop }: { shop: Shop }) {
  return shop.business_kind === 'restaurant' ? (
    <RestaurantHome shop={shop} />
  ) : (
    <SalonHome shop={shop} />
  )
}
