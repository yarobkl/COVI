import { useId, useState } from 'react'
import {
  CardIcon,
  CashIcon,
  CheckIcon,
  ChevronLeftIcon,
  CloudOffIcon,
  MobileMoneyIcon,
  PlusIcon,
  TransferIcon,
} from '../../components/icons'
import {
  Amount,
  AmountInput,
  Button,
  cx,
  Field,
  IconButton,
  Ledger,
  LedgerRow,
  Notice,
  NumPad,
  Segmented,
  Stepper,
  type SegmentedOption,
} from '../../components/ui'
import { fcfa, money, parseAmount, plural } from '../../lib/format'
import type { Product } from '../../lib/types'
import {
  cartCount,
  cartTotal,
  displayedPrice,
  lineDiscount,
  lineOf,
  maxQuantity,
  removeLine,
  setPrice,
  setQuantity,
  type Cart,
  type CartLine,
  type SoldSale,
} from './cart'
import { cartSignature, operationFor, submitCart, type CartOperation } from './cartSubmit'
import { cashChange, cashSuggestions, isFarBelow } from './saleMath'

const payments: readonly SegmentedOption<string>[] = [
  { value: 'Espèces', label: 'Espèces', icon: <CashIcon /> },
  { value: 'Mobile Money', label: 'Mobile Money', icon: <MobileMoneyIcon /> },
  { value: 'Carte', label: 'Carte', icon: <CardIcon /> },
  { value: 'Virement', label: 'Virement', icon: <TransferIcon /> },
  { value: 'Autre', label: 'Autre' },
]

type Mode = { kind: 'cart' } | { kind: 'price'; productId: string } | { kind: 'check' }

/** Why the last « Valider » did not go through, for the cart it was pressed on. */
type Problem = {
  tone: 'waiting' | 'refused'
  message: string
  productId?: string
  signature: string
}

export const EMPTY_CART_TEXT = 'Le panier est vide. Touchez un article pour l’ajouter.'

/**
 * « La vente »: the cart. Each article with how many and the price agreed with the customer
 * (price pad), how she pays, the change for cash, then « Valider la vente · 54 000 ». A cart of
 * one article is the sale of one article, as before.
 */
export function SaleForm({
  shopId,
  lines,
  onLinesChange,
  codeOf,
  keyboard,
  onBack,
  onAddMore,
  operation,
  onOperation,
  onSold,
}: {
  shopId: string
  lines: Cart
  onLinesChange: (lines: Cart) => void
  /** Arrival code (BAL-003…) of an article, when known. */
  codeOf: (product: Product) => string | undefined
  /** Physical keyboard for the price pad (computer). */
  keyboard: boolean
  /** Back to the articles (phone sheet). */
  onBack?: () => void
  /** « Ajouter un autre article »: back to the articles (phone) or to the search (computer). */
  onAddMore: () => void
  /**
   * The operation id of this cart, kept by the page for every retry of the same cart, even when
   * the phone sheet is closed and opened again (docs/contrat-panier.md). Forgotten after a sale.
   */
  operation: CartOperation | null
  onOperation: (operation: CartOperation) => void
  onSold: (sale: SoldSale) => void
}) {
  const [mode, setMode] = useState<Mode>({ kind: 'cart' })
  const [draft, setDraft] = useState<number | null>(null)
  const [payment, setPayment] = useState<string | null>(null)
  const [received, setReceived] = useState<number | null>(null)
  const [busy, setBusy] = useState(false)
  const [problem, setProblem] = useState<Problem | null>(null)
  const titleId = useId()

  const total = cartTotal(lines)
  const count = cartCount(lines)
  const cash = payment === 'Espèces'
  const change = cash ? cashChange(total, received) : { kind: 'none' as const }
  const farBelow = lines.filter((l) => isFarBelow(displayedPrice(l.product), l.price))
  // A message about another cart (changed since) is no longer true: it is not shown.
  const shown =
    problem && payment && problem.signature === cartSignature(lines, payment) ? problem : null
  const priced = mode.kind === 'price' ? lineOf(lines, mode.productId) : undefined

  // The validate button says why it waits.
  const blockedLabel = lines.some((l) => !(l.price > 0))
    ? 'Indiquez le prix auquel vous vendez'
    : !payment
      ? 'Choisissez comment la cliente paie'
      : ''

  async function submit() {
    if (!payment || blockedLabel) return
    const op = operationFor(operation, lines, payment)
    onOperation(op)
    setBusy(true)
    setProblem(null)
    const result = await submitCart({ shopId, lines, paymentLabel: payment, operationId: op.id })
    setBusy(false)
    setMode({ kind: 'cart' })
    if (result.status === 'sold') {
      navigator.vibrate?.(12)
      onSold({
        lines: lines.map(({ product, quantity, price }) => ({ product, quantity, price })),
        payment,
        received: cash ? received : null,
        offline: result.offline,
        at: new Date(),
      })
      return
    }
    setProblem({
      tone: result.status,
      message: result.message,
      productId: result.status === 'refused' ? result.productId : undefined,
      signature: op.signature,
    })
  }

  const validate = () => {
    if (farBelow.length) setMode({ kind: 'check' })
    else void submit()
  }

  const heading = (
    <div className="sale-form__head">
      {mode.kind !== 'cart' ? (
        <IconButton
          variant="tactile"
          label="Revenir au panier"
          onClick={() => setMode({ kind: 'cart' })}
        >
          <ChevronLeftIcon />
        </IconButton>
      ) : (
        onBack && (
          <IconButton variant="tactile" label="Revenir aux articles" onClick={onBack}>
            <ChevronLeftIcon />
          </IconButton>
        )
      )}
      <div>
        <h2 className="sale-form__title" id={titleId}>
          {priced ? priced.product.name : 'La vente'}
        </h2>
        {mode.kind === 'cart' && lines.length > 0 && (
          <p className="sale-form__hint">Le prix se discute : touchez-le pour le changer.</p>
        )}
      </div>
    </div>
  )

  if (priced)
    return (
      <section className="sale-form" aria-labelledby={titleId}>
        {heading}
        <NumPad
          value={draft}
          onChange={setDraft}
          reference={displayedPrice(priced.product)}
          keyboard={keyboard}
          onConfirm={() => {
            if (draft !== null) onLinesChange(setPrice(lines, priced.product.id, draft))
            setMode({ kind: 'cart' })
          }}
        />
      </section>
    )

  if (mode.kind === 'check' && farBelow.length)
    return (
      <section className="sale-form" aria-labelledby={titleId}>
        {heading}
        <div className="sale-form__check" role="alertdialog" aria-labelledby={`${titleId}-q`}>
          {farBelow.length === 1 ? (
            <p className="sale-form__question" id={`${titleId}-q`}>
              {money(farBelow[0].price)} au lieu de {fcfa(displayedPrice(farBelow[0].product))}
              {lines.length > 1 && ` pour ${farBelow[0].product.name}`}, c’est bien ça ?
            </p>
          ) : (
            <>
              <p className="sale-form__question" id={`${titleId}-q`}>
                Ces prix sont bien ceux convenus ?
              </p>
              <ul className="sale-form__checklist">
                {farBelow.map((l) => (
                  <li key={l.product.id}>
                    {l.product.name} : {money(l.price)} au lieu de {fcfa(displayedPrice(l.product))}
                  </li>
                ))}
              </ul>
            </>
          )}
          <p className="muted">
            {farBelow.length === 1
              ? 'Le prix fait est à moins de la moitié du prix affiché.'
              : 'Ils sont à moins de la moitié du prix affiché.'}
          </p>
          <Button write variant="sale" size="xl" block busy={busy} onClick={() => void submit()}>
            Oui, valider
          </Button>
          <Button variant="secondary" size="lg" block onClick={() => setMode({ kind: 'cart' })}>
            Corriger
          </Button>
        </div>
      </section>
    )

  if (!lines.length)
    return (
      <section className="sale-form" aria-labelledby={titleId}>
        {heading}
        <p className="muted sale-form__empty">{EMPTY_CART_TEXT}</p>
        {onBack && (
          <Button variant="secondary" size="lg" block onClick={onBack}>
            Revenir aux articles
          </Button>
        )}
      </section>
    )

  return (
    <section className="sale-form" aria-labelledby={titleId}>
      {heading}
      <div className="sale-form__body">
        <ul className="sale-lines" aria-label="Le panier">
          {lines.map((line) => (
            <SaleLineRow
              key={line.product.id}
              line={line}
              arrivalCode={codeOf(line.product)}
              problem={shown?.productId === line.product.id}
              onQuantity={(q) => onLinesChange(setQuantity(lines, line.product.id, q))}
              onPrice={() => {
                setDraft(line.price)
                setMode({ kind: 'price', productId: line.product.id })
              }}
              onRemove={() => onLinesChange(removeLine(lines, line.product.id))}
            />
          ))}
        </ul>
        <Button variant="ghost" className="sale-form__more" icon={<PlusIcon />} onClick={onAddMore}>
          Ajouter un autre article
        </Button>
        <Ledger>
          <LedgerRow
            variant="total"
            label={totalLabel(lines, count)}
            value={<Amount value={total} unit />}
          />
        </Ledger>

        <Segmented
          legend="Payé en"
          options={payments}
          value={payment}
          onChange={setPayment}
          sale
          className="sale-pay"
        />

        {cash && (
          <div className="sale-cash">
            <Field label="Reçu" optional>
              {(control) => (
                <AmountInput
                  {...control}
                  placeholder="0"
                  value={received === null ? '' : fcfa(received)}
                  onChange={(e) => setReceived(parseAmount(e.target.value))}
                />
              )}
            </Field>
            <div className="sale-cash__notes" role="group" aria-label="Billets reçus">
              {cashSuggestions(total).map((amount, i) => (
                <Button
                  key={amount}
                  variant="tactile"
                  aria-pressed={received === amount}
                  onClick={() => setReceived(amount)}
                >
                  {i === 0 ? 'Compte juste' : <span className="figures">{fcfa(amount)}</span>}
                </Button>
              ))}
            </div>
            <p className={`sale-cash__change sale-cash__change--${change.kind}`} aria-live="polite">
              {change.kind === 'change' && (
                <>
                  À rendre : <Amount value={change.amount} size="lg" unit />
                </>
              )}
              {change.kind === 'short' && (
                <>
                  Il manque <span className="figures">{fcfa(change.amount)}</span>&nbsp;FCFA.
                </>
              )}
              {change.kind === 'exact' && 'Le compte est juste, rien à rendre.'}
              {change.kind === 'none' &&
                'Tapez la somme reçue : la monnaie se calcule toute seule.'}
            </p>
          </div>
        )}

        {shown?.tone === 'waiting' && (
          <Notice icon={CloudOffIcon} title="Panier gardé à l’écran.">
            <p>{shown.message}</p>
          </Notice>
        )}
        {shown?.tone === 'refused' && (
          <Notice tone="danger" title="Vente pas enregistrée.">
            <p>{shown.message}</p>
          </Notice>
        )}
      </div>
      <div className="sale-form__foot">
        <Button
          write
          variant="sale"
          size="xl"
          block
          busy={busy}
          disabled={Boolean(blockedLabel)}
          icon={blockedLabel ? undefined : <CheckIcon />}
          onClick={validate}
        >
          {blockedLabel || (
            <>
              Valider la vente · <span className="amount">{fcfa(total)}</span>
            </>
          )}
        </Button>
      </div>
    </section>
  )
}

/** « Total », « Total (2 × 18 000) » for one article, « Total (3 articles) » for a cart. */
function totalLabel(lines: Cart, count: number) {
  if (lines.length > 1) return `Total (${plural(count, 'article')})`
  const [line] = lines
  return line.quantity > 1 ? `Total (${line.quantity} × ${fcfa(line.price)})` : 'Total'
}

/** One article of the cart: name and stock, how many, the agreed price, « Retirer ». */
function SaleLineRow({
  line,
  arrivalCode,
  problem,
  onQuantity,
  onPrice,
  onRemove,
}: {
  line: CartLine
  arrivalCode?: string
  /** The server refused the sale because of this article. */
  problem: boolean
  onQuantity: (quantity: number) => void
  onPrice: () => void
  onRemove: () => void
}) {
  const { product, quantity, price } = line
  const displayed = displayedPrice(product)
  const available = Math.max(1, maxQuantity(product))
  const discount = lineDiscount(line)
  return (
    <li className={cx('sale-line', problem && 'sale-line--problem')}>
      <div className="sale-line__top">
        <div className="sale-line__what">
          <p className="sale-line__name">{product.name}</p>
          <p className="sale-line__meta">
            {product.is_unique_piece
              ? 'Pièce unique'
              : available > 1
                ? `Restent ${available}`
                : 'Plus que 1'}
            {arrivalCode && ` · ${arrivalCode}`}
          </p>
        </div>
        <Button
          variant="ghost"
          className="sale-line__remove"
          aria-label={`Retirer ${product.name} du panier`}
          onClick={onRemove}
        >
          Retirer
        </Button>
      </div>
      <div className="sale-line__deal">
        {!product.is_unique_piece && available > 1 ? (
          <Stepper value={quantity} max={available} onChange={onQuantity} itemName={product.name} />
        ) : (
          <span className="sale-line__one">1 pièce</span>
        )}
        <div className="sale-price">
          <div className="sale-price__ref">
            {discount > 0 ? (
              <>
                <span>
                  Affiché <Amount value={displayed} size="sm" struck />
                </span>
                <span className="sale-price__discount">
                  <span className="figures">{fcfa(discount)}</span>&nbsp;FCFA de remise
                </span>
              </>
            ) : price > displayed ? (
              <span>
                Affiché <span className="figures">{fcfa(displayed)}</span>
              </span>
            ) : (
              <span>Au prix affiché</span>
            )}
          </div>
          <button
            type="button"
            className={price !== displayed ? 'price-key price-key--changed' : 'price-key'}
            aria-label={`${product.name} vendu à ${money(price)}${quantity > 1 ? ' la pièce' : ''}. Changer le prix`}
            onClick={onPrice}
          >
            {fcfa(price)}
          </button>
        </div>
      </div>
    </li>
  )
}
