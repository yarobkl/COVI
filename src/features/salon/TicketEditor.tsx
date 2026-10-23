import { useRef, useState } from 'react'
import {
  Amount,
  Badge,
  Button,
  Dialog,
  Ledger,
  LedgerRow,
  Notice,
  Stamp,
} from '../../components/ui'
import { fcfa, parseAmount } from '../../lib/format'
import {
  operationKey,
  salonApi,
  type PaymentMethod,
  type SalonCatalog,
  type SalonRole,
  type Supply,
  type Ticket,
} from '../../lib/salon'
import { ActionMessage } from './SalonParts'
import { methodLabels } from './salonFormat'
import { useSalonAction } from './useSalonLoad'

const ticketStatusLabel: Record<Ticket['status'], string> = {
  open: 'À encaisser',
  paid: 'Payée',
  partially_refunded: 'Remboursée en partie',
  refunded: 'Remboursée',
  cancelled: 'Annulée',
}

type PayRow = { method: PaymentMethod; amount: string; reference: string }

/**
 * Note d'un client : lignes (prestations, produits), remise, encaissement en un ou plusieurs
 * moyens, remboursement. Tous les montants sont recalculés et vérifiés par le serveur.
 */
export function TicketEditor({
  shopId,
  role,
  ticket: initial,
  catalog,
  supplies,
  onClose,
  onChanged,
}: {
  shopId: string
  role: SalonRole
  ticket: Ticket
  catalog: SalonCatalog
  supplies: Supply[]
  onClose: () => void
  onChanged: (ticket: Ticket) => void
}) {
  const [ticket, setTicket] = useState(initial)
  const action = useSalonAction()
  const canManage = role === 'owner' || role === 'manager'
  const payKey = useRef(operationKey())
  const refundKey = useRef(operationKey())
  const staff = catalog.staff.filter((s) => s.active)
  const services = catalog.services.filter((s) => s.active)
  const products = supplies.filter((s) => s.active && s.usage !== 'consumption')
  const [serviceId, setServiceId] = useState(services[0]?.id ?? '')
  const firstStaff = (sid: string) => {
    const svc = services.find((s) => s.id === sid)
    return staff.find((m) => !svc?.employee_ids.length || svc.employee_ids.includes(m.employee_id))
  }
  const [employeeId, setEmployeeId] = useState(firstStaff(services[0]?.id ?? '')?.employee_id ?? '')
  const [price, setPrice] = useState('')
  const [productId, setProductId] = useState(products[0]?.id ?? '')
  const [productQty, setProductQty] = useState('1')
  const [discount, setDiscount] = useState(String(initial.discount_xaf || ''))
  const [rows, setRows] = useState<PayRow[]>([
    { method: 'cash', amount: String(initial.total_xaf), reference: '' },
  ])
  const [refunding, setRefunding] = useState(false)
  const [refundLines, setRefundLines] = useState<string[]>([])
  const [refundMethod, setRefundMethod] = useState<PaymentMethod>('cash')
  const [restock, setRestock] = useState(true)
  const [reason, setReason] = useState('')

  const selectedService = services.find((s) => s.id === serviceId)
  const qualified = staff.filter(
    (m) =>
      !selectedService ||
      selectedService.employee_ids.length === 0 ||
      selectedService.employee_ids.includes(m.employee_id),
  )

  const apply = (next: Ticket | undefined) => {
    if (!next) return
    setTicket(next)
    onChanged(next)
    if (next.status === 'open') {
      setRows((r) => (r.length === 1 ? [{ ...r[0], amount: String(next.total_xaf) }] : r))
    }
  }

  const paySum = rows.reduce((sum, r) => sum + (parseAmount(r.amount) ?? 0), 0)
  const open = ticket.status === 'open'
  const refundable = ticket.lines.filter((l) => !l.refunded)
  const refundTotal = ticket.lines
    .filter((l) => refundLines.includes(l.id))
    .reduce((s, l) => s + (l.net_xaf ?? l.line_total_xaf), 0)

  async function addService() {
    if (!serviceId || !employeeId) return
    const svc = services.find((s) => s.id === serviceId)
    const typed = parseAmount(price)
    apply(
      await action.run(() =>
        salonApi.addLine(shopId, ticket.id, {
          kind: 'service',
          itemId: serviceId,
          employeeId,
          quantity: 1,
          unitPriceXaf: canManage && typed !== null && typed !== svc?.price_xaf ? typed : null,
        }),
      ),
    )
    setPrice('')
  }

  async function addProduct() {
    const qty = Number(productQty.replace(',', '.'))
    if (!productId || !Number.isFinite(qty) || qty <= 0) {
      action.setIsError(true)
      action.setMessage('Indiquez une quantité valable.')
      return
    }
    apply(
      await action.run(() =>
        salonApi.addLine(shopId, ticket.id, {
          kind: 'product',
          itemId: productId,
          employeeId: null,
          quantity: qty,
          unitPriceXaf: null,
        }),
      ),
    )
  }

  async function pay() {
    const payments = rows
      .map((r) => ({
        method: r.method,
        amount_xaf: parseAmount(r.amount) ?? 0,
        reference: r.reference.trim() || null,
      }))
      .filter((p) => p.amount_xaf > 0)
    const done = await action.run(
      () => salonApi.pay(shopId, ticket.id, payments, payKey.current),
      'Paiement enregistré.',
    )
    if (done) {
      payKey.current = operationKey()
      apply(done)
    }
  }

  async function refund() {
    const done = await action.run(
      () =>
        salonApi.refund(shopId, ticket.id, {
          lineIds: refundLines,
          method: refundMethod,
          restock,
          reason,
          key: refundKey.current,
        }),
      'Remboursement enregistré.',
    )
    if (done) {
      refundKey.current = operationKey()
      setRefunding(false)
      setRefundLines([])
      setReason('')
      apply(done)
    }
  }

  return (
    <Dialog open onClose={onClose} labelledBy="salon-ticket-title" sheet>
      <div className="dialog__body salon-ticket">
        <div className="entry__head">
          <h2 className="dialog__title" id="salon-ticket-title">
            {ticket.client_name || 'Client de passage'}
          </h2>
          <Badge tone={open ? 'waiting' : ticket.status === 'paid' ? 'success' : 'low'}>
            {ticketStatusLabel[ticket.status]}
          </Badge>
        </div>
        {ticket.status === 'paid' && (
          <Stamp kind="paid" drop>
            Payé
          </Stamp>
        )}

        {ticket.lines.length === 0 ? (
          <p className="entry__meta">Ajoutez une prestation ou un produit.</p>
        ) : (
          <Ledger label="Lignes de la note">
            {ticket.lines.map((l) => (
              <LedgerRow
                key={l.id}
                label={
                  <>
                    {l.refunded ? <s>{l.label}</s> : l.label}
                    {open && (
                      <button
                        type="button"
                        className="salon-link"
                        onClick={() =>
                          void action
                            .run(() => salonApi.removeLine(shopId, ticket.id, l.id))
                            .then(apply)
                        }
                        disabled={action.busy}
                      >
                        Retirer
                      </button>
                    )}
                  </>
                }
                meta={[
                  l.employee_name,
                  l.quantity !== 1
                    ? `${l.quantity.toLocaleString('fr-FR')} × ${fcfa(l.unit_price_xaf)}`
                    : null,
                  l.unit_price_xaf !== l.list_price_xaf
                    ? `prix catalogue ${fcfa(l.list_price_xaf)}`
                    : null,
                  l.refunded ? 'remboursé' : null,
                ]
                  .filter(Boolean)
                  .join(' · ')}
                value={<Amount value={l.line_total_xaf} />}
              />
            ))}
            {ticket.discount_xaf > 0 && (
              <LedgerRow
                label="Remise"
                value={<Amount value={-ticket.discount_xaf} tone="out" />}
              />
            )}
            <LedgerRow
              variant="total"
              label="Total"
              value={<Amount value={ticket.total_xaf} size="lg" />}
            />
          </Ledger>
        )}

        {open && (
          <>
            {ticket.lines.length > 0 && (
              <fieldset className="salon-fieldset">
                <legend>Encaisser</legend>
                {rows.map((r, i) => (
                  <div className="form-grid" key={i}>
                    <label>
                      Moyen de paiement
                      <select
                        value={r.method}
                        onChange={(e) =>
                          setRows(
                            rows.map((x, j) =>
                              j === i ? { ...x, method: e.target.value as PaymentMethod } : x,
                            ),
                          )
                        }
                      >
                        {(Object.keys(methodLabels) as PaymentMethod[]).map((m) => (
                          <option key={m} value={m}>
                            {methodLabels[m]}
                          </option>
                        ))}
                      </select>
                    </label>
                    <label>
                      Montant (FCFA)
                      <input
                        inputMode="numeric"
                        value={r.amount}
                        onChange={(e) =>
                          setRows(
                            rows.map((x, j) => (j === i ? { ...x, amount: e.target.value } : x)),
                          )
                        }
                      />
                    </label>
                    {r.method !== 'cash' && (
                      <label className="form-grid__full">
                        Référence de la transaction <small>(facultatif)</small>
                        <input
                          value={r.reference}
                          maxLength={80}
                          onChange={(e) =>
                            setRows(
                              rows.map((x, j) =>
                                j === i ? { ...x, reference: e.target.value } : x,
                              ),
                            )
                          }
                        />
                      </label>
                    )}
                  </div>
                ))}
                <div className="row-actions">
                  {rows.length < 3 && (
                    <Button
                      variant="ghost"
                      onClick={() =>
                        setRows([
                          ...rows,
                          {
                            method: 'mobile_money',
                            amount: String(Math.max(0, ticket.total_xaf - paySum)),
                            reference: '',
                          },
                        ])
                      }
                    >
                      Payer avec un 2e moyen
                    </Button>
                  )}
                  {rows.length > 1 && (
                    <Button variant="ghost" onClick={() => setRows(rows.slice(0, -1))}>
                      Retirer le dernier moyen
                    </Button>
                  )}
                </div>
                {rows.some((r) => r.method === 'mobile_money' || r.method === 'card') && (
                  <Notice title="Vérifiez la réception avant de valider" live={false}>
                    COVI n’interroge pas l’opérateur : le paiement Mobile Money ou carte est
                    confirmé par vous, à la caisse.
                  </Notice>
                )}
                <Button
                  variant="primary"
                  size="lg"
                  block
                  busy={action.busy}
                  disabled={paySum !== ticket.total_xaf}
                  onClick={() => void pay()}
                >
                  {paySum === ticket.total_xaf
                    ? `Encaisser ${fcfa(ticket.total_xaf)} FCFA`
                    : `La somme des paiements (${fcfa(paySum)}) doit faire ${fcfa(ticket.total_xaf)}`}
                </Button>
              </fieldset>
            )}

            <details className="salon-fold" open={ticket.lines.length === 0}>
              <summary>Ajouter une prestation</summary>
              <fieldset className="salon-fieldset">
                <legend>Ajouter une prestation</legend>
                {services.length === 0 ? (
                  <p className="entry__meta">Aucune prestation active dans le catalogue.</p>
                ) : (
                  <div className="form-grid">
                    <label>
                      Prestation
                      <select
                        value={serviceId}
                        onChange={(e) => {
                          setServiceId(e.target.value)
                          setEmployeeId(firstStaff(e.target.value)?.employee_id ?? '')
                        }}
                      >
                        {services.map((s) => (
                          <option key={s.id} value={s.id}>
                            {s.name} — {fcfa(s.price_xaf)} F
                          </option>
                        ))}
                      </select>
                    </label>
                    <label>
                      Réalisée par
                      <select value={employeeId} onChange={(e) => setEmployeeId(e.target.value)}>
                        {qualified.length === 0 && (
                          <option value="">Personne n’est habilité</option>
                        )}
                        {qualified.map((m) => (
                          <option key={m.employee_id} value={m.employee_id}>
                            {m.full_name}
                          </option>
                        ))}
                      </select>
                    </label>
                    {canManage && (
                      <label>
                        Prix final <small>(laisser vide = prix du catalogue)</small>
                        <input
                          inputMode="numeric"
                          value={price}
                          onChange={(e) => setPrice(e.target.value)}
                          placeholder="Prix du catalogue"
                        />
                      </label>
                    )}
                    <div className="form-grid__actions">
                      <Button
                        onClick={() => void addService()}
                        busy={action.busy}
                        disabled={!employeeId}
                      >
                        Ajouter la prestation
                      </Button>
                    </div>
                  </div>
                )}
              </fieldset>
            </details>

            {products.length > 0 && (
              <details className="salon-fold">
                <summary>Vendre un produit</summary>
                <fieldset className="salon-fieldset">
                  <legend>Vendre un produit</legend>
                  <div className="form-grid">
                    <label>
                      Produit
                      <select value={productId} onChange={(e) => setProductId(e.target.value)}>
                        {products.map((p) => (
                          <option key={p.id} value={p.id} disabled={p.quantity_on_hand <= 0}>
                            {p.name} — {fcfa(p.sale_price_xaf ?? 0)} F (
                            {p.quantity_on_hand.toLocaleString('fr-FR')} en stock)
                          </option>
                        ))}
                      </select>
                    </label>
                    <label>
                      Quantité
                      <input
                        inputMode="decimal"
                        value={productQty}
                        onChange={(e) => setProductQty(e.target.value)}
                      />
                    </label>
                    <div className="form-grid__actions">
                      <Button onClick={() => void addProduct()} busy={action.busy}>
                        Ajouter le produit
                      </Button>
                    </div>
                  </div>
                </fieldset>
              </details>
            )}

            {canManage && ticket.subtotal_xaf > 0 && (
              <details className="salon-fold">
                <summary>Remise</summary>
                <fieldset className="salon-fieldset">
                  <legend>Remise</legend>
                  <div className="form-grid">
                    <label>
                      Montant de la remise (FCFA)
                      <input
                        inputMode="numeric"
                        value={discount}
                        onChange={(e) => setDiscount(e.target.value)}
                      />
                    </label>
                    <div className="form-grid__actions">
                      <Button
                        busy={action.busy}
                        onClick={() =>
                          void action
                            .run(() =>
                              salonApi.setDiscount(shopId, ticket.id, parseAmount(discount) ?? 0),
                            )
                            .then(apply)
                        }
                      >
                        Appliquer la remise
                      </Button>
                    </div>
                  </div>
                </fieldset>
              </details>
            )}
          </>
        )}

        {!open && ticket.payments.length > 0 && (
          <Ledger label="Paiements">
            {ticket.payments.map((p) => (
              <LedgerRow
                key={p.id}
                label={
                  p.kind === 'refund'
                    ? `Remboursement · ${methodLabels[p.method]}`
                    : methodLabels[p.method]
                }
                meta={[p.reference, 'confirmé à la caisse'].filter(Boolean).join(' · ')}
                value={
                  <Amount
                    value={p.kind === 'refund' ? -p.amount_xaf : p.amount_xaf}
                    tone={p.kind === 'refund' ? 'out' : 'in'}
                  />
                }
              />
            ))}
          </Ledger>
        )}

        {canManage &&
          (ticket.status === 'paid' || ticket.status === 'partially_refunded') &&
          refundable.length > 0 && (
            <>
              {!refunding ? (
                <Button variant="ghost" onClick={() => setRefunding(true)}>
                  Rembourser…
                </Button>
              ) : (
                <fieldset className="salon-fieldset">
                  <legend>Rembourser</legend>
                  {refundable.map((l) => (
                    <label className="form-check" key={l.id}>
                      <input
                        type="checkbox"
                        checked={refundLines.includes(l.id)}
                        onChange={(e) =>
                          setRefundLines(
                            e.target.checked
                              ? [...refundLines, l.id]
                              : refundLines.filter((x) => x !== l.id),
                          )
                        }
                      />
                      {l.label} — {fcfa(l.net_xaf ?? l.line_total_xaf)} F
                    </label>
                  ))}
                  <div className="form-grid">
                    <label>
                      Rendu par
                      <select
                        value={refundMethod}
                        onChange={(e) => setRefundMethod(e.target.value as PaymentMethod)}
                      >
                        {(Object.keys(methodLabels) as PaymentMethod[]).map((m) => (
                          <option key={m} value={m}>
                            {methodLabels[m]}
                          </option>
                        ))}
                      </select>
                    </label>
                    <label>
                      Motif
                      <input
                        value={reason}
                        maxLength={200}
                        onChange={(e) => setReason(e.target.value)}
                      />
                    </label>
                    {ticket.lines.some(
                      (l) => refundLines.includes(l.id) && l.kind === 'product',
                    ) && (
                      <label className="form-check form-grid__full">
                        <input
                          type="checkbox"
                          checked={restock}
                          onChange={(e) => setRestock(e.target.checked)}
                        />
                        Remettre les produits rendus en stock
                      </label>
                    )}
                  </div>
                  <div className="row-actions">
                    <Button
                      variant="danger"
                      solid
                      busy={action.busy}
                      disabled={refundLines.length === 0 || reason.trim().length < 3}
                      onClick={() => void refund()}
                    >
                      {refundLines.length === 0
                        ? 'Cochez les lignes à rembourser'
                        : `Rembourser ${fcfa(refundTotal)} FCFA`}
                    </Button>
                    <Button variant="ghost" onClick={() => setRefunding(false)}>
                      Ne pas rembourser
                    </Button>
                  </div>
                </fieldset>
              )}
            </>
          )}

        <ActionMessage message={action.message} isError={action.isError} />
        <div className="dialog__actions">
          {open && ticket.paid_xaf === 0 && (
            <Button
              variant="ghost"
              busy={action.busy}
              onClick={() =>
                void action
                  .run(() => salonApi.cancelTicket(shopId, ticket.id), 'Note annulée.')
                  .then(apply)
              }
            >
              Annuler la note
            </Button>
          )}
          <Button variant="secondary" onClick={onClose}>
            Fermer
          </Button>
        </div>
      </div>
    </Dialog>
  )
}
