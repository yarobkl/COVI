import { useCallback, useEffect, useId, useMemo, useState } from 'react'
import { Button, Notice } from '../../components/ui'
import { money } from '../../lib/format'
import {
  compressReferencePhoto,
  fetchCatalog,
  paymentMethodLabels,
  paymentMethods,
  submitOrder,
  trackingLink,
  type CatalogProduct,
  type Fulfillment,
  type OrderChannel,
  type OrderLineInput,
  type PaymentMethod,
  type PublicCatalog,
} from '../../lib/publicOrders'
import { TurnstileChallenge } from './TurnstileChallenge'

type Line = { key: number; productId: string; description: string; quantity: number; price: string }

const newOperationId = () => crypto.randomUUID()
const emptyLine = (key: number): Line => ({
  key,
  productId: '',
  description: '',
  quantity: 1,
  price: '',
})

function productLabel(p: CatalogProduct) {
  const details = [p.brand, p.size ? `taille ${p.size}` : null].filter(Boolean).join(' · ')
  return `${p.name}${details ? ` (${details})` : ''} — ${money(p.priceXaf)}`
}

/**
 * Page ouverte par le QR code ou le lien WhatsApp / TikTok d'une boutique. Le client n'a pas de
 * compte : il choisit ses articles dans le stock publié (ou les décrit), indique comment il veut
 * les recevoir et payer, et reçoit une référence de suivi. Aucun paiement n'est encaissé ici.
 */
export function PublicOrderPage({ token, channel }: { token: string; channel: OrderChannel }) {
  const [catalog, setCatalog] = useState<PublicCatalog | null>(null)
  const [loadError, setLoadError] = useState('')
  const [lines, setLines] = useState<Line[]>([emptyLine(1)])
  const [nextKey, setNextKey] = useState(2)
  const [name, setName] = useState('')
  const [phone, setPhone] = useState('')
  const [fulfillment, setFulfillment] = useState<Fulfillment>('pickup')
  const [address, setAddress] = useState('')
  const [method, setMethod] = useState<PaymentMethod>('mobile_money')
  const [note, setNote] = useState('')
  const [photo, setPhoto] = useState<string | null>(null)
  const [photoError, setPhotoError] = useState('')
  const [challenge, setChallenge] = useState('')
  const [resetKey, setResetKey] = useState(0)
  const [operationId, setOperationId] = useState(newOperationId)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [done, setDone] = useState<{
    reference: string
    trackingToken: string
    photoSaved: boolean | null
  } | null>(null)
  const ids = useId()

  const load = useCallback(() => {
    fetchCatalog(token)
      .then(setCatalog)
      .catch((e: Error) => setLoadError(e.message))
  }, [token])
  useEffect(load, [load])
  useEffect(() => {
    document.title = catalog ? `Commander — ${catalog.shopName}` : 'Commander — COVI'
  }, [catalog])

  const byId = useMemo(() => new Map((catalog?.products ?? []).map((p) => [p.id, p])), [catalog])
  const categories = useMemo(() => {
    const groups = new Map<string, CatalogProduct[]>()
    for (const p of catalog?.products ?? []) {
      const key = p.category?.trim() || 'Autres articles'
      groups.set(key, [...(groups.get(key) ?? []), p])
    }
    return [...groups.entries()]
  }, [catalog])

  const update = (key: number, patch: Partial<Line>) =>
    setLines((all) => all.map((l) => (l.key === key ? { ...l, ...patch } : l)))

  const total = lines.reduce((sum, l) => {
    const p = byId.get(l.productId)
    const price = l.price ? Number(l.price) : (p?.priceXaf ?? 0)
    return sum + (Number.isFinite(price) ? price * l.quantity : 0)
  }, 0)

  if (done)
    return (
      <main className="order-guest" id="contenu">
        <section className="order-guest__card">
          <p className="order-guest__shop">{catalog?.shopName}</p>
          <h1>Demande envoyée</h1>
          <p className="order-guest__ref">
            Référence <b>{done.reference}</b>
          </p>
          <Notice tone="calm">
            <p>
              La boutique va vous contacter pour confirmer la disponibilité et le règlement. Rien
              n’est payé tant que la boutique n’a pas confirmé avoir reçu votre règlement.
            </p>
          </Notice>
          {done.photoSaved === false && (
            <p className="muted">La photo n’a pas pu être jointe ; la demande est bien envoyée.</p>
          )}
          <p>Gardez ce lien pour suivre votre commande et recevoir votre reçu :</p>
          <a
            className="order-guest__link"
            href={trackingLink(window.location.origin, done.trackingToken)}
          >
            Suivre ma commande {done.reference}
          </a>
        </section>
      </main>
    )

  if (loadError)
    return (
      <main className="order-guest" id="contenu">
        <section className="order-guest__card">
          <h1>Commande en ligne</h1>
          <Notice tone="danger">
            <p>{loadError}</p>
          </Notice>
          <Button
            variant="secondary"
            onClick={() => {
              setLoadError('')
              load()
            }}
          >
            Réessayer
          </Button>
        </section>
      </main>
    )

  if (!catalog)
    return (
      <main className="order-guest" id="contenu">
        <p role="status">Ouverture de la boutique…</p>
      </main>
    )

  const free = !catalog.showCatalog
  const linesValid = lines.every(
    (l) => (free ? l.description.trim().length > 0 : Boolean(l.productId)) && l.quantity >= 1,
  )
  const phoneValid = /^\+?[0-9 ().-]{6,32}$/.test(phone.trim())
  const ready =
    catalog.ordersOpen &&
    linesValid &&
    name.trim().length > 0 &&
    phoneValid &&
    (fulfillment === 'pickup' || address.trim().length > 0) &&
    challenge.length > 0 &&
    !busy

  const send = async () => {
    setBusy(true)
    setError('')
    try {
      const payload: OrderLineInput[] = lines.map((l) => {
        const proposed = l.price ? Math.round(Number(l.price)) : undefined
        const base = {
          quantity: l.quantity,
          ...(proposed ? { proposedUnitPriceXaf: proposed } : {}),
        }
        return free
          ? { ...base, description: l.description.trim() }
          : { ...base, productId: l.productId }
      })
      const result = await submitOrder({
        token,
        operationId,
        channel,
        customerName: name.trim(),
        phone: phone.trim(),
        fulfillment,
        deliveryAddress: fulfillment === 'delivery' ? address.trim() : undefined,
        paymentMethod: method,
        note: note.trim() || undefined,
        lines: payload,
        referenceImage: photo,
        challenge,
      })
      setDone(result)
    } catch (e) {
      setError((e as Error).message)
      // Le jeton anti-robot est à usage unique ; une demande refusée peut être corrigée et renvoyée.
      setResetKey((k) => k + 1)
      if ((e as { status?: number }).status === 409) setOperationId(newOperationId())
      if ((e as { status?: number }).status === 409) load()
    } finally {
      setBusy(false)
    }
  }

  return (
    <main className="order-guest" id="contenu">
      <section className="order-guest__card">
        <p className="order-guest__shop">
          {catalog.shopName}
          {[catalog.neighborhood, catalog.city].filter(Boolean).length > 0 &&
            ` · ${[catalog.neighborhood, catalog.city].filter(Boolean).join(', ')}`}
        </p>
        <h1>Commander</h1>
        {catalog.message && <p className="order-guest__message">{catalog.message}</p>}
        {!catalog.ordersOpen && (
          <Notice tone="danger">
            <p>Les commandes en ligne sont momentanément fermées. Contactez la boutique.</p>
          </Notice>
        )}
      </section>

      <form
        className="order-guest__card"
        onSubmit={(e) => {
          e.preventDefault()
          if (ready) void send()
        }}
      >
        <h2>Vos articles</h2>
        {!free && catalog.products.length === 0 && (
          <p className="muted">Aucun article n’est disponible en ligne pour le moment.</p>
        )}
        {lines.map((line, index) => {
          const product = byId.get(line.productId)
          const max = product?.maxQuantity ?? 20
          return (
            <fieldset key={line.key} className="order-guest__line">
              <legend>Article {index + 1}</legend>
              {free ? (
                <label>
                  Article souhaité
                  <input
                    className="input"
                    value={line.description}
                    maxLength={120}
                    placeholder="Ex. robe wax rouge vue dans votre statut"
                    onChange={(e) => update(line.key, { description: e.target.value })}
                  />
                </label>
              ) : (
                <label>
                  Article
                  <select
                    className="select"
                    value={line.productId}
                    onChange={(e) => update(line.key, { productId: e.target.value, quantity: 1 })}
                  >
                    <option value="">Choisir un article…</option>
                    {categories.map(([category, products]) => (
                      <optgroup key={category} label={category}>
                        {products.map((p) => (
                          <option
                            key={p.id}
                            value={p.id}
                            disabled={lines.some((l) => l.key !== line.key && l.productId === p.id)}
                          >
                            {productLabel(p)}
                          </option>
                        ))}
                      </optgroup>
                    ))}
                  </select>
                </label>
              )}
              <div className="order-guest__row">
                <label>
                  Quantité
                  <select
                    className="select"
                    value={line.quantity}
                    onChange={(e) => update(line.key, { quantity: Number(e.target.value) })}
                  >
                    {Array.from({ length: Math.max(1, max) }, (_, i) => i + 1).map((n) => (
                      <option key={n} value={n}>
                        {n}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  Prix proposé (facultatif)
                  <input
                    className="input input--amount"
                    inputMode="numeric"
                    value={line.price}
                    placeholder={product ? String(product.priceXaf) : 'FCFA'}
                    onChange={(e) =>
                      update(line.key, { price: e.target.value.replace(/\D/g, '').slice(0, 9) })
                    }
                  />
                </label>
              </div>
              {lines.length > 1 && (
                <Button
                  variant="ghost"
                  onClick={() => setLines((all) => all.filter((l) => l.key !== line.key))}
                >
                  Retirer cet article
                </Button>
              )}
            </fieldset>
          )
        })}
        {lines.length < 20 && (
          <Button
            variant="secondary"
            onClick={() => {
              setLines((all) => [...all, emptyLine(nextKey)])
              setNextKey((k) => k + 1)
            }}
          >
            Ajouter un article
          </Button>
        )}
        {total > 0 && (
          <p className="order-guest__total">
            Total indicatif : <b>{money(total)}</b>
            <br />
            <span className="muted">Le prix final est confirmé par la boutique.</span>
          </p>
        )}

        <h2>Photo de l’article (facultatif)</h2>
        <p className="muted">
          Capture d’un statut WhatsApp ou d’un live TikTok, pour aider la boutique.
        </p>
        <input
          type="file"
          accept="image/*"
          aria-label="Photo de référence"
          onChange={async (e) => {
            const file = e.target.files?.[0]
            setPhotoError('')
            if (!file) return setPhoto(null)
            try {
              setPhoto(await compressReferencePhoto(file))
            } catch (err) {
              setPhoto(null)
              setPhotoError((err as Error).message)
            }
          }}
        />
        {photo && <img className="order-guest__photo" src={photo} alt="Photo jointe" />}
        {photoError && <p className="field__error">{photoError}</p>}

        <h2>Vos coordonnées</h2>
        <label htmlFor={`${ids}-name`}>Votre nom</label>
        <input
          id={`${ids}-name`}
          className="input"
          value={name}
          maxLength={60}
          autoComplete="name"
          onChange={(e) => setName(e.target.value)}
        />
        <label htmlFor={`${ids}-phone`}>Téléphone (WhatsApp de préférence)</label>
        <input
          id={`${ids}-phone`}
          className="input"
          value={phone}
          inputMode="tel"
          autoComplete="tel"
          maxLength={32}
          placeholder="+242 06 …"
          onChange={(e) => setPhone(e.target.value)}
        />

        <h2>Réception</h2>
        <div className="order-guest__choices" role="radiogroup" aria-label="Réception">
          {(
            [
              ['pickup', 'Retrait en boutique'],
              ['delivery', 'Livraison'],
            ] as const
          ).map(([value, label]) => (
            <label key={value} className="order-guest__choice">
              <input
                type="radio"
                name={`${ids}-fulfillment`}
                checked={fulfillment === value}
                onChange={() => setFulfillment(value)}
              />
              {label}
            </label>
          ))}
        </div>
        {fulfillment === 'delivery' && (
          <>
            <label htmlFor={`${ids}-address`}>Adresse de livraison (quartier, rue, repère)</label>
            <textarea
              id={`${ids}-address`}
              className="input"
              rows={2}
              maxLength={240}
              value={address}
              onChange={(e) => setAddress(e.target.value)}
            />
          </>
        )}

        <h2>Règlement</h2>
        <div className="order-guest__choices" role="radiogroup" aria-label="Moyen de règlement">
          {paymentMethods.map((m) => (
            <label key={m} className="order-guest__choice">
              <input
                type="radio"
                name={`${ids}-payment`}
                checked={method === m}
                onChange={() => setMethod(m)}
              />
              {paymentMethodLabels[m]}
            </label>
          ))}
        </div>
        <p className="muted">
          Vous ne payez rien sur cette page. La boutique vous indiquera comment régler et confirmera
          elle-même la réception de votre règlement.
        </p>

        <label htmlFor={`${ids}-note`}>Message pour la boutique (facultatif)</label>
        <textarea
          id={`${ids}-note`}
          className="input"
          rows={3}
          maxLength={500}
          value={note}
          onChange={(e) => setNote(e.target.value)}
        />

        {catalog.ordersOpen && <TurnstileChallenge onToken={setChallenge} resetKey={resetKey} />}
        {error && (
          <Notice tone="danger">
            <p>{error}</p>
          </Notice>
        )}
        <Button type="submit" variant="primary" block busy={busy} disabled={!ready}>
          Envoyer ma demande
        </Button>
        {!ready && !busy && catalog.ordersOpen && (
          <p className="muted">
            {!linesValid
              ? 'Choisissez au moins un article.'
              : !name.trim() || !phoneValid
                ? 'Indiquez votre nom et un numéro de téléphone valide.'
                : fulfillment === 'delivery' && !address.trim()
                  ? 'Indiquez l’adresse de livraison.'
                  : 'Validez la vérification de sécurité ci-dessus.'}
          </p>
        )}
      </form>
      <p className="order-guest__footer muted">Commande gérée avec COVI — Commerce &amp; Vie</p>
    </main>
  )
}
