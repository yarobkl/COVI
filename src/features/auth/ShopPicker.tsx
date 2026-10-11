import { Button } from '../../components/ui'
import { PlusIcon } from '../../components/icons'
import type { Shop } from '../../lib/types'
import { AuthPage } from './AuthPage'

/**
 * « Choisir une boutique »: one notebook label per shop of the account (multi-shop
 * subscription). Touching a label opens that shop's notebook.
 */
export function ShopPicker({
  shops,
  currentId,
  onChoose,
  onAdd,
  addBlocked,
  onSignOut,
}: {
  shops: readonly Shop[]
  /** The shop open before « Changer de boutique », marked on its label. */
  currentId?: string | null
  onChoose: (shop: Shop) => void
  /** Missing when adding a shop is not possible (see `addBlocked`). */
  onAdd?: () => void
  /** Why adding a shop is not possible: the button is disabled and says why. */
  addBlocked?: string | null
  onSignOut: () => void
}) {
  return (
    <AuthPage
      title="Choisir une boutique"
      lead="Votre compte tient plusieurs cahiers. Touchez celui de la boutique où vous êtes."
    >
      <ul className="shop-picker" aria-label="Vos boutiques">
        {shops.map((s) => (
          <li key={s.id}>
            <button
              type="button"
              className="label-card shop-picker__label"
              aria-current={s.id === currentId ? 'true' : undefined}
              onClick={() => onChoose(s)}
            >
              <span className="sommaire__shop-kicker">Cahier de caisse</span>
              <span className="sommaire__shop-name">{s.name}</span>
              {s.city && <span className="sommaire__shop-place">{s.city}</span>}
              {s.id === currentId && <span className="hand shop-picker__here">ouverte</span>}
            </button>
          </li>
        ))}
      </ul>
      <div className="shop-picker__foot">
        <Button
          variant="secondary"
          icon={<PlusIcon />}
          onClick={onAdd}
          disabled={!onAdd}
          aria-describedby={addBlocked ? 'ajout-boutique-impossible' : undefined}
        >
          Ajouter une boutique
        </Button>
        <button type="button" className="btn btn--ghost" onClick={onSignOut}>
          Se déconnecter
        </button>
      </div>
      {addBlocked && (
        <p className="shop-actions__note" id="ajout-boutique-impossible">
          {addBlocked}
        </p>
      )}
    </AuthPage>
  )
}
