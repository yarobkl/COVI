import { useCallback, useRef, useState, type FormEvent } from 'react'
import {
  Badge,
  Button,
  Dialog,
  EmptyState,
  Ledger,
  LedgerRow,
  PageHead,
  Sheet,
} from '../../components/ui'
import { fcfa, parseAmount } from '../../lib/format'
import {
  operationKey,
  salonApi,
  type SalonRole,
  type Supply,
  type SupplyUnit,
  type SupplyUsage,
} from '../../lib/salon'
import { ActionMessage, Loaded } from './SalonParts'
import { unitLabels, usageLabels } from './salonFormat'
import { useSalonAction, useSalonLoad } from './useSalonLoad'

type Draft = {
  id: string | null
  name: string
  category: string
  unit: SupplyUnit
  usage: SupplyUsage
  alert: string
  cost: string
  price: string
  active: boolean
}
type Move = {
  supply: Supply
  reason: 'purchase' | 'return' | 'loss' | 'correction'
  quantity: string
  cost: string
  note: string
}

const qty = (n: number, unit: SupplyUnit) =>
  `${n.toLocaleString('fr-FR', { maximumFractionDigits: 3 })} ${unitLabels[unit]}`

const reasonLabels = {
  purchase: 'Achat / arrivage',
  return: 'Retour en stock',
  loss: 'Perte, casse ou périmé',
  correction: 'Correction après comptage',
} as const

/** Produits du salon : à vendre et/ou consommés pendant les prestations. */
export function SalonStockPage({ shopId, role }: { shopId: string; role: SalonRole }) {
  const canEdit = role === 'owner' || role === 'manager'
  const load = useCallback(() => salonApi.supplies(shopId), [shopId])
  const data = useSalonLoad(load)
  const action = useSalonAction()
  const [draft, setDraft] = useState<Draft | null>(null)
  const [move, setMove] = useState<Move | null>(null)
  const moveKey = useRef(operationKey())
  const list = data.data ?? []
  const low = list.filter((s) => s.active && s.low)

  async function save(e: FormEvent) {
    e.preventDefault()
    if (!draft) return
    const id = await action.run(
      () =>
        salonApi.saveSupply(shopId, {
          id: draft.id,
          name: draft.name.trim(),
          category: draft.category.trim(),
          unit: draft.unit,
          usage: draft.usage,
          alertThreshold: Number(draft.alert.replace(',', '.')) || 0,
          unitCostXaf: Number(draft.cost.replace(',', '.')) || 0,
          salePriceXaf: draft.usage === 'consumption' ? null : parseAmount(draft.price),
          active: draft.active,
        }),
      'Produit enregistré.',
    )
    if (id) {
      setDraft(null)
      data.reload()
    }
  }

  async function applyMove(e: FormEvent) {
    e.preventDefault()
    if (!move) return
    const amount = Number(move.quantity.replace(',', '.'))
    if (!Number.isFinite(amount) || amount < 0) {
      action.setIsError(true)
      action.setMessage('Indiquez une quantité valable.')
      return
    }
    const done = await action.run(
      () =>
        salonApi.adjustSupply(shopId, {
          supplyId: move.supply.id,
          reason: move.reason,
          quantity: amount,
          unitCostXaf:
            move.reason === 'purchase' && move.cost.trim()
              ? Number(move.cost.replace(',', '.'))
              : null,
          note: move.note,
          key: moveKey.current,
        }),
      'Stock mis à jour.',
    )
    if (done !== undefined) {
      moveKey.current = operationKey()
      setMove(null)
      data.reload()
    }
  }

  return (
    <div className="page-stack">
      <PageHead
        title="Produits"
        sub="Shampoings, colorations, soins, mèches… Le stock baisse tout seul à la vente et à chaque prestation qui les consomme."
        action={
          canEdit ? (
            <Button
              variant="primary"
              onClick={() =>
                setDraft({
                  id: null,
                  name: '',
                  category: '',
                  unit: 'piece',
                  usage: 'both',
                  alert: '1',
                  cost: '',
                  price: '',
                  active: true,
                })
              }
            >
              Ajouter un produit
            </Button>
          ) : undefined
        }
      />
      <ActionMessage message={action.message} isError={action.isError} />
      <Loaded loading={data.loading} error={data.error}>
        {low.length > 0 && (
          <Sheet>
            <h2 className="section-title">À racheter</h2>
            <Ledger label="Stock bas">
              {low.map((s) => (
                <LedgerRow
                  key={s.id}
                  label={s.name}
                  meta={`seuil ${qty(s.alert_threshold, s.unit)}`}
                  value={<Badge tone="low">{qty(s.quantity_on_hand, s.unit)}</Badge>}
                />
              ))}
            </Ledger>
          </Sheet>
        )}
        {list.length === 0 ? (
          <EmptyState title="Aucun produit">
            Ajoutez les produits que vous vendez ou que vous utilisez pendant les prestations.
          </EmptyState>
        ) : (
          <Sheet>
            <Ledger label="Produits">
              {list.map((s) => (
                <LedgerRow
                  key={s.id}
                  variant={canEdit ? 'link' : undefined}
                  label={
                    canEdit ? (
                      <button
                        type="button"
                        className="ledger__open"
                        onClick={() =>
                          setDraft({
                            id: s.id,
                            name: s.name,
                            category: s.category ?? '',
                            unit: s.unit,
                            usage: s.usage,
                            alert: String(s.alert_threshold),
                            cost: String(s.unit_cost_xaf ?? ''),
                            price: s.sale_price_xaf === null ? '' : String(s.sale_price_xaf),
                            active: s.active,
                          })
                        }
                      >
                        {s.name}
                      </button>
                    ) : (
                      s.name
                    )
                  }
                  meta={[
                    usageLabels[s.usage],
                    s.sale_price_xaf !== null ? `vendu ${fcfa(s.sale_price_xaf)} F` : null,
                    canEdit && s.unit_cost_xaf !== null
                      ? `coût ${s.unit_cost_xaf.toLocaleString('fr-FR')} F / ${unitLabels[s.unit]}`
                      : null,
                    s.active ? null : 'arrêté',
                  ]
                    .filter(Boolean)
                    .join(' · ')}
                  value={
                    <>
                      {s.low && s.active ? (
                        <Badge tone="low">{qty(s.quantity_on_hand, s.unit)}</Badge>
                      ) : (
                        qty(s.quantity_on_hand, s.unit)
                      )}
                      {canEdit && (
                        <button
                          type="button"
                          className="salon-link"
                          onClick={() =>
                            setMove({
                              supply: s,
                              reason: 'purchase',
                              quantity: '',
                              cost: '',
                              note: '',
                            })
                          }
                        >
                          Mouvement
                        </button>
                      )}
                    </>
                  }
                />
              ))}
            </Ledger>
          </Sheet>
        )}
      </Loaded>

      {draft && (
        <Dialog open onClose={() => setDraft(null)} labelledBy="salon-supply-title" sheet>
          <form className="dialog__body" onSubmit={(e) => void save(e)}>
            <h2 className="dialog__title" id="salon-supply-title">
              {draft.id ? 'Modifier le produit' : 'Nouveau produit'}
            </h2>
            <div className="form-grid">
              <label>
                Nom
                <input
                  value={draft.name}
                  maxLength={120}
                  required
                  onChange={(e) => setDraft({ ...draft, name: e.target.value })}
                />
              </label>
              <label>
                Catégorie <small>(facultatif)</small>
                <input
                  value={draft.category}
                  maxLength={60}
                  onChange={(e) => setDraft({ ...draft, category: e.target.value })}
                />
              </label>
              <label>
                Unité
                <select
                  value={draft.unit}
                  onChange={(e) => setDraft({ ...draft, unit: e.target.value as SupplyUnit })}
                >
                  {(Object.keys(unitLabels) as SupplyUnit[]).map((u) => (
                    <option key={u} value={u}>
                      {unitLabels[u]}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Utilisation
                <select
                  value={draft.usage}
                  onChange={(e) => setDraft({ ...draft, usage: e.target.value as SupplyUsage })}
                >
                  {(Object.keys(usageLabels) as SupplyUsage[]).map((u) => (
                    <option key={u} value={u}>
                      {usageLabels[u]}
                    </option>
                  ))}
                </select>
              </label>
              {draft.usage !== 'consumption' && (
                <label>
                  Prix de vente (FCFA)
                  <input
                    inputMode="numeric"
                    value={draft.price}
                    required
                    onChange={(e) => setDraft({ ...draft, price: e.target.value })}
                  />
                </label>
              )}
              <label>
                Coût d’achat par {unitLabels[draft.unit]} (FCFA)
                <input
                  inputMode="decimal"
                  value={draft.cost}
                  onChange={(e) => setDraft({ ...draft, cost: e.target.value })}
                />
              </label>
              <label>
                Alerte quand il reste
                <input
                  inputMode="decimal"
                  value={draft.alert}
                  onChange={(e) => setDraft({ ...draft, alert: e.target.value })}
                />
              </label>
              <label className="form-check">
                <input
                  type="checkbox"
                  checked={draft.active}
                  onChange={(e) => setDraft({ ...draft, active: e.target.checked })}
                />
                En usage
              </label>
              {!draft.id && (
                <p className="form-grid__note">
                  Le stock de départ s’ajoute ensuite avec « Mouvement » → Achat.
                </p>
              )}
            </div>
            <ActionMessage message={action.message} isError={action.isError} />
            <div className="dialog__actions">
              <Button variant="ghost" onClick={() => setDraft(null)}>
                Fermer
              </Button>
              <Button type="submit" variant="primary" busy={action.busy}>
                Enregistrer
              </Button>
            </div>
          </form>
        </Dialog>
      )}

      {move && (
        <Dialog open onClose={() => setMove(null)} labelledBy="salon-move-title" sheet>
          <form className="dialog__body" onSubmit={(e) => void applyMove(e)}>
            <h2 className="dialog__title" id="salon-move-title">
              {move.supply.name} — {qty(move.supply.quantity_on_hand, move.supply.unit)}
            </h2>
            <div className="form-grid">
              <label className="form-grid__full">
                Mouvement
                <select
                  value={move.reason}
                  onChange={(e) => setMove({ ...move, reason: e.target.value as Move['reason'] })}
                >
                  {(Object.keys(reasonLabels) as Move['reason'][]).map((r) => (
                    <option key={r} value={r}>
                      {reasonLabels[r]}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                {move.reason === 'correction'
                  ? `Quantité comptée (${unitLabels[move.supply.unit]})`
                  : `Quantité (${unitLabels[move.supply.unit]})`}
                <input
                  inputMode="decimal"
                  value={move.quantity}
                  required
                  onChange={(e) => setMove({ ...move, quantity: e.target.value })}
                />
              </label>
              {move.reason === 'purchase' && (
                <label>
                  Coût d’achat par {unitLabels[move.supply.unit]} <small>(facultatif)</small>
                  <input
                    inputMode="decimal"
                    value={move.cost}
                    onChange={(e) => setMove({ ...move, cost: e.target.value })}
                  />
                </label>
              )}
              <label className="form-grid__full">
                Note <small>(facultatif)</small>
                <input
                  value={move.note}
                  maxLength={200}
                  onChange={(e) => setMove({ ...move, note: e.target.value })}
                />
              </label>
            </div>
            <ActionMessage message={action.message} isError={action.isError} />
            <div className="dialog__actions">
              <Button variant="ghost" onClick={() => setMove(null)}>
                Fermer
              </Button>
              <Button type="submit" variant="primary" busy={action.busy}>
                Enregistrer
              </Button>
            </div>
          </form>
        </Dialog>
      )}
    </div>
  )
}
