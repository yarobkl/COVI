import { useCallback, useEffect, useId, useState } from 'react'
import { Button, Notice } from '../../components/ui'
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
        {catalog.showCatalog && (
          <p className="muted">
            Choisissez ce que vous recherchez, même si la boutique n’en a pas en stock actuellement.
            Le commerçant confirmera la disponibilité et le prix avant le règlement.
          </p>
        )}
        {lines.map((line, index) => (
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
              <>
                <label>
                  Choisir un article
                  <select
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
                </label>
                <label>
                  {line.articleType === OTHER_ARTICLE
                    ? 'Précisez l’article souhaité'
                    : 'Précisions : taille, couleur ou modèle (facultatif)'}
                  <input
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
                </label>
              </>
            )}
            <div className="order-guest__row">
              <label>
                Quantité
                <select
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
              </label>
              <label>
                Prix proposé (facultatif)
                <input
                  className="input input--amount"
                  inputMode="numeric"
                  value={line.price}
                  placeholder="FCFA"
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
        ))}
        <section className="order-guest__reference-photo" aria-label="Photo du modèle recherché">
          <h3>Ajouter une photo du modèle (facultatif)</h3>
          <p className="muted">
            Vous avez vu un vêtement sur WhatsApp, TikTok ou ailleurs ? Joignez une capture d’écran
            ou une photo depuis votre téléphone pour montrer le modèle à la boutique. Une photo peut
            accompagner cette demande.
          </p>
          <label htmlFor={`${ids}-reference-photo`}>Capture d’écran ou photo du modèle</label>
          <input
            id={`${ids}-reference-photo`}
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
          {photo && (
            <>
              <p role="status">Photo ajoutée à votre demande</p>
              <img
                className="order-guest__photo"
                src={photo}
                alt="Aperçu de la photo du modèle à commander"
              />
              <Button variant="secondary" onClick={() => setPhoto(null)}>
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

        {lines.length < 20 && (
          <Button
            variant="secondary"
            onClick={() => {
              setLines((all) => [...all, emptyLine(nextKey)])
              setNextKey((k) => k + 1)
            }}
          >
            Ajouter un autre article à ma demande
          </Button>
        )}
        {total > 0 && (
          <p className="order-guest__total">
            Total indicatif : <b>{money(total)}</b>
            <br />
            <span className="muted">Le prix final est confirmé par la boutique.</span>
          </p>
        )}

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
