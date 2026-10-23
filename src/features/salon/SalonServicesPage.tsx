import { useCallback, useState, type FormEvent } from 'react'
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
import { salonApi, type SalonRole, type SalonService } from '../../lib/salon'
import { ActionMessage, Loaded } from './SalonParts'
import { minutesLabel, unitLabels } from './salonFormat'
import { useSalonAction, useSalonLoad } from './useSalonLoad'

const examples = [
  'Coupe homme',
  'Coupe femme',
  'Coupe enfant',
  'Barbe',
  'Shampoing',
  'Brushing',
  'Tresses',
  'Nattes',
  'Locks',
  'Défrisage',
  'Coloration',
  'Soin capillaire',
  'Pose de perruque',
  'Coiffure événementielle',
]

type Draft = {
  id: string | null
  name: string
  category: string
  description: string
  price: string
  duration: string
  cost: string
  active: boolean
  employeeIds: string[]
  consumables: { supply_id: string; quantity: string }[]
}

const blank: Draft = {
  id: null,
  name: '',
  category: '',
  description: '',
  price: '',
  duration: '30',
  cost: '',
  active: true,
  employeeIds: [],
  consumables: [],
}

/** Catalogue des prestations : chaque salon écrit les siennes (aucune liste imposée). */
export function SalonServicesPage({ shopId, role }: { shopId: string; role: SalonRole }) {
  const canEdit = role === 'owner' || role === 'manager'
  const load = useCallback(async () => {
    const [catalog, supplies] = await Promise.all([
      salonApi.catalog(shopId),
      canEdit ? salonApi.supplies(shopId) : Promise.resolve([]),
    ])
    return { catalog, supplies }
  }, [shopId, canEdit])
  const data = useSalonLoad(load)
  const action = useSalonAction()
  const [draft, setDraft] = useState<Draft | null>(null)
  const services = data.data?.catalog.services ?? []
  const staff = (data.data?.catalog.staff ?? []).filter((s) => s.active)
  const consumable = (data.data?.supplies ?? []).filter((s) => s.usage !== 'sale' && s.active)
  const categories = [...new Set(services.map((s) => s.category).filter(Boolean))] as string[]

  async function edit(s: SalonService) {
    const items = await action.run(() => salonApi.consumables(shopId, s.id))
    setDraft({
      id: s.id,
      name: s.name,
      category: s.category ?? '',
      description: s.description ?? '',
      price: String(s.price_xaf),
      duration: String(s.duration_minutes),
      cost: s.direct_cost_xaf ? String(s.direct_cost_xaf) : '',
      active: s.active,
      employeeIds: s.employee_ids,
      consumables: (items ?? []).map((i) => ({
        supply_id: i.supply_id,
        quantity: String(i.quantity),
      })),
    })
  }

  async function save(e: FormEvent) {
    e.preventDefault()
    if (!draft) return
    const price = parseAmount(draft.price)
    const duration = Number(draft.duration)
    if (
      draft.name.trim().length < 2 ||
      price === null ||
      !Number.isInteger(duration) ||
      duration < 5 ||
      duration > 720
    ) {
      action.setIsError(true)
      action.setMessage('Vérifiez le nom, le prix et la durée (5 à 720 minutes).')
      return
    }
    const items = draft.consumables
      .map((c) => ({ supply_id: c.supply_id, quantity: Number(c.quantity.replace(',', '.')) }))
      .filter((c) => c.supply_id && c.quantity > 0)
    const ok = await action.run(
      async () => {
        const id = await salonApi.saveService(shopId, {
          id: draft.id,
          name: draft.name.trim(),
          category: draft.category.trim(),
          description: draft.description.trim(),
          priceXaf: price,
          durationMinutes: duration,
          directCostXaf: parseAmount(draft.cost) ?? 0,
          active: draft.active,
          employeeIds: draft.employeeIds,
        })
        await salonApi.setConsumables(shopId, id, items)
        return id
      },
      draft.id ? 'Prestation mise à jour.' : 'Prestation ajoutée.',
    )
    if (ok) {
      setDraft(null)
      data.reload()
    }
  }

  const grouped = categories.length
    ? [
        ...categories.map((c) => ({ title: c, list: services.filter((s) => s.category === c) })),
        { title: 'Sans catégorie', list: services.filter((s) => !s.category) },
      ]
    : [{ title: '', list: services }]

  return (
    <div className="page-stack">
      <PageHead
        title="Prestations"
        sub="Vos prestations, prix et durées. Les durées remplissent l’agenda ; les prix arrivent tout seuls à la caisse."
        action={
          canEdit ? (
            <Button variant="primary" onClick={() => setDraft({ ...blank })}>
              Ajouter une prestation
            </Button>
          ) : undefined
        }
      />
      <ActionMessage message={action.message} isError={action.isError} />
      <Loaded loading={data.loading} error={data.error}>
        {services.length === 0 ? (
          <EmptyState
            title="Aucune prestation"
            actions={
              canEdit ? (
                <Button variant="primary" onClick={() => setDraft({ ...blank })}>
                  Ajouter ma première prestation
                </Button>
              ) : undefined
            }
          >
            Exemples : {examples.join(', ')}. Écrivez les vôtres, avec vos prix.
          </EmptyState>
        ) : (
          <Sheet>
            {grouped
              .filter((g) => g.list.length > 0)
              .map((g) => (
                <section key={g.title || 'all'} className="entry">
                  {g.title && <h2 className="entry__title">{g.title}</h2>}
                  <Ledger label={g.title || 'Prestations'}>
                    {g.list.map((s) => (
                      <LedgerRow
                        key={s.id}
                        variant={canEdit ? 'link' : undefined}
                        label={
                          canEdit ? (
                            <button
                              type="button"
                              className="ledger__open"
                              onClick={() => void edit(s)}
                            >
                              {s.name}
                            </button>
                          ) : (
                            s.name
                          )
                        }
                        meta={[
                          minutesLabel(s.duration_minutes),
                          s.employee_ids.length
                            ? `${s.employee_ids.length} habilité${s.employee_ids.length > 1 ? 's' : ''}`
                            : 'toute l’équipe',
                          s.active ? null : 'arrêtée',
                        ]
                          .filter(Boolean)
                          .join(' · ')}
                        value={
                          <>
                            {!s.active && <Badge tone="low">Arrêtée</Badge>} {fcfa(s.price_xaf)} F
                          </>
                        }
                      />
                    ))}
                  </Ledger>
                </section>
              ))}
          </Sheet>
        )}
      </Loaded>

      {draft && (
        <Dialog open onClose={() => setDraft(null)} labelledBy="salon-service-title" sheet>
          <form className="dialog__body" onSubmit={(e) => void save(e)}>
            <h2 className="dialog__title" id="salon-service-title">
              {draft.id ? 'Modifier la prestation' : 'Nouvelle prestation'}
            </h2>
            <div className="form-grid">
              <label>
                Nom
                <input
                  value={draft.name}
                  list="salon-service-examples"
                  maxLength={120}
                  required
                  onChange={(e) => setDraft({ ...draft, name: e.target.value })}
                />
                <datalist id="salon-service-examples">
                  {examples.map((x) => (
                    <option key={x} value={x} />
                  ))}
                </datalist>
              </label>
              <label>
                Catégorie <small>(facultatif)</small>
                <input
                  value={draft.category}
                  list="salon-service-categories"
                  maxLength={60}
                  onChange={(e) => setDraft({ ...draft, category: e.target.value })}
                />
                <datalist id="salon-service-categories">
                  {categories.map((x) => (
                    <option key={x} value={x} />
                  ))}
                </datalist>
              </label>
              <label>
                Prix (FCFA)
                <input
                  inputMode="numeric"
                  value={draft.price}
                  required
                  onChange={(e) => setDraft({ ...draft, price: e.target.value })}
                />
              </label>
              <label>
                Durée (minutes)
                <input
                  inputMode="numeric"
                  value={draft.duration}
                  required
                  onChange={(e) => setDraft({ ...draft, duration: e.target.value })}
                />
              </label>
              <label className="form-grid__full">
                Description <small>(facultatif)</small>
                <textarea
                  value={draft.description}
                  maxLength={500}
                  onChange={(e) => setDraft({ ...draft, description: e.target.value })}
                />
              </label>
              <fieldset className="salon-fieldset form-grid__full">
                <legend>Qui peut la faire ?</legend>
                <p className="entry__meta">Sans case cochée, toute l’équipe peut la faire.</p>
                <div className="salon-checks">
                  {staff.map((m) => (
                    <label className="form-check" key={m.employee_id}>
                      <input
                        type="checkbox"
                        checked={draft.employeeIds.includes(m.employee_id)}
                        onChange={(e) =>
                          setDraft({
                            ...draft,
                            employeeIds: e.target.checked
                              ? [...draft.employeeIds, m.employee_id]
                              : draft.employeeIds.filter((x) => x !== m.employee_id),
                          })
                        }
                      />
                      {m.full_name}
                    </label>
                  ))}
                  {staff.length === 0 && (
                    <p className="entry__meta">Ajoutez votre équipe dans « Équipe ».</p>
                  )}
                </div>
              </fieldset>
              <fieldset className="salon-fieldset form-grid__full">
                <legend>Produits consommés à chaque prestation</legend>
                <p className="entry__meta">
                  Retirés du stock au moment du paiement, une seule fois. Sans produit ici, le coût
                  direct estimé ci-dessous est utilisé dans les marges.
                </p>
                {draft.consumables.map((c, i) => (
                  <div className="form-grid" key={i}>
                    <label>
                      Produit
                      <select
                        value={c.supply_id}
                        onChange={(e) =>
                          setDraft({
                            ...draft,
                            consumables: draft.consumables.map((x, j) =>
                              j === i ? { ...x, supply_id: e.target.value } : x,
                            ),
                          })
                        }
                      >
                        <option value="">Choisir…</option>
                        {consumable.map((s) => (
                          <option key={s.id} value={s.id}>
                            {s.name} ({unitLabels[s.unit]})
                          </option>
                        ))}
                      </select>
                    </label>
                    <label>
                      Quantité
                      <input
                        inputMode="decimal"
                        value={c.quantity}
                        onChange={(e) =>
                          setDraft({
                            ...draft,
                            consumables: draft.consumables.map((x, j) =>
                              j === i ? { ...x, quantity: e.target.value } : x,
                            ),
                          })
                        }
                      />
                    </label>
                  </div>
                ))}
                <div className="row-actions">
                  {consumable.length > 0 ? (
                    <Button
                      variant="ghost"
                      onClick={() =>
                        setDraft({
                          ...draft,
                          consumables: [...draft.consumables, { supply_id: '', quantity: '' }],
                        })
                      }
                    >
                      Ajouter un produit consommé
                    </Button>
                  ) : (
                    <p className="entry__meta">Créez d’abord vos produits dans « Produits ».</p>
                  )}
                  {draft.consumables.length > 0 && (
                    <Button
                      variant="ghost"
                      onClick={() =>
                        setDraft({ ...draft, consumables: draft.consumables.slice(0, -1) })
                      }
                    >
                      Retirer le dernier
                    </Button>
                  )}
                </div>
              </fieldset>
              <label>
                Coût direct estimé (FCFA) <small>(facultatif)</small>
                <input
                  inputMode="numeric"
                  value={draft.cost}
                  onChange={(e) => setDraft({ ...draft, cost: e.target.value })}
                />
              </label>
              <label className="form-check">
                <input
                  type="checkbox"
                  checked={draft.active}
                  onChange={(e) => setDraft({ ...draft, active: e.target.checked })}
                />
                Proposée aux clients
              </label>
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
    </div>
  )
}
