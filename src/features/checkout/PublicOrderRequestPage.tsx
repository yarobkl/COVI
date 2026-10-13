import { useEffect, useRef, useState, type FormEvent } from 'react'
import { TurnstileChallenge } from './TurnstileChallenge'
import {
  Amount,
  AmountInput,
  Button,
  Field,
  Ledger,
  LedgerRow,
  Notice,
  Sheet,
  Stepper,
} from '../../components/ui'
import { fcfa, parseAmount } from '../../lib/format'
import { prepareOrderReferencePhoto } from '../../lib/orderReferencePhoto'
import { prepareManualOrderLines, type ManualOrderLineInput } from '../../lib/manualOrder'
import {
  getPublicCatalog,
  preparePublicRequest,
  submitPublicOrder,
  type OrderChannel,
  type ProposedPaymentMethod,
  type PublicCatalog,
  type RecordedPublicRequest,
} from '../../lib/publicOrders'

type Props = { token: string; channel: OrderChannel }
type BasketLine = ManualOrderLineInput

/** Guest experience. A public order is always a REQUEST, never an automatic sale.
 * No sign-in required; token only permits submitting with strict server limits.
 * Not reachable unless the checkout build-time feature flag is enabled.
 */
export function PublicOrderRequestPage({ token, channel }: Props) {
  const [catalog, setCatalog] = useState<PublicCatalog | null>(null)
  const [loadError, setLoadError] = useState('')
  const [retry, setRetry] = useState(0)
  const [lines, setLines] = useState<BasketLine[]>([])
  const [categoryId, setCategoryId] = useState('')
  const [quantity, setQuantity] = useState(1)
  const [priceInput, setPriceInput] = useState('')
  const [fulfillment, setFulfillment] = useState<'pickup' | 'delivery'>('pickup')
  const [paymentMethod, setPaymentMethod] = useState<ProposedPaymentMethod | ''>('')
  const [phone, setPhone] = useState('')
  const [deliveryAddress, setDeliveryAddress] = useState('')
  const [note, setNote] = useState('')
  const [referenceImage, setReferenceImage] = useState<string | null>(null)
  const [photoBusy, setPhotoBusy] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [saved, setSaved] = useState<RecordedPublicRequest | null>(null)
  const [challenge, setChallenge] = useState('')
  const [challengeVersion, setChallengeVersion] = useState(0)
  const inFlight = useRef(false)
  const attempt = useRef<{ fingerprint: string; operationId: string } | null>(null)

  useEffect(() => {
    let cancelled = false
    getPublicCatalog(token).then(
      (value) => {
        if (!cancelled) {
          setCatalog(value)
          setLoadError('')
        }
      },
      (reason) => {
        if (!cancelled) {
          setLoadError(reason instanceof Error ? reason.message : 'Lien de commande indisponible.')
        }
      },
    )
    return () => {
      cancelled = true
    }
  }, [token, retry])

  const selected = catalog?.categories.find((c) => c.id === categoryId)
  const price = parseAmount(priceInput)
  const total = lines.reduce((sum, line) => sum + line.quantity * line.negotiatedUnitPriceXaf, 0)
  const count = lines.reduce((sum, line) => sum + line.quantity, 0)

  function addLine() {
    if (inFlight.current) return
    setError('')
    if (!selected || price === null || price < 1 || price > 999_999_999) {
      setError('Choisissez une catégorie et un prix négocié valide.')
      return
    }
    const others = lines
      .filter((line) => line.categoryId === selected.id)
      .reduce((sum, line) => sum + line.quantity, 0)
    if (others + quantity > 20) {
      setError('La demande est limitée à 20 pièces par catégorie.')
      return
    }
    try {
      const prepared = prepareManualOrderLines([
        ...lines,
        { categoryId: selected.id, quantity, negotiatedUnitPriceXaf: price },
      ])
      if (prepared.lines.length > 20 || prepared.amountXaf > 2_000_000_000)
        throw new Error('La commande est trop importante.')
      setLines(
        prepared.lines.map((line) => ({
          categoryId: line.categoryId,
          quantity: line.quantity,
          negotiatedUnitPriceXaf: line.unitPriceXaf,
        })),
      )
      setQuantity(1)
      setPriceInput('')
      setCategoryId('')
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Article non ajouté.')
    }
  }

  async function send(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    if (inFlight.current) return
    inFlight.current = true
    setBusy(true)
    setError('')
    try {
      // Include all editable request details in the retry identity.
      const fingerprint = JSON.stringify([
        token,
        channel,
        lines,
        phone.trim(),
        deliveryAddress.trim(),
        note.trim(),
        fulfillment,
        paymentMethod,
        referenceImage,
      ])
      if (!attempt.current || attempt.current.fingerprint !== fingerprint) {
        attempt.current = { fingerprint, operationId: crypto.randomUUID() }
      }
      const input = {
        token,
        channel,
        operationId: attempt.current.operationId,
        lines,
        phone,
        deliveryAddress,
        note,
        fulfillment,
        paymentMethod: paymentMethod || undefined,
        referenceImage: referenceImage ?? undefined,
      }
      const prepared = preparePublicRequest(input)
      if (!paymentMethod) throw new Error('Choisissez le moyen de paiement prévu.')
      const result = await submitPublicOrder({ ...input, paymentMethod, challenge })
      const expected = prepared.p_lines.reduce(
        (sum, line) => sum + line.quantity * line.unitPriceXaf,
        0,
      )
      if (result.amountXaf !== expected)
        throw new Error('Le montant renvoyé par la boutique ne correspond pas à votre demande.')
      setSaved(result)
      // Preserve a private, reloadable order follow-up link. Unlike the QR,
      // this random token grants access only to this single order's status.
      window.location.hash = '/suivi/' + result.trackingToken
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Demande non envoyée. Réessayez.')
      setChallenge('')
      setChallengeVersion((current) => current + 1)
    } finally {
      inFlight.current = false
      setBusy(false)
    }
  }

  if (loadError)
    return (
      <div className="checkout-guest seyes margin-rule">
        <Notice tone="danger" title="Cette page de commande est indisponible.">
          <p>{loadError}</p>
          <Button
            variant="secondary"
            onClick={() => {
              setLoadError('')
              setRetry((x) => x + 1)
            }}
          >
            Réessayer
          </Button>
        </Notice>
      </div>
    )

  if (!catalog)
    return (
      <div className="checkout-guest seyes margin-rule" role="status">
        <p className="hand">On ouvre le cahier de la boutique…</p>
      </div>
    )

  if (saved)
    return (
      <main className="checkout-guest seyes margin-rule">
        <Sheet className="checkout-guest__sheet">
          <p className="hand">C'est noté !</p>
          <h1>
            {saved.status === 'cancelled' || saved.status === 'expired'
              ? 'Demande clôturée'
              : 'Demande envoyée'}
          </h1>
          <p>Votre demande a été retrouvée dans le cahier de {catalog.shopName}.</p>
          <Ledger>
            <LedgerRow
              variant="total"
              label="Montant proposé"
              value={<Amount value={saved.amountXaf} unit />}
            />
          </Ledger>
          <p>Présentez ce numéro au vendeur :</p>
          <strong className="checkout-guest__reference figures">
            {saved.orderId.slice(0, 8).toUpperCase()}
          </strong>
          <p className="checkout-guest__caution">
            {saved.status === 'paid'
              ? 'La boutique a enregistré votre règlement. Cette page ne permet jamais de payer.'
              : saved.status === 'cancelled' || saved.status === 'expired'
                ? 'Cette demande n’est plus active. Contactez la boutique pour une nouvelle demande.'
                : 'La boutique doit vérifier votre demande et constater tout paiement séparément. Aucun paiement ne peut être effectué depuis cette page.'}
          </p>
        </Sheet>
      </main>
    )

  return (
    <main className="checkout-guest seyes margin-rule">
      <Sheet className="checkout-guest__sheet">
        <header className="checkout-guest__head">
          <p className="hand">La feuille de commande</p>
          <h1>{catalog.shopName}</h1>
          <p>Choisissez vos vêtements par catégorie et notez le prix discuté avec le vendeur.</p>
          <p className="checkout-guest__caution">
            Ceci est une demande, pas un paiement. La boutique confirmera la disponibilité.
          </p>
        </header>
        <form
          onSubmit={(e) => {
            void send(e)
          }}
          className="checkout-guest__form"
        >
          <fieldset disabled={busy} className="checkout-guest__entry">
            <legend className="section-title">Ajouter un vêtement</legend>
            <Field label="Catégorie">
              {(props) => (
                <select
                  {...props}
                  className="select"
                  value={categoryId}
                  onChange={(e) => {
                    setCategoryId(e.target.value)
                    setQuantity(1)
                  }}
                >
                  <option value="">Choisir une catégorie</option>
                  {catalog.categories.map((item) => (
                    <option key={item.id} value={item.id}>
                      {item.label}
                    </option>
                  ))}
                </select>
              )}
            </Field>
            <Field label="Prix discuté par pièce" hint="FCFA · le vendeur devra le confirmer">
              {(props) => (
                <AmountInput
                  {...props}
                  value={priceInput}
                  placeholder="Ex. : 3 500"
                  onChange={(e) =>
                    setPriceInput(
                      parseAmount(e.target.value) === null
                        ? ''
                        : fcfa(parseAmount(e.target.value) ?? 0),
                    )
                  }
                />
              )}
            </Field>
            {selected && (
              <div className="checkout-guest__quantity">
                <span>Quantité souhaitée</span>
                <Stepper
                  itemName={selected.label}
                  value={quantity}
                  max={20}
                  onChange={setQuantity}
                />
                <small>Disponibilité à confirmer</small>
              </div>
            )}
            <Button
              variant="tactile"
              block
              disabled={!selected || price === null || price < 1 || price > 999_999_999}
              onClick={addLine}
            >
              Ajouter à la demande
            </Button>
          </fieldset>
          <section className="checkout-guest__lines" aria-label="Articles demandés">
            <h2 className="section-title">Ma demande</h2>
            {lines.length ? (
              lines.map((line, index) => {
                const label =
                  catalog.categories.find((c) => c.id === line.categoryId)?.label ?? 'Catégorie'
                return (
                  <div
                    key={line.categoryId + ':' + line.negotiatedUnitPriceXaf}
                    className="checkout-guest__item"
                  >
                    <div>
                      <strong>{label}</strong>
                      <p>
                        {line.quantity} × {fcfa(line.negotiatedUnitPriceXaf)} FCFA
                      </p>
                    </div>
                    <Button
                      variant="ghost"
                      disabled={busy}
                      onClick={() => setLines((old) => old.filter((_, i) => i !== index))}
                    >
                      Retirer
                    </Button>
                  </div>
                )
              })
            ) : (
              <p>Votre feuille est vide.</p>
            )}
            <Ledger>
              <LedgerRow
                variant="total"
                label={'Total proposé · ' + count + ' pièce(s)'}
                value={<Amount value={total} size="lg" unit />}
              />
            </Ledger>
          </section>
          <fieldset className="checkout-guest__entry" disabled={busy}>
            <legend className="section-title">Récupérer les vêtements</legend>
            <div className="checkout-guest__choices">
              <label>
                <input
                  type="radio"
                  checked={fulfillment === 'pickup'}
                  onChange={() => setFulfillment('pickup')}
                />{' '}
                Retrait en boutique
              </label>
              <label>
                <input
                  type="radio"
                  checked={fulfillment === 'delivery'}
                  onChange={() => setFulfillment('delivery')}
                />{' '}
                Livraison
              </label>
            </div>
            <fieldset className="checkout-guest__payment">
              <legend className="section-title">Comment souhaitez-vous payer ?</legend>
              <p className="field__hint">
                Ce choix ne débite aucun compte. Le vendeur vérifiera lui-même la réception de votre
                argent avant de valider la vente.
              </p>
              <div className="checkout-guest__choices">
                <label>
                  <input
                    type="radio"
                    name="paymentMethod"
                    checked={paymentMethod === 'cash'}
                    onChange={() => setPaymentMethod('cash')}
                    required
                  />{' '}
                  Espèces
                </label>
                <label>
                  <input
                    type="radio"
                    name="paymentMethod"
                    checked={paymentMethod === 'mobile_money'}
                    onChange={() => setPaymentMethod('mobile_money')}
                    required
                  />{' '}
                  Mobile Money
                </label>
                <label>
                  <input
                    type="radio"
                    name="paymentMethod"
                    checked={paymentMethod === 'other'}
                    onChange={() => setPaymentMethod('other')}
                    required
                  />{' '}
                  Autre moyen
                </label>
              </div>
            </fieldset>
            <Field
              label="Votre téléphone"
              optional={fulfillment === 'pickup'}
              hint="Indispensable pour une livraison ; facultatif en boutique"
            >
              {(props) => (
                <input
                  {...props}
                  className="input"
                  value={phone}
                  type="tel"
                  autoComplete="tel"
                  maxLength={32}
                  required={fulfillment === 'delivery'}
                  placeholder="+242..."
                  onChange={(e) => setPhone(e.target.value)}
                />
              )}
            </Field>
            {fulfillment === 'delivery' && (
              <Field
                label="Adresse de livraison"
                hint="Précisez le quartier, la rue et un point de repère."
              >
                {(props) => (
                  <textarea
                    {...props}
                    className="input"
                    rows={2}
                    maxLength={240}
                    required
                    value={deliveryAddress}
                    placeholder="Ville, quartier, rue et point de repère"
                    onChange={(e) => setDeliveryAddress(e.target.value)}
                  />
                )}
              </Field>
            )}
            <Field
              label="Capture de l'article vu sur WhatsApp ou pendant un live"
              optional
              hint="Une capture facultative pour aider le vendeur à retrouver l'article. COVI ne crée pas de fiche produit ni de galerie de photos."
            >
              {(props) => (
                <input
                  {...props}
                  className="input"
                  type="file"
                  accept="image/jpeg,image/png,image/webp"
                  disabled={busy || photoBusy}
                  onChange={(event) => {
                    const file = event.target.files?.[0]
                    if (!file) {
                      setReferenceImage(null)
                      return
                    }
                    setPhotoBusy(true)
                    setReferenceImage(null)
                    setError('')
                    void prepareOrderReferencePhoto(file).then(
                      (encoded) => {
                        setReferenceImage(encoded)
                        setError('')
                      },
                      (reason) => {
                        setError(
                          reason instanceof Error
                            ? reason.message
                            : 'Impossible de préparer cette capture.',
                        )
                      },
                    ).finally(() => setPhotoBusy(false))
                  }}
                />
              )}
            </Field>
            {photoBusy && <p role="status">Préparation de la capture…</p>}
            {referenceImage && (
              <p role="status">
                Capture prête. Elle sera visible uniquement par cette boutique, dans votre demande.
                <Button variant="ghost" onClick={() => setReferenceImage(null)}>
                  Retirer la capture
                </Button>
              </p>
            )}
            <Field
              label="Précisions pour le vendeur"
              optional
              hint="Ex. : article montré pendant un live, couleur ou capture à retrouver"
            >
              {(props) => (
                <textarea
                  {...props}
                  className="input"
                  rows={3}
                  maxLength={500}
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                />
              )}
            </Field>
          </fieldset>
          {error && (
            <p className="field__error" role="alert">
              {error}
            </p>
          )}
          <TurnstileChallenge key={challengeVersion} onTokenChange={setChallenge} />
          <p className="checkout-guest__caution">
            Ne payez pas depuis cette page. Le vendeur confirmera votre demande, puis constatera la
            réception du paiement séparément.
          </p>
          <Button
            type="submit"
            block
            variant="sale"
            size="lg"
            busy={busy}
            busyLabel="Envoi de la demande…"
            disabled={
              busy ||
              photoBusy ||
              !challenge ||
              !lines.length ||
              !paymentMethod ||
              (fulfillment === 'delivery' && (!phone.trim() || !deliveryAddress.trim()))
            }
          >
            Envoyer la demande · {fcfa(total)} FCFA
          </Button>
        </form>
      </Sheet>
    </main>
  )
}
