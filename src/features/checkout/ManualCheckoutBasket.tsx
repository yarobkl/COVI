import { useRef, useState, type FormEvent } from 'react'
import { Amount, AmountInput, Button, Field, Ledger, LedgerRow, Sheet, Stepper } from '../../components/ui'
import { fcfa, parseAmount } from '../../lib/format'
import { prepareManualOrderLines, type ManualOrderLineInput } from '../../lib/manualOrder'
import type { CheckoutStockCategory } from '../../lib/checkoutCategoryStock'

type BasketLine = ManualOrderLineInput
type Props = {
  categories: readonly CheckoutStockCategory[]
  onPrepare: (lines: readonly BasketLine[]) => Promise<void>
}

function remainingFor(
  category: CheckoutStockCategory | undefined,
  lines: readonly BasketLine[],
): number {
  if (!category) return 0
  return Math.max(
    0,
    category.available - lines
      .filter((line) => line.categoryId === category.id)
      .reduce((sum, line) => sum + line.quantity, 0),
  )
}

/**
 * Notebook checkout basket: quantities + negotiated prices by category.
 * Pure client preparation. Adding a row does NOT reserve or deduct inventory.
 * This component is NOT mounted on the current application's active sale routes.
 */
export function ManualCheckoutBasket({ categories, onPrepare }: Props) {
  const [lines, setLines] = useState<BasketLine[]>([])
  const [categoryId, setCategoryId] = useState('')
  const [quantity, setQuantity] = useState(1)
  const [priceInput, setPriceInput] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const submitting = useRef(false)

  const selected = categories.find((category) => category.id === categoryId)
  const remaining = remainingFor(selected, lines)
  const amount = parseAmount(priceInput)
  const price = priceInput.trim() && amount !== null ? amount : null
  const total = lines.reduce(
    (sum, line) => sum + line.quantity * line.negotiatedUnitPriceXaf, 0,
  )
  const basketSize = lines.reduce((sum, line) => sum + line.quantity, 0)
  const hasStock = categories.some((category) => category.available > 0)

  function addLine() {
    setError('')
    if (!selected || remaining === 0) {
      setError('Choisissez une catégorie disponible.')
      return
    }
    if (price === null || !Number.isSafeInteger(price) || price < 0) {
      setError('Saisissez le prix négocié en francs CFA.')
      return
    }
    if (quantity > remaining || quantity < 1) {
      setError('La quantité demandée dépasse le stock disponible.')
      return
    }

    try {
      // Category + negotiated price is the row identity. If its exact price
      // returns, consolidate the quantity; a different price stays separate.
      const proposed = prepareManualOrderLines([
        ...lines,
        { categoryId: selected.id, quantity, negotiatedUnitPriceXaf: price },
      ])
      setLines(proposed.lines.map((line) => ({
        categoryId: line.categoryId,
        quantity: line.quantity,
        negotiatedUnitPriceXaf: line.unitPriceXaf,
      })))
      setCategoryId('')
      setQuantity(1)
      setPriceInput('')
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Ligne non ajoutée.')
    }
  }

  function changeQuantity(index: number, newQuantity: number) {
    setError('')
    setLines((previous) => previous.map((line, i) =>
      i === index ? { ...line, quantity: newQuantity } : line,
    ))
  }

  function removeLine(index: number) {
    setError('')
    setLines((previous) => previous.filter((_, i) => i !== index))
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (submitting.current) return
    submitting.current = true
    setBusy(true)
    setError('')
    try {
      const prepared = prepareManualOrderLines(lines)
      // The authoritative database rechecks inventory at APPROVAL and PAYMENT.
      await onPrepare(prepared.lines.map((line) => ({
        categoryId: line.categoryId,
        quantity: line.quantity,
        negotiatedUnitPriceXaf: line.unitPriceXaf,
      })))
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Commande non préparée.')
    } finally {
      submitting.current = false
      setBusy(false)
    }
  }

  return (
    <Sheet className="checkout-basket" aria-label="Nouvelle commande manuelle">
      <header className="checkout-basket__head">
        <p className="hand checkout-basket__hand">Une ligne, un prix convenu.</p>
        <h2>Le panier</h2>
        <p className="checkout-basket__intro">
          Notez les vêtements par catégorie. Le prix est celui négocié avec le client.
        </p>
      </header>
      <form onSubmit={(event) => { void submit(event) }} className="checkout-basket__form">
        <fieldset className="checkout-basket__entry" disabled={busy}>
          <legend className="section-title">Ajouter une ligne</legend>
          <div className="checkout-basket__entry-fields">
            <Field label="Catégorie">
              {(props) => (
                <select
                  {...props}
                  className="select"
                  value={categoryId}
                  onChange={(event) => {
                    setCategoryId(event.target.value)
                    setQuantity(1)
                    setError('')
                  }}
                >
                  <option value="">Choisir une catégorie</option>
                  {categories.map((category) => (
                    <option
                      key={category.id}
                      value={category.id}
                      disabled={remainingFor(category, lines) === 0}
                    >
                      {category.label} · {remainingFor(category, lines)} disponible(s)
                    </option>
                  ))}
                </select>
              )}
            </Field>
            <Field label="Prix négocié par pièce" hint="Montant convenu avec le client, en FCFA">
              {(props) => (
                <AmountInput
                  {...props}
                  placeholder="Ex. : 3 500"
                  value={priceInput}
                  onChange={(event) => setPriceInput(
                    parseAmount(event.target.value) === null
                      ? ''
                      : fcfa(parseAmount(event.target.value) ?? 0),
                  )}
                />
              )}
            </Field>
          </div>
          {selected && remaining > 0 && (
            <div className="checkout-basket__quantity">
              <span>Quantité</span>
              <Stepper
                value={Math.min(quantity, remaining)}
                max={remaining}
                onChange={setQuantity}
                itemName={selected.label}
              />
              <span className="field__hint">{remaining} disponibles</span>
            </div>
          )}
          <Button
            variant="tactile"
            block
            onClick={addLine}
            disabled={!selected || remaining < 1 || price === null}
          >
            Ajouter au panier
          </Button>
          {!hasStock && (
            <p className="field__hint">Aucune catégorie disponible : réceptionnez du stock avant de vendre.</p>
          )}
        </fieldset>

        <section className="checkout-basket__summary" aria-label="Lignes du panier">
          <h3 className="section-title">La note</h3>
          {lines.length ? (
            <div className="checkout-basket__lines">
              {lines.map((line, index) => {
                const category = categories.find((item) => item.id === line.categoryId)
                if (!category) return null
                const otherQuantity = lines.reduce((sum, item, i) =>
                  sum + (i !== index && item.categoryId === line.categoryId ? item.quantity : 0), 0)
                const max = Math.max(line.quantity, category.available - otherQuantity)
                return (
                  <div className="checkout-basket__item" key={line.categoryId + ':' + line.negotiatedUnitPriceXaf}>
                    <div className="checkout-basket__item-head">
                      <strong>{category.label}</strong>
                      <span className="figures">{fcfa(line.negotiatedUnitPriceXaf)} FCFA / pièce</span>
                    </div>
                    <div className="checkout-basket__item-actions">
                      <Stepper
                        value={line.quantity}
                        max={max}
                        onChange={(value) => changeQuantity(index, value)}
                        itemName={category.label}
                      />
                      <button
                        type="button"
                        className="btn btn--ghost checkout-basket__remove"
                        onClick={() => removeLine(index)}
                        disabled={busy}
                        aria-label={'Retirer ' + category.label + ' du panier'}
                      >
                        Retirer
                      </button>
                      <Amount value={line.quantity * line.negotiatedUnitPriceXaf} unit />
                    </div>
                  </div>
                )
              })}
            </div>
          ) : (
            <p className="checkout-basket__empty">Le panier est vide. Ajoutez une première ligne.</p>
          )}
          <Ledger label="Total du panier">
            <LedgerRow
              variant="total"
              label={basketSize > 1 ? 'Total · ' + basketSize + ' pièces' : 'Total · ' + basketSize + ' pièce'}
              value={<Amount value={total} size="lg" unit />}
            />
          </Ledger>
        </section>
        {error && <p className="field__error" role="alert">{error}</p>}
        <p className="checkout-confirmation__assurance">
          Préparer la commande ne retire rien du stock. La sortie se fait après la confirmation du paiement reçu.
        </p>
        <Button
          type="submit"
          variant="sale"
          size="lg"
          block
          busy={busy}
          busyLabel="Préparation de la commande…"
          disabled={busy || !lines.length}
        >
          Préparer la commande · <span className="figures">{fcfa(total)} FCFA</span>
        </Button>
      </form>
    </Sheet>
  )
}
