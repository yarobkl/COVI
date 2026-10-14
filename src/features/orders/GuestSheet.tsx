import type { ReactNode } from 'react'
import { LabelCard } from '../../components/ui'

/**
 * Page publique (commande, suivi) : une page du cahier de la boutique, quadrillage Seyès et marge
 * rouge, l'étiquette de la boutique en tête ; sur ordinateur, la feuille est posée sur la table.
 */
export function GuestSheet({
  shop,
  place,
  children,
}: {
  shop?: string | null
  place?: string | null
  children: ReactNode
}) {
  return (
    <div className="order-guest">
      <main className="order-guest__sheet seyes margin-rule" id="contenu">
        {shop && (
          <LabelCard className="order-guest__label">
            <p className="order-guest__shop">{shop}</p>
            {place && <p className="order-guest__place">{place}</p>}
          </LabelCard>
        )}
        {children}
        <p className="order-guest__footer">
          Bon tenu avec <b>COVI</b> — le cahier de la boutique.
        </p>
      </main>
    </div>
  )
}
