import { useEffect, useId, useRef, useState, type FormEvent } from 'react'
import { CloseIcon } from '../../components/icons'
import { CheckField } from '../../components/ui/CheckField'
import {
  AmountInput,
  Button,
  Dialog,
  Field,
  IconButton,
  Input,
  Notice,
  Segmented,
} from '../../components/ui'
import { localDay } from '../../lib/dates'
import { fcfa } from '../../lib/format'
import { createArrival } from '../../lib/operations'
import type { Arrival, ArrivalKind } from '../../lib/types'
import { nextArrivalCode } from './arrivalMath'
import {
  arrivalSaveError,
  balloonFromValues,
  isCodeTaken,
  orderFromValues,
  orderTotal,
  type BalloonErrors,
  type BalloonValues,
  type OrderErrors,
  type OrderValues,
} from './arrivalForms'
import { CountryField } from './CountryField'
import { typedAmount } from '../stock/productForm'

const kinds = [
  { value: 'supplier_order', label: 'Une commande chez un fournisseur' },
  { value: 'balloon', label: 'Un ballon (friperie)' },
] as const

function ArrivalForm({
  shopId,
  imposedKind,
  codes,
  titleId,
  onClose,
  onSaved,
}: {
  shopId: string
  imposedKind?: ArrivalKind
  codes: readonly string[]
  titleId: string
  onClose: () => void
  onSaved: (arrival: Arrival) => void
}) {
  const [kind, setKind] = useState<ArrivalKind>(imposedKind ?? 'supplier_order')
  const [order, setOrder] = useState<OrderValues>(() => ({
    country: '',
    supplier: '',
    orderDate: localDay(new Date()),
    goods: '',
    transport: '',
    customs: '',
  }))
  const [balloon, setBalloon] = useState<BalloonValues>({ place: '', price: '', received: true })
  const [errors, setErrors] = useState<OrderErrors & BalloonErrors>({})
  const [failure, setFailure] = useState('')
  const [busy, setBusy] = useState(false)
  const form = useRef<HTMLFormElement>(null)
  const forget = (key: string) => {
    if (key in errors)
      setErrors((e) => {
        const next = { ...e }
        delete next[key as keyof typeof e]
        return next
      })
  }
  const setO = (key: keyof OrderValues, value: string) => {
    setOrder((v) => ({ ...v, [key]: value }))
    forget(key)
  }

  useEffect(() => {
    form.current?.querySelector<HTMLElement>('[aria-invalid="true"]')?.focus()
  }, [errors])

  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    if (busy) return
    const today = localDay(new Date())
    const build = (code: string) =>
      kind === 'balloon'
        ? balloonFromValues(balloon, code, today)
        : orderFromValues(order, code, today)
    const first = build(nextArrivalCode(kind, codes))
    if (first.errors) {
      setErrors(first.errors)
      return
    }
    setErrors({})
    setFailure('')
    setBusy(true)
    try {
      // A readable code (BAL-004); if another device took it meanwhile, the next one.
      for (let skip = 0; ; skip++) {
        const { input } = build(nextArrivalCode(kind, codes, skip))
        if (!input) return
        try {
          onSaved(await createArrival(shopId, input))
          return
        } catch (err) {
          if (!isCodeTaken(err) || skip >= 4) throw err
        }
      }
    } catch (err) {
      setFailure(arrivalSaveError(err))
    } finally {
      setBusy(false)
    }
  }

  const total = orderTotal(order)
  const title = imposedKind
    ? imposedKind === 'balloon'
      ? 'Nouveau ballon'
      : 'Nouvelle commande'
    : 'Nouvel arrivage'

  return (
    <form className="dialog__body arrival-form" ref={form} onSubmit={submit} noValidate>
      <div className="product-form__head">
        <h2 className="dialog__title" id={titleId}>
          {title}
        </h2>
        <IconButton label="Fermer sans enregistrer" onClick={onClose}>
          <CloseIcon />
        </IconButton>
      </div>

      {!imposedKind && (
        <Segmented
          legend="C’est…"
          options={kinds}
          value={kind}
          onChange={(k) => {
            setKind(k)
            setErrors({})
          }}
          className="arrival-form__kind"
        />
      )}

      {kind === 'supplier_order' ? (
        <>
          <CountryField
            label="Pays d’origine"
            kind="order"
            value={order.country}
            onChange={(v) => setO('country', v)}
            placeholder="Ex. Chine, Inde, Turquie"
            error={errors.country}
          />
          <Field label="Fournisseur" error={errors.supplier}>
            {(control) => (
              <Input
                {...control}
                value={order.supplier}
                onChange={(e) => setO('supplier', e.target.value)}
                placeholder="Nom ou contact WhatsApp"
                autoComplete="off"
                maxLength={120}
              />
            )}
          </Field>
          <Field label="Commandé le" optional error={errors.orderDate}>
            {(control) => (
              <Input
                {...control}
                className="arrival-form__date"
                type="date"
                max={localDay(new Date())}
                value={order.orderDate}
                onChange={(e) => setO('orderDate', e.target.value)}
              />
            )}
          </Field>
          <Field label="Prix de la marchandise (FCFA)" error={errors.goods}>
            {(control) => (
              <AmountInput
                {...control}
                value={order.goods}
                onChange={(e) => setO('goods', typedAmount(e.target.value))}
                placeholder="300 000"
              />
            )}
          </Field>
          <div className="product-form__pair">
            <Field label="Transport / fret (FCFA)" optional>
              {(control) => (
                <AmountInput
                  {...control}
                  value={order.transport}
                  onChange={(e) => setO('transport', typedAmount(e.target.value))}
                  placeholder="0"
                />
              )}
            </Field>
            <Field label="Douane et dédouanement (FCFA)" optional>
              {(control) => (
                <AmountInput
                  {...control}
                  value={order.customs}
                  onChange={(e) => setO('customs', typedAmount(e.target.value))}
                  placeholder="0"
                />
              )}
            </Field>
          </div>
          <p className="arrival-form__total" aria-live="polite">
            <span>Payé en tout</span>
            <span className="ledger__dots" aria-hidden="true" />
            <strong className="amount amount--md">
              {fcfa(total)}
              <span className="amount__unit">FCFA</span>
            </strong>
          </p>
          <p className="muted">Ensuite, indiquez quand c’est commandé, en route, puis reçu.</p>
        </>
      ) : (
        <>
          <CountryField
            label="Acheté où ?"
            kind="balloon"
            optional
            value={balloon.place}
            onChange={(place) => setBalloon((v) => ({ ...v, place }))}
            placeholder="Ex. Brazzaville, Belgique"
          />
          <Field
            label="Prix payé pour le ballon (FCFA)"
            error={errors.price}
            hint="Tout compris. On ne divise pas ce prix par pièce : on suit ce que le ballon vous rapporte."
          >
            {(control) => (
              <AmountInput
                {...control}
                value={balloon.price}
                onChange={(e) => {
                  const price = typedAmount(e.target.value)
                  setBalloon((v) => ({ ...v, price }))
                  forget('price')
                }}
                placeholder="250 000"
              />
            )}
          </Field>
          <CheckField
            label="Je l’ai déjà reçu"
            checked={balloon.received}
            onChange={(received) => setBalloon((v) => ({ ...v, received }))}
            hint={
              balloon.received
                ? 'Il est noté ouvert aujourd’hui : vous pourrez ajouter ses pièces tout de suite.'
                : 'Il est noté payé. Vous indiquerez quand il arrive.'
            }
          />
        </>
      )}

      {failure && (
        <Notice tone="danger">
          <p>{failure}</p>
        </Notice>
      )}

      <div className="dialog__actions">
        <Button variant="ghost" onClick={onClose}>
          Annuler
        </Button>
        <Button variant="primary" type="submit" busy={busy}>
          {kind === 'balloon' ? 'Enregistrer le ballon' : 'Enregistrer la commande'}
        </Button>
      </div>
    </form>
  )
}

/** « Nouvel arrivage » (or « Nouvelle commande », « Nouveau ballon ») in a sheet. */
export function ArrivalFormSheet({
  open,
  onClose,
  shopId,
  kind,
  codes,
  onSaved,
}: {
  open: boolean
  onClose: () => void
  shopId: string
  /** Imposed by the filter (Commandes, Ballons); chosen in the form otherwise. */
  kind?: ArrivalKind
  /** Codes already used, for the next readable one. */
  codes: readonly string[]
  onSaved: (arrival: Arrival) => void
}) {
  const titleId = useId()
  return (
    <Dialog open={open} onClose={onClose} labelledBy={titleId} sheet className="product-sheet">
      <ArrivalForm
        shopId={shopId}
        imposedKind={kind}
        codes={codes}
        titleId={titleId}
        onClose={onClose}
        onSaved={onSaved}
      />
    </Dialog>
  )
}
