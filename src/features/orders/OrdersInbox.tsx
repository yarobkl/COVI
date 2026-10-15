import { useCallback, useEffect, useId, useRef, useState } from 'react'
import { Button, Dialog, Notice } from '../../components/ui'
import { money } from '../../lib/format'
import {
  acceptOrder,
  confirmOrderPayment,
  listOrders,
  orderErrorMessage,
  paymentMethodLabels,
  paymentMethods,
  referencePhotoUrl,
  rejectOrder,
  statusLabels,
  type InboxOrder,
  type PaymentMethod,
} from '../../lib/publicOrders'
import {
  closeSharedCashierTill,
  listSharedCashiers,
  openSharedCashierTill,
  type SharedCashier,
} from '../../lib/sharedCashiers'
import {
  getOpenPaySettings,
  guessProvider,
  listOrderPayments,
  mobilePaymentsEnabled,
  mobileStatusLabels,
  normalizeCongoPhone,
  providerLabels,
  refreshMobilePayment,
  requestMobilePayment,
  type MobileProvider,
  type OrderMobilePayment,
} from '../../lib/mobilePayments'
import { pinResultMessage, type TillSession } from '../../lib/team'
import { supabase } from '../../lib/supabase'

const POLL_LIVE_MS = 60_000
const POLL_FALLBACK_MS = 15_000

const dateTime = (iso: string) =>
  new Date(iso).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })

type StockChoice = { id: string; name: string; price: number; quantity: number }

/**
 * Commandes reçues par QR code ou lien WhatsApp / TikTok. Nouvelles demandes en temps réel
 * (Supabase Realtime), avec une actualisation régulière de secours si le temps réel est coupé.
 * Encaisser une commande = confirmer le règlement réellement reçu, avec le PIN d'un caissier :
 * la vente est alors enregistrée et le stock diminue, une seule fois.
 */
export function OrdersInbox({ shopId, till }: { shopId: string; till?: TillSession | null }) {
  const [orders, setOrders] = useState<InboxOrder[] | null>(null)
  const [error, setError] = useState('')
  const [live, setLive] = useState(false)
  const [showClosed, setShowClosed] = useState(false)
  const [confirming, setConfirming] = useState<InboxOrder | null>(null)
  const [rejecting, setRejecting] = useState<InboxOrder | null>(null)
  const [fresh, setFresh] = useState<Set<string>>(new Set())
  const [payments, setPayments] = useState<Map<string, OrderMobilePayment>>(new Map())
  const [mobileReady, setMobileReady] = useState(false)
  const [requesting, setRequesting] = useState<InboxOrder | null>(null)
  const known = useRef<Set<string> | null>(null)

  const load = useCallback(() => {
    listOrders(shopId, showClosed)
      .then((list) => {
        setOrders(list)
        setError('')
        const ids = new Set(list.map((o) => o.id))
        if (known.current) {
          const added = list.filter((o) => o.status === 'new' && !known.current?.has(o.id))
          if (added.length) setFresh((f) => new Set([...f, ...added.map((o) => o.id)]))
        }
        known.current = ids
      })
      .catch((e) => setError(orderErrorMessage(e)))
    // Paiements Mobile Money (OpenPay) : facultatifs, jamais bloquants pour les commandes.
    if (mobilePaymentsEnabled)
      listOrderPayments(shopId)
        .then(setPayments)
        .catch(() => undefined)
  }, [shopId, showClosed])

  useEffect(() => {
    if (!mobilePaymentsEnabled) return
    getOpenPaySettings(shopId)
      .then((s) => setMobileReady(Boolean(s?.configured && s.enabled)))
      .catch(() => setMobileReady(false))
  }, [shopId])

  useEffect(() => {
    load()
    const channel = supabase
      .channel(`covi-orders-${shopId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'public_orders', filter: `shop_id=eq.${shopId}` },
        () => load(),
      )
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'public_order_payments',
          filter: `shop_id=eq.${shopId}`,
        },
        () => load(),
      )
      .subscribe((status) => setLive(status === 'SUBSCRIBED'))
    return () => {
      void supabase.removeChannel(channel)
    }
  }, [shopId, load])

  // Secours : actualisation régulière, plus fréquente si le temps réel est indisponible.
  useEffect(() => {
    const timer = window.setInterval(
      () => {
        if (document.visibilityState === 'visible') load()
      },
      live ? POLL_LIVE_MS : POLL_FALLBACK_MS,
    )
    const onFocus = () => load()
    window.addEventListener('focus', onFocus)
    return () => {
      window.clearInterval(timer)
      window.removeEventListener('focus', onFocus)
    }
  }, [live, load])

  const pending = (orders ?? []).filter((o) => o.status === 'new' || o.status === 'accepted')
  const newCount = (orders ?? []).filter((o) => o.status === 'new').length

  return (
    <section className="orders-inbox" aria-label="Commandes reçues">
      <div className="orders-inbox__head">
        <h2>Commandes reçues</h2>
        <p className="muted" role="status">
          {live ? 'Mises à jour en direct' : 'Actualisation automatique toutes les 15 secondes'}
        </p>
      </div>
      {newCount > 0 && (
        <Notice
          tone="success"
          title={`${newCount} nouvelle${newCount > 1 ? 's' : ''} demande${newCount > 1 ? 's' : ''}`}
        >
          <p>Vérifiez le stock, contactez le client, puis encaissez quand le règlement est reçu.</p>
        </Notice>
      )}
      {error && (
        <Notice tone="danger">
          <p>{error}</p>
        </Notice>
      )}
      {orders === null && !error && <p role="status">Chargement des commandes…</p>}
      {orders !== null && pending.length === 0 && (
        <p className="muted">
          Aucune commande en attente. Les nouvelles demandes apparaissent ici.
        </p>
      )}
      <ul className="orders-inbox__list">
        {(orders ?? []).map((o) => (
          <OrderCard
            key={o.id}
            order={o}
            fresh={fresh.has(o.id)}
            onAccept={async () => {
              try {
                await acceptOrder(o.id)
                load()
              } catch (e) {
                setError(orderErrorMessage(e))
              }
            }}
            onConfirm={() => setConfirming(o)}
            onReject={() => setRejecting(o)}
            payment={payments.get(o.id) ?? null}
            mobileReady={mobileReady}
            onRequestMobile={() => setRequesting(o)}
            onRefreshMobile={async (paymentId) => {
              try {
                await refreshMobilePayment(paymentId)
              } catch (e) {
                setError((e as Error).message)
              }
              load()
            }}
          />
        ))}
      </ul>
      <Button variant="ghost" onClick={() => setShowClosed((v) => !v)}>
        {showClosed ? 'Masquer les commandes anciennes' : 'Afficher aussi les commandes anciennes'}
      </Button>
      {confirming && (
        <ConfirmPaymentDialog
          shopId={shopId}
          order={confirming}
          payment={payments.get(confirming.id) ?? null}
          till={till ?? null}
          onClose={() => setConfirming(null)}
          onDone={() => {
            setConfirming(null)
            load()
          }}
        />
      )}
      {requesting && (
        <MobilePaymentDialog
          order={requesting}
          onClose={() => setRequesting(null)}
          onDone={() => {
            setRequesting(null)
            load()
          }}
        />
      )}
      {rejecting && (
        <RejectDialog
          order={rejecting}
          onClose={() => setRejecting(null)}
          onDone={() => {
            setRejecting(null)
            load()
          }}
        />
      )}
    </section>
  )
}

function OrderCard({
  order,
  fresh,
  onAccept,
  onConfirm,
  onReject,
  payment,
  mobileReady,
  onRequestMobile,
  onRefreshMobile,
}: {
  order: InboxOrder
  fresh: boolean
  onAccept: () => void
  onConfirm: () => void
  onReject: () => void
  payment: OrderMobilePayment | null
  mobileReady: boolean
  onRequestMobile: () => void
  onRefreshMobile: (paymentId: string) => void
}) {
  const [photo, setPhoto] = useState<string | null>(null)
  const [photoError, setPhotoError] = useState('')
  const open = order.status === 'new' || order.status === 'accepted'
  const whatsapp = order.customerPhone.replace(/[^0-9]/g, '')
  return (
    <li className={`order-card order-card--${order.status}${fresh ? ' order-card--fresh' : ''}`}>
      <header className="order-card__head">
        <b>{order.reference}</b>
        <span className={`order-status order-status--${order.status}`}>
          {statusLabels[order.status]}
        </span>
      </header>
      <p>
        <b>{order.customerName}</b> ·{' '}
        <a href={`tel:${order.customerPhone}`}>{order.customerPhone}</a>
        {whatsapp.length >= 8 && (
          <>
            {' '}
            ·{' '}
            <a href={`https://wa.me/${whatsapp}`} target="_blank" rel="noreferrer">
              WhatsApp
            </a>
          </>
        )}
      </p>
      <p className="muted">
        {dateTime(order.createdAt)} ·{' '}
        {order.channel === 'social' ? 'Lien réseaux sociaux' : 'QR code'} ·{' '}
        {order.fulfillment === 'delivery'
          ? `Livraison : ${order.deliveryAddress ?? ''}`
          : 'Retrait en boutique'}
      </p>
      <ul className="order-card__lines">
        {order.lines.map((l) => (
          <li key={l.id}>
            {l.quantity} × {l.productName ?? l.description}
            {l.proposedUnitPriceXaf != null
              ? ` — prix proposé ${money(l.proposedUnitPriceXaf)} (affiché ${l.listedUnitPriceXaf != null ? money(l.listedUnitPriceXaf) : '—'})`
              : l.listedUnitPriceXaf != null
                ? ` — ${money(l.listedUnitPriceXaf)}`
                : ''}
            {open && l.productId && (l.availableQuantity ?? 0) < l.quantity && (
              <b className="order-card__warn"> · stock insuffisant ({l.availableQuantity ?? 0})</b>
            )}
          </li>
        ))}
      </ul>
      <p>
        Règlement souhaité : <b>{paymentMethodLabels[order.paymentMethod]}</b>
        {order.requestedTotalXaf > 0 && ` · total indicatif ${money(order.requestedTotalXaf)}`}
      </p>
      {order.note && <p className="order-card__note">« {order.note} »</p>}
      {order.referenceImagePath && (
        <p>
          {photo ? (
            <img className="order-card__photo" src={photo} alt="Photo de référence du client" />
          ) : (
            <Button
              variant="ghost"
              onClick={async () => {
                const url = await referencePhotoUrl(order.referenceImagePath ?? '')
                setPhoto(url)
                setPhotoError(url ? '' : 'La photo n’a pas pu être ouverte. Réessayez.')
              }}
            >
              Voir la photo du client
            </Button>
          )}
          {photoError && (
            <span className="field__error" role="alert">
              {photoError}
            </span>
          )}
        </p>
      )}
      {order.status === 'paid' && (
        <p className="order-card__paid">
          Encaissée le {order.confirmedAt ? dateTime(order.confirmedAt) : ''} ·{' '}
          {order.paidMethod ? paymentMethodLabels[order.paidMethod] : ''}
          {order.paymentReference ? ` · Transaction externe : ${order.paymentReference}` : ''}
          {order.cashierName ? ` · caisse de ${order.cashierName}` : ''}
          {order.internalReference && (
            <span>
              {' '}
              · Référence COVI : <b>{order.internalReference}</b>
            </span>
          )}
        </p>
      )}
      {payment && (
        <p className={`order-card__mobile order-card__mobile--${payment.status}`} role="status">
          {providerLabels[payment.provider]} · {money(payment.amount)} :{' '}
          <b>{mobileStatusLabels[payment.status]}</b>
          {payment.reference ? ` · réf. ${payment.reference}` : ''}
          {payment.status === 'error' && payment.message ? ` (${payment.message})` : ''}
          {open && (payment.status === 'pending' || payment.status === 'requested') && (
            <>
              {' '}
              <Button variant="ghost" onClick={() => onRefreshMobile(payment.id)}>
                Vérifier maintenant
              </Button>
            </>
          )}
        </p>
      )}
      {order.status === 'rejected' && order.rejectReason && (
        <p>Motif du refus : {order.rejectReason}</p>
      )}
      {open && (
        <div className="order-card__actions">
          {order.status === 'new' && (
            <Button variant="secondary" onClick={onAccept}>
              Accepter la commande
            </Button>
          )}
          {mobileReady &&
            payment?.status !== 'success' &&
            payment?.status !== 'pending' &&
            payment?.status !== 'requested' && (
              <Button variant="secondary" onClick={onRequestMobile}>
                Demander le paiement Mobile Money
              </Button>
            )}
          <Button variant="primary" onClick={onConfirm}>
            Règlement reçu — encaisser
          </Button>
          <Button variant="ghost" onClick={onReject}>
            Refuser
          </Button>
        </div>
      )}
    </li>
  )
}

/**
 * Demande de paiement Mobile Money via OpenPay : le client reçoit une notification sur son téléphone
 * et valide avec son code secret. Rien n'est encaissé ici ; le paiement ne compte qu'une fois
 * confirmé par OpenPay, puis la vente est enregistrée en caisse comme d'habitude.
 */
function MobilePaymentDialog({
  order,
  onClose,
  onDone,
}: {
  order: InboxOrder
  onClose: () => void
  onDone: () => void
}) {
  const titleId = useId()
  const [phone, setPhone] = useState(order.customerPhone)
  const [provider, setProvider] = useState<MobileProvider>(() => guessProvider(order.customerPhone))
  const [amount, setAmount] = useState(
    order.requestedTotalXaf > 0 ? String(Math.round(order.requestedTotalXaf)) : '',
  )
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const normalized = normalizeCongoPhone(phone)
  const value = Number(amount)
  const ready = Boolean(normalized) && Number.isSafeInteger(value) && value > 0 && !busy
  return (
    <Dialog open onClose={() => !busy && onClose()} labelledBy={titleId} sheet>
      <div className="dialog__body order-confirm">
        <h2 className="dialog__title" id={titleId}>
          Paiement Mobile Money — {order.reference}
        </h2>
        <p className="muted">
          Le client reçoit une demande sur son téléphone et la valide avec son code secret. Le
          paiement arrive sur le compte OpenPay de la boutique.
        </p>
        <label>
          Numéro Mobile Money du client
          <input
            className="input"
            inputMode="tel"
            value={phone}
            maxLength={20}
            onChange={(e) => {
              setPhone(e.target.value)
              setProvider(guessProvider(e.target.value))
            }}
          />
        </label>
        <label>
          Opérateur
          <select
            className="select"
            value={provider}
            onChange={(e) => setProvider(e.target.value as MobileProvider)}
          >
            <option value="MTN">{providerLabels.MTN}</option>
            <option value="AIRTEL">{providerLabels.AIRTEL}</option>
          </select>
        </label>
        <label>
          Montant à payer (FCFA)
          <input
            className="input input--amount"
            inputMode="numeric"
            value={amount}
            onChange={(e) => setAmount(e.target.value.replace(/\D/g, '').slice(0, 8))}
          />
        </label>
        {phone && !normalized && (
          <p className="field__error">Numéro invalide : 06 XXX XX XX ou 05 XXX XX XX.</p>
        )}
        {error && (
          <Notice tone="danger">
            <p>{error}</p>
          </Notice>
        )}
        <div className="dialog__actions">
          <Button variant="secondary" disabled={busy} onClick={onClose}>
            Annuler
          </Button>
          <Button
            variant="primary"
            busy={busy}
            disabled={!ready}
            onClick={async () => {
              setBusy(true)
              setError('')
              try {
                await requestMobilePayment({
                  orderId: order.id,
                  provider,
                  phone: normalized ?? '',
                  amount: value,
                })
                onDone()
              } catch (e) {
                setError((e as Error).message)
                setBusy(false)
              }
            }}
          >
            Envoyer la demande de {value > 0 ? money(value) : 'paiement'}
          </Button>
        </div>
      </div>
    </Dialog>
  )
}

function RejectDialog({
  order,
  onClose,
  onDone,
}: {
  order: InboxOrder
  onClose: () => void
  onDone: () => void
}) {
  const titleId = useId()
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  return (
    <Dialog open onClose={() => !busy && onClose()} labelledBy={titleId} sheet>
      <div className="dialog__body">
        <h2 className="dialog__title" id={titleId}>
          Refuser la commande {order.reference}
        </h2>
        <label>
          Motif visible par le client (facultatif)
          <input
            className="input"
            value={reason}
            maxLength={240}
            onChange={(e) => setReason(e.target.value)}
            placeholder="Ex. article déjà vendu"
          />
        </label>
        {error && (
          <Notice tone="danger">
            <p>{error}</p>
          </Notice>
        )}
        <div className="dialog__actions">
          <Button variant="secondary" disabled={busy} onClick={onClose}>
            Annuler
          </Button>
          <Button
            variant="primary"
            busy={busy}
            onClick={async () => {
              setBusy(true)
              try {
                await rejectOrder(order.id, reason)
                onDone()
              } catch (e) {
                setError(orderErrorMessage(e))
                setBusy(false)
              }
            }}
          >
            Refuser
          </Button>
        </div>
      </div>
    </Dialog>
  )
}

/**
 * Confirmation du règlement réellement reçu. Le caissier vérifie chaque article et son prix, le
 * moyen de règlement effectif et confirme explicitement sa réception. La référence du prestataire
 * est facultative ; COVI génère sa propre référence après l'encaissement.
 * Sans session de caisse ouverte, le PIN d'un caissier est demandé ici même.
 */
function ConfirmPaymentDialog({
  shopId,
  order,
  payment,
  till,
  onClose,
  onDone,
}: {
  shopId: string
  order: InboxOrder
  payment: OrderMobilePayment | null
  till: TillSession | null
  onClose: () => void
  onDone: () => void
}) {
  const titleId = useId()
  const [stock, setStock] = useState<StockChoice[] | null>(null)
  const [cashiers, setCashiers] = useState<SharedCashier[] | null>(till ? [] : null)
  const [cashierId, setCashierId] = useState('')
  const [pin, setPin] = useState('')
  const [lines, setLines] = useState(() =>
    order.lines.map((l) => ({
      lineId: l.id,
      productId: l.productId ?? '',
      price: String(l.proposedUnitPriceXaf ?? l.listedUnitPriceXaf ?? l.currentPriceXaf ?? ''),
      locked: Boolean(l.productId),
      label: l.productName ?? l.description ?? '',
      quantity: l.quantity,
    })),
  )
  const paidByMobile = payment?.status === 'success'
  const [method, setMethod] = useState<PaymentMethod>(
    paidByMobile ? 'mobile_money' : order.paymentMethod,
  )
  const [reference, setReference] = useState(paidByMobile ? (payment?.reference ?? '') : '')
  const [verified, setVerified] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    void supabase
      .from('products')
      .select('id, name, initial_sale_price, quantity_on_hand')
      .eq('shop_id', shopId)
      .eq('status', 'active')
      .gt('quantity_on_hand', 0)
      .order('name')
      .limit(1000)
      .then(({ data }) =>
        setStock(
          (data ?? []).map((p) => ({
            id: p.id,
            name: p.name,
            price: Number(p.initial_sale_price),
            quantity: p.quantity_on_hand,
          })),
        ),
      )
    if (!till)
      listSharedCashiers(shopId)
        .then((list) => setCashiers(list.filter((c) => c.active)))
        .catch(() => setCashiers([]))
  }, [shopId, till])

  const needsPin = !till && (cashiers?.length ?? 0) > 0
  const linesOk = lines.every((l) => l.productId && l.price !== '' && Number(l.price) >= 0)
  const total = lines.reduce((s, l) => s + Number(l.price || 0) * l.quantity, 0)
  const ready = linesOk && verified && (!needsPin || (cashierId && /^\d{4,6}$/.test(pin))) && !busy

  const submit = async () => {
    setBusy(true)
    setError('')
    let opened: string | null = null
    try {
      let token = till?.token ?? null
      if (needsPin) {
        const result = await openSharedCashierTill(shopId, cashierId, pin)
        if ('refused' in result) {
          setError(pinResultMessage(result.refused))
          setBusy(false)
          return
        }
        token = result.session.token
        opened = token
      }
      await confirmOrderPayment({
        orderId: order.id,
        paidMethod: method,
        paymentReference: reference.trim() || null,
        paymentVerified: verified,
        lines: lines.map((l) => ({
          lineId: l.lineId,
          productId: l.productId,
          unitPriceXaf: Math.round(Number(l.price)),
        })),
        tillToken: token,
      })
      onDone()
    } catch (e) {
      setError(orderErrorMessage(e))
    } finally {
      if (opened) void closeSharedCashierTill(shopId, opened).catch(() => undefined)
      setBusy(false)
    }
  }

  return (
    <Dialog open onClose={() => !busy && onClose()} labelledBy={titleId} sheet>
      <div className="dialog__body order-confirm">
        <h2 className="dialog__title" id={titleId}>
          Encaisser la commande {order.reference}
        </h2>
        <p className="muted">
          {order.customerName} · règlement souhaité : {paymentMethodLabels[order.paymentMethod]}
        </p>
        {paidByMobile && payment && (
          <Notice tone="success">
            <p>
              OpenPay confirme le paiement de {money(payment.amount)} par{' '}
              {providerLabels[payment.provider]} (réf. {payment.reference}).
            </p>
          </Notice>
        )}
        {lines.map((l, i) => (
          <fieldset key={l.lineId} className="order-confirm__line">
            <legend>
              {l.quantity} × {l.label}
            </legend>
            {!l.locked && (
              <label>
                Article du stock
                <select
                  className="select"
                  value={l.productId}
                  onChange={(e) => {
                    const p = stock?.find((s) => s.id === e.target.value)
                    setLines((all) =>
                      all.map((x, j) =>
                        j === i
                          ? {
                              ...x,
                              productId: e.target.value,
                              price: x.price || String(p?.price ?? ''),
                            }
                          : x,
                      ),
                    )
                  }}
                >
                  <option value="">Choisir l’article…</option>
                  {(stock ?? []).map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.name} — {money(p.price)} ({p.quantity} en stock)
                    </option>
                  ))}
                </select>
              </label>
            )}
            <label>
              Prix unitaire final (FCFA)
              <input
                className="input input--amount"
                inputMode="numeric"
                value={l.price}
                onChange={(e) =>
                  setLines((all) =>
                    all.map((x, j) =>
                      j === i ? { ...x, price: e.target.value.replace(/\D/g, '').slice(0, 9) } : x,
                    ),
                  )
                }
              />
            </label>
          </fieldset>
        ))}
        <p className="order-guest__total">
          Total à encaisser : <b>{money(total)}</b>
        </p>
        <label>
          Règlement effectivement reçu
          <select
            className="select"
            value={method}
            onChange={(e) => setMethod(e.target.value as PaymentMethod)}
          >
            {paymentMethods.map((m) => (
              <option key={m} value={m}>
                {paymentMethodLabels[m]}
              </option>
            ))}
          </select>
        </label>
        <label>
          Numéro de transaction externe (facultatif)
          <input
            className="input"
            value={reference}
            maxLength={64}
            placeholder={
              method === 'mobile_money'
                ? 'Référence SMS si disponible'
                : method === 'card'
                  ? 'Référence du ticket, si disponible'
                  : method === 'bank_transfer'
                    ? 'Référence du virement, si disponible'
                    : 'Aucune référence nécessaire'
            }
            onChange={(e) => setReference(e.target.value)}
          />
        </label>
        <p className="muted">
          La référence COVI sera générée automatiquement après confirmation. Un numéro externe n’est
          jamais obligatoire et ne prouve pas, à lui seul, que le paiement est reçu.
        </p>
        <label className="order-confirm__check">
          <input
            type="checkbox"
            checked={verified}
            onChange={(e) => setVerified(e.target.checked)}
          />
          J’ai vérifié que le règlement de {money(total)} est bien reçu.
        </label>
        {till ? (
          <p className="muted">Encaissé par la caisse de {till.displayName}.</p>
        ) : needsPin ? (
          <>
            <label>
              Caissier
              <select
                className="select"
                value={cashierId}
                onChange={(e) => setCashierId(e.target.value)}
              >
                <option value="">Choisir…</option>
                {(cashiers ?? []).map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.display_name}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Code PIN du caissier
              <input
                className="input"
                type="password"
                inputMode="numeric"
                autoComplete="off"
                maxLength={6}
                value={pin}
                onChange={(e) => setPin(e.target.value.replace(/\D/g, ''))}
              />
            </label>
          </>
        ) : null}
        {error && (
          <Notice tone="danger">
            <p>{error}</p>
          </Notice>
        )}
        <div className="dialog__actions">
          <Button variant="secondary" disabled={busy} onClick={onClose}>
            Annuler
          </Button>
          <Button variant="primary" busy={busy} disabled={!ready} onClick={() => void submit()}>
            Confirmer et enregistrer la vente
          </Button>
        </div>
      </div>
    </Dialog>
  )
}
