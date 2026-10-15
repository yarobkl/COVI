import { useEffect, useId, useState, type FormEvent } from 'react'
import { Button, Dialog, Ledger, LedgerRow, Notice, Segmented, Stepper } from '../../components/ui'
import { whenLabel } from '../../lib/dates'
import { money } from '../../lib/format'
import {
  adjustProductStock,
  listStockMovements,
  setProductArchived,
  stockErrorMessage,
  stockReasonLabel,
  stockReasons,
  updateProductDetails,
  type StockMovement,
  type StockReason,
} from '../../lib/stock'
import type { Product } from '../../lib/types'

const statusText = { active: 'en vente', sold: 'épuisé', archived: 'retiré de la vente' } as const

/**
 * « Modifier le produit » : corriger le stock avec un motif (réassort, perte, vol, erreur de
 * comptage), changer la fiche (nom, prix…), retirer le produit de la vente ou l'y remettre.
 * Chaque correction de stock est enregistrée et visible dans l'historique et la cloche.
 */
export function ProductEditor({
  product,
  onClose,
  onChanged,
}: {
  product: Product
  onClose: () => void
  /** Après chaque enregistrement : la page recharge le stock. */
  onChanged: (message: string) => void
}) {
  const titleId = useId()
  const [quantity, setQuantity] = useState(product.quantity_on_hand)
  const [reason, setReason] = useState<StockReason | null>(null)
  const [note, setNote] = useState('')
  const [movements, setMovements] = useState<StockMovement[] | null>(null)
  const [busy, setBusy] = useState<'stock' | 'details' | 'archive' | null>(null)
  const [error, setError] = useState('')
  const [done, setDone] = useState('')

  useEffect(() => {
    let active = true
    listStockMovements(product.id).then(
      (rows) => active && setMovements(rows),
      () => active && setMovements([]),
    )
    return () => {
      active = false
    }
  }, [product.id])

  const run = async (kind: 'stock' | 'details' | 'archive', action: () => Promise<string>) => {
    setBusy(kind)
    setError('')
    setDone('')
    try {
      const message = await action()
      setDone(message)
      onChanged(message)
    } catch (e) {
      setError(stockErrorMessage(e))
    } finally {
      setBusy(null)
    }
  }

  const delta = quantity - product.quantity_on_hand
  const saveStock = () =>
    run('stock', async () => {
      if (!reason) throw new Error('reason')
      await adjustProductStock(product.id, quantity, reason, note)
      setMovements(await listStockMovements(product.id).catch(() => movements))
      setNote('')
      setReason(null)
      return `Stock de ${product.name} : ${product.quantity_on_hand} → ${quantity}.`
    })

  const saveDetails = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    const f = new FormData(event.currentTarget)
    const text = (key: string) => String(f.get(key) ?? '').trim() || null
    const name = text('name')
    const price = Number(String(f.get('price') ?? '').replace(/\s/g, ''))
    if (!name) return setError('Le nom du produit est obligatoire.')
    if (!Number.isFinite(price) || price < 0) return setError('Indiquez un prix valide.')
    void run('details', async () => {
      await updateProductDetails(product.id, {
        name,
        category: text('category'),
        brand: text('brand'),
        size: text('size'),
        initial_sale_price: Math.round(price),
      })
      return 'Fiche du produit enregistrée.'
    })
  }

  const archived = product.status === 'archived'

  return (
    <Dialog open onClose={() => !busy && onClose()} labelledBy={titleId} sheet>
      <div className="dialog__body product-editor">
        <h2 className="dialog__title" id={titleId}>
          {product.name}
        </h2>
        <p className="muted">
          {product.quantity_on_hand} en stock · {statusText[product.status]} ·{' '}
          {money(Number(product.initial_sale_price))}
        </p>
        {error && (
          <Notice tone="danger">
            <p>{error}</p>
          </Notice>
        )}
        {done && (
          <Notice tone="success">
            <p>{done}</p>
          </Notice>
        )}

        <section className="product-editor__part" aria-labelledby={`${titleId}-stock`}>
          <h3 className="section-title" id={`${titleId}-stock`}>
            Corriger le stock
          </h3>
          <div className="product-editor__qty">
            <span>Nouvelle quantité</span>
            <Stepper
              value={quantity}
              min={0}
              max={product.is_unique_piece ? 1 : 100000}
              onChange={setQuantity}
              itemName={product.name}
            />
            {delta !== 0 && (
              <span className={'figures ' + (delta < 0 ? 'amount-out' : '')}>
                {delta > 0 ? '+' : '−'} {Math.abs(delta)}
              </span>
            )}
          </div>
          <Segmented
            legend="Motif"
            value={reason}
            onChange={setReason}
            options={stockReasons.map((r) => ({ value: r.value, label: r.label }))}
          />
          <label className="field">
            <span className="field__label">
              Note <span className="field__optional">(facultatif)</span>
            </span>
            <input
              className="input"
              value={note}
              maxLength={200}
              placeholder="Ex. : carton du 15 octobre"
              onChange={(e) => setNote(e.target.value)}
            />
          </label>
          <Button
            variant="primary"
            busy={busy === 'stock'}
            disabled={delta === 0 || !reason || busy !== null}
            onClick={() => void saveStock()}
          >
            {delta === 0
              ? 'Changez la quantité'
              : !reason
                ? 'Choisissez un motif'
                : 'Enregistrer la correction'}
          </Button>
        </section>

        <section className="product-editor__part" aria-labelledby={`${titleId}-details`}>
          <h3 className="section-title" id={`${titleId}-details`}>
            Fiche du produit
          </h3>
          <form className="form-grid" onSubmit={saveDetails}>
            <label>
              Nom
              <input name="name" defaultValue={product.name} required maxLength={120} />
            </label>
            <label>
              Prix de vente
              <input
                name="price"
                inputMode="numeric"
                defaultValue={Number(product.initial_sale_price)}
                required
              />
            </label>
            <label>
              Catégorie
              <input name="category" defaultValue={product.category ?? ''} maxLength={60} />
            </label>
            <label>
              Marque
              <input name="brand" defaultValue={product.brand ?? ''} maxLength={60} />
            </label>
            <label>
              Taille
              <input name="size" defaultValue={product.size ?? ''} maxLength={30} />
            </label>
            <div className="form-grid__actions">
              <Button variant="secondary" type="submit" busy={busy === 'details'}>
                Enregistrer la fiche
              </Button>
            </div>
          </form>
        </section>

        <section className="product-editor__part" aria-labelledby={`${titleId}-history`}>
          <h3 className="section-title" id={`${titleId}-history`}>
            Corrections de stock
          </h3>
          {movements === null ? (
            <p className="muted">Chargement…</p>
          ) : movements.length === 0 ? (
            <p className="muted">Aucune correction pour ce produit.</p>
          ) : (
            <Ledger label="Corrections de stock">
              {movements.map((m) => (
                <LedgerRow
                  key={m.id}
                  label={stockReasonLabel(m.reason)}
                  meta={[whenLabel(new Date(m.created_at)), m.note].filter(Boolean).join(' · ')}
                  value={
                    <span className="figures">
                      {m.quantity_before} → {m.quantity_after}
                    </span>
                  }
                />
              ))}
            </Ledger>
          )}
        </section>

        <div className="dialog__actions">
          <Button
            variant={archived ? 'secondary' : 'danger'}
            busy={busy === 'archive'}
            disabled={busy !== null}
            onClick={() =>
              void run('archive', async () => {
                await setProductArchived(product.id, !archived)
                return archived
                  ? `${product.name} est de nouveau en vente.`
                  : `${product.name} est retiré de la vente.`
              })
            }
          >
            {archived ? 'Remettre en vente' : 'Retirer de la vente'}
          </Button>
          <Button variant="ghost" disabled={busy !== null} onClick={onClose}>
            Fermer
          </Button>
        </div>
      </div>
    </Dialog>
  )
}
