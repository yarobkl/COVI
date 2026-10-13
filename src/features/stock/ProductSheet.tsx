import { useEffect, useId, useRef, useState, type FormEvent } from 'react'
import { CloseIcon } from '../../components/icons'
import { CheckField } from '../../components/ui/CheckField'
import { AmountInput, Button, Dialog, Field, IconButton, Input, Notice } from '../../components/ui'
import { addProduct } from '../../lib/covi'
import type { Arrival, Product } from '../../lib/types'
import '../../styles/app/stock.css'
import { PhotoField } from './PhotoField'
import {
  arrivalOption,
  emptyProduct,
  productFromValues,
  productSaveError,
  typedAmount,
  type ProductErrors,
  type ProductValues,
} from './productForm'

function ProductForm({
  shopId,
  arrivals,
  arrival,
  titleId,
  onClose,
  onSaved,
}: {
  shopId: string
  arrivals: readonly Arrival[]
  arrival: Arrival | null
  titleId: string
  onClose: () => void
  onSaved: (product: Product) => void
}) {
  const [values, setValues] = useState<ProductValues>(() => emptyProduct(arrival))
  const [errors, setErrors] = useState<ProductErrors>({})
  const [failure, setFailure] = useState('')
  const [busy, setBusy] = useState(false)
  const [photoBusy, setPhotoBusy] = useState(false)
  const form = useRef<HTMLFormElement>(null)
  const set = <K extends keyof ProductValues>(key: K, value: ProductValues[K]) => {
    setValues((v) => ({ ...v, [key]: value }))
    // A field being corrected loses its message.
    if (key in errors)
      setErrors((e) => {
        const next = { ...e }
        delete next[key as keyof ProductErrors]
        return next
      })
  }

  const chosen = arrival ?? arrivals.find((a) => a.id === values.arrivalId) ?? null
  const balloon = chosen?.kind === 'balloon'

  // After a refused submit, the first field to fix gets the focus.
  useEffect(() => {
    form.current?.querySelector<HTMLElement>('[aria-invalid="true"]')?.focus()
  }, [errors])

  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    if (busy || photoBusy) return
    const result = productFromValues(values, arrival ? [arrival] : arrivals)
    if (result.errors) {
      setErrors(result.errors)
      return
    }
    setErrors({})
    setFailure('')
    setBusy(true)
    try {
      const saved = await addProduct(shopId, result.input)
      onSaved(saved)
    } catch (err) {
      setFailure(productSaveError(err))
    } finally {
      setBusy(false)
    }
  }

  const title = arrival ? (balloon ? 'Nouvelle pièce' : 'Nouveau modèle') : 'Ajouter au stock'

  return (
    <form className="dialog__body product-form" ref={form} onSubmit={submit} noValidate>
      <div className="product-form__head">
        <div>
          {arrival && <p className="product-form__kicker">Pour {arrival.code}</p>}
          <h2 className="dialog__title" id={titleId}>
            {title}
          </h2>
        </div>
        <IconButton label="Fermer sans enregistrer" onClick={onClose}>
          <CloseIcon />
        </IconButton>
      </div>

      <Field label="Nom de l’article" error={errors.name}>
        {(control) => (
          <Input
            {...control}
            value={values.name}
            onChange={(e) => set('name', e.target.value)}
            placeholder={balloon ? 'Ex. Veste en jean' : 'Ex. Robe wax modèle A'}
            autoComplete="off"
            maxLength={120}
          />
        )}
      </Field>

      <PhotoField
        value={values.photo}
        onChange={(photo) => set('photo', photo)}
        onBusyChange={setPhotoBusy}
      />

      <div className="product-form__pair">
        <Field label="Type" optional>
          {(control) => (
            <Input
              {...control}
              value={values.category}
              onChange={(e) => set('category', e.target.value)}
              placeholder="Robe, jean, chemise…"
              maxLength={60}
            />
          )}
        </Field>
        <Field label="Marque" optional>
          {(control) => (
            <Input
              {...control}
              value={values.brand}
              onChange={(e) => set('brand', e.target.value)}
              maxLength={60}
            />
          )}
        </Field>
      </div>

      <div className="product-form__pair">
        <Field label="Taille" optional>
          {(control) => (
            <Input
              {...control}
              value={values.size}
              onChange={(e) => set('size', e.target.value)}
              placeholder="M, 40, 6 ans…"
              maxLength={30}
            />
          )}
        </Field>
        <Field label="Prix affiché (FCFA)" error={errors.price}>
          {(control) => (
            <AmountInput
              {...control}
              value={values.price}
              onChange={(e) => set('price', typedAmount(e.target.value))}
              placeholder="18 000"
            />
          )}
        </Field>
      </div>

      {!arrival && (
        <Field label="Vient de quel arrivage ?" optional>
          {(control) => (
            <select
              {...control}
              className="select"
              value={values.arrivalId}
              onChange={(e) => {
                const next = arrivals.find((a) => a.id === e.target.value)
                setValues((v) => ({
                  ...v,
                  arrivalId: e.target.value,
                  unique: next?.kind === 'balloon' ? true : v.unique,
                }))
              }}
            >
              <option value="">Aucun</option>
              {arrivals.map((a) => (
                <option key={a.id} value={a.id}>
                  {arrivalOption(a)}
                </option>
              ))}
            </select>
          )}
        </Field>
      )}

      <CheckField
        label="Pièce unique (friperie)"
        checked={values.unique || balloon}
        disabled={balloon}
        onChange={(unique) => set('unique', unique)}
        hint={
          balloon
            ? 'Une pièce de ballon est toujours unique.'
            : 'Un seul exemplaire : il sort du stock à la première vente.'
        }
      />

      {!(values.unique || balloon) && (
        <Field label="Combien de pièces ?" error={errors.quantity}>
          {(control) => (
            <Input
              {...control}
              className="product-form__qty"
              type="text"
              inputMode="numeric"
              autoComplete="off"
              value={Number.isFinite(values.quantity) && values.quantity > 0 ? values.quantity : ''}
              onChange={(e) => set('quantity', Number(e.target.value.replace(/\D/g, '') || 0))}
            />
          )}
        </Field>
      )}

      {failure && (
        <Notice tone="danger" className="product-form__failure">
          <p>{failure}</p>
        </Notice>
      )}

      <div className="dialog__actions">
        <Button variant="ghost" onClick={onClose}>
          Annuler
        </Button>
        <Button variant="primary" type="submit" busy={busy} disabled={photoBusy}>
          {photoBusy ? 'On prépare la photo…' : 'Mettre en stock'}
        </Button>
      </div>
    </form>
  )
}

/**
 * « Ajouter au stock » in a sheet (rises from the bottom on phones, centred on computers). With
 * `arrival`, the article is added to that arrival (a bale piece is always unique).
 */
export function ProductSheet({
  open,
  onClose,
  shopId,
  arrivals = [],
  arrival = null,
  onSaved,
}: {
  open: boolean
  onClose: () => void
  shopId: string
  /** Arrivals offered in « Vient de quel arrivage ? » (ignored with `arrival`). */
  arrivals?: readonly Arrival[]
  arrival?: Arrival | null
  onSaved: (product: Product) => void
}) {
  const titleId = useId()
  return (
    <Dialog open={open} onClose={onClose} labelledBy={titleId} sheet className="product-sheet">
      <ProductForm
        shopId={shopId}
        arrivals={arrivals}
        arrival={arrival}
        titleId={titleId}
        onClose={onClose}
        onSaved={onSaved}
      />
    </Dialog>
  )
}
