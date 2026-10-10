import { useId, useState } from 'react'
import {
  CardIcon,
  CashIcon,
  CheckIcon,
  ChevronLeftIcon,
  MobileMoneyIcon,
  TransferIcon,
} from '../../components/icons'
import {
  Amount,
  AmountInput,
  Button,
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
import { fcfa, money, parseAmount } from '../../lib/format'
import { resilientSale } from '../../lib/offline'
import type { Product } from '../../lib/types'
import { saleErrorMessage } from './saleErrors'
import { cashChange, cashSuggestions, discountOf, isFarBelow } from './saleMath'

/** A validated sale, for the « Vendu. » screen. */
export type SoldSale = {
  product: Product
  quantity: number
  price: number
  payment: string
  /** Cash handed over (display only, never stored). */
  received: number | null
  /** Kept on the device, to be sent when the network comes back. */
  offline: boolean
  at: Date
}

const payments: readonly SegmentedOption<string>[] = [
  { value: 'Espèces', label: 'Espèces', icon: <CashIcon /> },
  { value: 'Mobile Money', label: 'Mobile Money', icon: <MobileMoneyIcon /> },
  { value: 'Carte', label: 'Carte', icon: <CardIcon /> },
  { value: 'Virement', label: 'Virement', icon: <TransferIcon /> },
  { value: 'Autre', label: 'Autre' },
]

type Mode = 'form' | 'price' | 'check'

/**
 * « La vente » for one article: how many, the price agreed with the customer (price pad), how
 * she pays, the change for cash, then « Valider la vente · 18 000 ».
 */
export function SaleForm({
  shopId,
  product,
  arrivalCode,
  keyboard,
  onBack,
  onSold,
}: {
  shopId: string
  product: Product
  arrivalCode?: string
  /** Physical keyboard for the price pad (computer). */
  keyboard: boolean
  /** Back to the articles (phone sheet). */
  onBack?: () => void
  onSold: (sale: SoldSale) => void
}) {
  const displayed = Number(product.initial_sale_price)
  const available = Math.max(1, Number(product.quantity_on_hand))
  const [mode, setMode] = useState<Mode>('form')
  const [quantity, setQuantity] = useState(1)
  const [price, setPrice] = useState<number | null>(displayed)
  const [draft, setDraft] = useState<number | null>(displayed)
  const [payment, setPayment] = useState<string | null>(null)
  const [received, setReceived] = useState<number | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const titleId = useId()

  const unitPrice = price ?? 0
  const total = unitPrice * quantity
  const discount = discountOf(displayed, unitPrice, quantity)
  const cash = payment === 'Espèces'
  const change = cash ? cashChange(total, received) : { kind: 'none' as const }

  const blocked = !price ? 'Indiquez le prix auquel vous vendez' : !payment
  const blockedLabel =
    typeof blocked === 'string' ? blocked : blocked ? 'Choisissez comment la cliente paie' : ''

  async function submit() {
    if (!price || !payment) return
    setBusy(true)
    setError('')
    try {
      const result = await resilientSale({
        shopId,
        productId: product.id,
        quantity,
        soldUnitPrice: price,
        paymentLabel: payment,
      })
      navigator.vibrate?.(12)
      onSold({
        product,
        quantity,
        price,
        payment,
        received: cash ? received : null,
        offline: result.offline,
        at: new Date(),
      })
    } catch (e) {
      setError(saleErrorMessage(e, { remaining: Number(product.quantity_on_hand) }))
      setMode('form')
    } finally {
      setBusy(false)
    }
  }

  const validate = () => {
    if (price && isFarBelow(displayed, price)) setMode('check')
    else void submit()
  }

  const heading = (
    <div className="sale-form__head">
      {mode !== 'form' ? (
        <IconButton variant="tactile" label="Revenir à la vente" onClick={() => setMode('form')}>
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
          {mode === 'price' ? product.name : 'La vente'}
        </h2>
        {mode === 'form' && (
          <p className="sale-form__hint">Le prix se discute : touchez-le pour le changer.</p>
        )}
      </div>
    </div>
  )

  if (mode === 'price')
    return (
      <section className="sale-form" aria-labelledby={titleId}>
        {heading}
        <NumPad
          value={draft}
          onChange={setDraft}
          reference={displayed}
          keyboard={keyboard}
          onConfirm={() => {
            setPrice(draft)
            setMode('form')
          }}
        />
      </section>
    )

  if (mode === 'check')
    return (
      <section className="sale-form" aria-labelledby={titleId}>
        {heading}
        <div className="sale-form__check" role="alertdialog" aria-labelledby={`${titleId}-q`}>
          <p className="sale-form__question" id={`${titleId}-q`}>
            {money(unitPrice)} au lieu de {fcfa(displayed)}, c’est bien ça ?
          </p>
          <p className="muted">Le prix fait est à moins de la moitié du prix affiché.</p>
          <Button variant="sale" size="xl" block busy={busy} onClick={() => void submit()}>
            Oui, valider
          </Button>
          <Button variant="secondary" size="lg" block onClick={() => setMode('form')}>
            Corriger
          </Button>
        </div>
      </section>
    )

  return (
    <section className="sale-form" aria-labelledby={titleId}>
      {heading}
      <div className="sale-form__body">
        <div className="sale-line">
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
          {!product.is_unique_piece && available > 1 && (
            <Stepper
              value={quantity}
              max={available}
              onChange={setQuantity}
              itemName={product.name}
            />
          )}
        </div>
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
            ) : unitPrice > displayed ? (
              <span>
                Affiché <span className="figures">{fcfa(displayed)}</span>
              </span>
            ) : (
              <span>Au prix affiché</span>
            )}
          </div>
          <button
            type="button"
            className={unitPrice !== displayed ? 'price-key price-key--changed' : 'price-key'}
            aria-label={`Vendu à ${money(unitPrice)}${quantity > 1 ? ' la pièce' : ''}. Changer le prix`}
            onClick={() => {
              setDraft(price)
              setMode('price')
            }}
          >
            {fcfa(unitPrice)}
          </button>
        </div>
        <Ledger>
          <LedgerRow
            variant="total"
            label={quantity > 1 ? `Total (${quantity} × ${fcfa(unitPrice)})` : 'Total'}
            value={<Amount value={total} unit />}
          />
        </Ledger>

        <Segmented
          legend="Payé en"
          options={payments}
          value={payment}
          onChange={(value) => {
            setPayment(value)
            setError('')
          }}
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

        {error && (
          <Notice tone="danger" title="Vente pas enregistrée.">
            <p>{error}</p>
          </Notice>
        )}
      </div>
      <div className="sale-form__foot">
        <Button
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
