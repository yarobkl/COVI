import { useCallback, useEffect, useState } from 'react'
import { AmountInput, Button, Field, Notice, Segmented, Stamp } from '../../components/ui'
import { money } from '../../lib/format'
import { DEFAULT_ARTICLE_TYPES } from '../../lib/articleTypes'
import {
  compressReferencePhoto,
  fetchCatalog,
  paymentMethodLabels,
  paymentMethods,
  submitOrder,
  trackingLink,
  type Fulfillment,
  type OrderChannel,
  type OrderLineInput,
  type PaymentMethod,
  type PublicCatalog,
} from '../../lib/publicOrders'
import { GuestSheet } from './GuestSheet'
import { TurnstileChallenge } from './TurnstileChallenge'

type Line = {
  key: number
  articleType: string
  description: string
  quantity: number
  price: string
}

const newOperationId = () => crypto.randomUUID()
const OTHER_ARTICLE = '__covi_other_article__'
const emptyLine = (key: number): Line => ({
  key,
  articleType: '',
  description: '',
  quantity: 1,
  price: '',
})

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

  const load = useCallback(() => {
    fetchCatalog(token)
      .then(setCatalog)
      .catch((e: Error) => setLoadError(e.message))
  }, [token])
  useEffect(load, [load])
  useEffect(() => {
    document.title = catalog ? `Commander — ${catalog.shopName}` : 'Commander — COVI'
  }, [catalog])

  const articleTypes = catalog?.articleTypes?.length
    ? catalog.articleTypes
    : [...DEFAULT_ARTICLE_TYPES]

  const update = (key: number, patch: Partial<Line>) =>
    setLines((all) => all.map((l) => (l.key === key ? { ...l, ...patch } : l)))

  const total = lines.reduce((sum, l) => {
    const price = Number(l.price || 0)
    return sum + (Number.isFinite(price) ? price * l.quantity : 0)
  }, 0)

  if (done)
    return (
      <GuestSheet shop={catalog?.shopName}>
        <section className="order-guest__part order-guest__done">
          <h1 className="section-title">Demande envoyée</h1>
          <Stamp kind="received" size="lg" drop>
            Reçue
          </Stamp>
          <p className="order-guest__ref">
            Référence <span className="figures">{done.reference}</span>
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
      </GuestSheet>
    )

  if (loadError)
    return (
      <GuestSheet>
        <section className="order-guest__part">
          <h1 className="section-title">Commande en ligne</h1>
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
      </GuestSheet>
    )

  if (!catalog)
    return (
      <GuestSheet>
        <p className="hand order-guest__loading" role="status">
          Ouverture de la boutique…
        </p>
      </GuestSheet>
    )

  // The customer's drop-down is an assortment of article TYPES, not stock references.
  const free = !catalog.showCatalog
  const linesValid = lines.every(
    (l) =>
      (free || l.articleType === OTHER_ARTICLE
        ? l.description.trim().length > 0
        : articleTypes.includes(l.articleType)) && l.quantity >= 1,
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
        const article =
          free || l.articleType === OTHER_ARTICLE
            ? l.description.trim()
            : [l.articleType, l.description.trim()].filter(Boolean).join(' — ')
        // Product references are allocated by the cashier AFTER checking real stock.
        return { ...base, description: article }
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

  const place = [catalog.neighborhood, catalog.city].filter(Boolean).join(', ')

  return (
    <GuestSheet shop={catalog.shopName} place={place}>
      <header className="order-guest__head">
        <h1 className="section-title">Bon de commande</h1>
        <p className="hand order-guest__hand">Sans compte, et vous ne payez rien ici.</p>
      </header>
      {catalog.message && <p className="order-guest__message hand">{catalog.message}</p>}
      {!catalog.ordersOpen && (
        <Notice tone="danger">
          <p>Les commandes en ligne sont momentanément fermées. Contactez la boutique.</p>
        </Notice>
      )}

      <form
        className="order-guest__form"
        onSubmit={(e) => {
          e.preventDefault()
          if (ready) void send()
        }}
      >
        <section className="order-guest__part">
          <h2 className="section-title">Vos articles</h2>
          {catalog.showCatalog && (
            <p className="order-guest__lead">
              Choisissez ce que vous recherchez, même si la boutique n’en a pas en stock
              actuellement. Le commerçant confirmera la disponibilité et le prix avant le règlement.
            </p>
          )}
          {lines.map((line, index) => (
            <fieldset key={line.key} className="order-guest__line">
              <legend className="order-guest__num hand">Article {index + 1}</legend>
              {free ? (
                <Field label="Article souhaité">
                  {(control) => (
                    <input
                      {...control}
                      className="input"
                      value={line.description}
                      maxLength={120}
                      placeholder="Ex. robe wax rouge vue dans votre statut"
                      onChange={(e) => update(line.key, { description: e.target.value })}
                    />
                  )}
                </Field>
              ) : (
                <>
                  <Field label="Choisir un article">
                    {(control) => (
                      <select
                        {...control}
                        className="select"
                        value={line.articleType}
                        onChange={(e) =>
                          update(line.key, { articleType: e.target.value, description: '' })
                        }
                      >
                        <option value="">Sélectionner un type d’article…</option>
                        {articleTypes.map((type) => (
                          <option key={type} value={type}>
                            {type}
                          </option>
                        ))}
                        <option value={OTHER_ARTICLE}>Autre article</option>
                      </select>
                    )}
                  </Field>
                  <Field
                    label={
                      line.articleType === OTHER_ARTICLE
                        ? 'Précisez l’article souhaité'
                        : 'Précisions : taille, couleur ou modèle'
                    }
                    optional={line.articleType !== OTHER_ARTICLE}
                  >
                    {(control) => (
                      <input
                        {...control}
                        className="input"
                        value={line.description}
                        maxLength={line.articleType === OTHER_ARTICLE ? 120 : 60}
                        placeholder={
                          line.articleType === OTHER_ARTICLE
                            ? 'Ex. tenue traditionnelle pour enfant'
                            : 'Ex. taille L, bleu, vu sur WhatsApp'
                        }
                        onChange={(e) => update(line.key, { description: e.target.value })}
                      />
                    )}
                  </Field>
                </>
              )}
              <div className="order-guest__row">
                <Field label="Quantité">
                  {(control) => (
                    <select
                      {...control}
                      className="select"
                      value={line.quantity}
                      onChange={(e) => update(line.key, { quantity: Number(e.target.value) })}
                    >
                      {Array.from({ length: 20 }, (_, i) => i + 1).map((n) => (
                        <option key={n} value={n}>
                          {n}
                        </option>
                      ))}
                    </select>
                  )}
                </Field>
                <Field label="Prix proposé" optional>
                  {(control) => (
                    <AmountInput
                      {...control}
                      value={line.price}
                      placeholder="0"
                      onChange={(e) =>
                        update(line.key, { price: e.target.value.replace(/\D/g, '').slice(0, 9) })
                      }
                    />
                  )}
                </Field>
              </div>
              {lines.length > 1 && (
                <Button
                  variant="ghost"
                  className="order-guest__remove"
                  onClick={() => setLines((all) => all.filter((l) => l.key !== line.key))}
                >
                  Retirer cet article
                </Button>
              )}
            </fieldset>
          ))}
          {lines.length < 20 && (
            <Button
              variant="secondary"
              onClick={() => {
                setLines((all) => [...all, emptyLine(nextKey)])
                setNextKey((k) => k + 1)
              }}
            >
              + Ajouter un autre article
            </Button>
          )}
          {total > 0 && (
            <p className="order-guest__total">
              <span>Total indicatif</span>
              <span className="order-guest__dots" aria-hidden="true" />
              <b className="figures">{money(total)}</b>
            </p>
          )}
          {total > 0 && <p className="muted">Le prix final est confirmé par la boutique.</p>}
        </section>

        <section
          className="order-guest__part order-guest__reference-photo"
          aria-label="Photo du modèle recherché"
        >
          <h2 className="section-title">
            Photo du modèle <span className="field__optional">(facultatif)</span>
          </h2>
          <p className="order-guest__lead">
            Vu sur WhatsApp, TikTok ou ailleurs ? Joignez une capture d’écran ou une photo pour
            montrer le modèle à la boutique.
          </p>
          {!photo && (
            <label className="btn btn--secondary order-guest__upload">
              <input
                className="visually-hidden"
                type="file"
                accept="image/*"
                aria-label="Ajouter une capture d’écran ou une photo du modèle"
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
              Ajouter une capture ou une photo
            </label>
          )}
          {photo && (
            <>
              <figure className="order-guest__polaroid">
                <img src={photo} alt="Aperçu de la photo du modèle à commander" />
                <figcaption className="hand">Photo ajoutée à votre demande</figcaption>
              </figure>
              <Button variant="ghost" onClick={() => setPhoto(null)}>
                Retirer la photo
              </Button>
            </>
          )}
          {photoError && (
            <p className="field__error" role="alert">
              {photoError}
            </p>
          )}
        </section>

        <section className="order-guest__part">
          <h2 className="section-title">Vos coordonnées</h2>
          <Field label="Votre nom">
            {(control) => (
              <input
                {...control}
                className="input"
                value={name}
                maxLength={60}
                autoComplete="name"
                onChange={(e) => setName(e.target.value)}
              />
            )}
          </Field>
          <Field label="Téléphone (WhatsApp de préférence)">
            {(control) => (
              <input
                {...control}
                className="input"
                value={phone}
                inputMode="tel"
                autoComplete="tel"
                maxLength={32}
                placeholder="+242 06 …"
                onChange={(e) => setPhone(e.target.value)}
              />
            )}
          </Field>
        </section>

        <section className="order-guest__part">
          <Segmented
            legend={<span className="section-title">Réception</span>}
            options={[
              { value: 'pickup', label: 'Retrait en boutique' },
              { value: 'delivery', label: 'Livraison' },
            ]}
            value={fulfillment}
            onChange={setFulfillment}
          />
          {fulfillment === 'delivery' && (
            <Field label="Adresse de livraison (quartier, rue, repère)">
              {(control) => (
                <textarea
                  {...control}
                  className="input order-guest__textarea"
                  rows={2}
                  maxLength={240}
                  value={address}
                  onChange={(e) => setAddress(e.target.value)}
                />
              )}
            </Field>
          )}
        </section>

        <section className="order-guest__part">
          <Segmented
            legend={<span className="section-title">Règlement</span>}
            options={paymentMethods.map((m) => ({ value: m, label: paymentMethodLabels[m] }))}
            value={method}
            onChange={setMethod}
          />
          <p className="order-guest__promise">
            <mark>Vous ne payez rien sur cette page.</mark> La boutique vous indiquera comment
            régler et confirmera elle-même la réception de votre règlement.
          </p>
          <Field label="Message pour la boutique" optional>
            {(control) => (
              <textarea
                {...control}
                className="input order-guest__textarea"
                rows={3}
                maxLength={500}
                value={note}
                onChange={(e) => setNote(e.target.value)}
              />
            )}
          </Field>
        </section>

        <section className="order-guest__part order-guest__send">
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
            <p className="order-guest__why">
              {!linesValid
                ? 'Choisissez au moins un article.'
                : !name.trim() || !phoneValid
                  ? 'Indiquez votre nom et un numéro de téléphone valide.'
                  : fulfillment === 'delivery' && !address.trim()
                    ? 'Indiquez l’adresse de livraison.'
                    : 'Validez la vérification de sécurité ci-dessus.'}
            </p>
          )}
        </section>
      </form>
    </GuestSheet>
  )
}
