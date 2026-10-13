import { useCallback, useEffect, useState } from 'react'
import { Amount, Button, Ledger, LedgerRow, Notice, Sheet } from '../../components/ui'
import { approveManualCheckoutOrder, rejectCheckoutOrder } from '../../lib/manualOrder'
import { getPendingPublicOrders, type PendingPublicOrder } from '../../lib/publicOrders'
import { CashierCheckoutPanel } from './CashierCheckoutPanel'
import { watchCheckoutOrderUpdates } from '../../lib/checkoutInboxUpdates'

/** A private shop-owner inbox for incoming QR / social requests.
 * Client-suggested prices are ALWAYS reviewed before payment is confirmed.
 * No public page can access this component or the approval RPC.
 */
export function PublicOrderInbox({ shopId, shopName }: { shopId: string; shopName: string }) {
  const [orders, setOrders] = useState<PendingPublicOrder[]>([])
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState('')
  const [retry, setRetry] = useState(0)
  const [busyId, setBusyId] = useState<string | null>(null)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [selected, setSelected] = useState<PendingPublicOrder | null>(null)

  // New orders should appear without a manual refresh. Realtime acts only as a
  // signal; the authorized RPC remains the only source of displayed information.
  // Polling is a fallback while Realtime publication or connectivity is unavailable.
  const refresh = useCallback(async (silent: boolean, alive: () => boolean) => {
    if (!silent) setLoading(true)
    try {
      const rows = await getPendingPublicOrders(shopId)
      if (!alive()) return
      setOrders(rows)
      setLoadError('')
    } catch (reason) {
      if (!alive()) return
      setLoadError(reason instanceof Error ? reason.message : 'Demandes indisponibles.')
    } finally {
      if (alive()) setLoading(false)
    }
  }, [shopId])

  useEffect(() => {
    let active = true
    // Serialise overlapping responses to avoid reverting a more recent list.
    let latest = 0
    const load = (silent: boolean) => {
      const sequence = ++latest
      void refresh(silent, () => active && sequence === latest)
    }
    load(false)
    const stop = watchCheckoutOrderUpdates(shopId, () => load(true))
    const interval = window.setInterval(() => {
      if (document.visibilityState !== 'hidden') load(true)
    }, 15000)
    return () => {
      active = false
      window.clearInterval(interval)
      stop()
    }
  }, [shopId, retry, refresh])

  async function reject(order: PendingPublicOrder) {
    if (busyId || !window.confirm('Refuser cette commande sans encaisser ?')) return
    setError('')
    setNotice('')
    setBusyId(order.orderId)
    try {
      await rejectCheckoutOrder({ shopId, orderId: order.orderId })
      setOrders((current) => current.filter((item) => item.orderId !== order.orderId))
      setNotice('Demande refusée. Aucun paiement ni stock n’a été modifié.')
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Refus impossible.')
    } finally {
      setBusyId(null)
    }
  }

  async function approve(order: PendingPublicOrder) {
    if (busyId) return
    setError('')
    setBusyId(order.orderId)
    try {
      if (order.status === 'submitted') {
        const approved = await approveManualCheckoutOrder({
          shopId,
          orderId: order.orderId,
        })
        if (
          approved.orderId !== order.orderId ||
          approved.status !== 'approved' ||
          approved.amountXaf !== order.amountXaf
        ) {
          throw new Error('La validation du serveur ne correspond pas à la demande.')
        }
      }
      setSelected(order)
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Approbation impossible.')
    } finally {
      setBusyId(null)
    }
  }

  if (selected)
    return (
      <section className="checkout-inbox">
        <Button
          variant="secondary"
          onClick={() => {
            setSelected(null)
            setLoading(true)
            setRetry((x) => x + 1)
          }}
        >
          Retour aux commandes reçues
        </Button>
        <Sheet className="checkout-inbox__review">
          <p className="hand">À vérifier avant d'encaisser.</p>
          <h2>Commande {selected.orderId.slice(0, 8).toUpperCase()}</h2>
          <Ledger label="Articles du client">
            {selected.lines.map((line, index) => (
              <LedgerRow
                key={index}
                label={line.label + ' · ' + line.quantity + ' pièce(s)'}
                value={<Amount value={line.lineTotalXaf} unit />}
              />
            ))}
            <LedgerRow
              variant="total"
              label="Prix proposés par le client"
              value={<Amount value={selected.amountXaf} size="lg" unit />}
            />
          </Ledger>
          <p>
            Le commerçant a validé les quantités et les prix proposés. Confirmer le paiement
            uniquement après avoir constaté l'argent reçu.
          </p>
        </Sheet>
        <CashierCheckoutPanel
          shopId={shopId}
          shopName={shopName}
          orderId={selected.orderId}
          amountXaf={selected.amountXaf}
        />
      </section>
    )

  return (
    <Sheet className="checkout-inbox">
      <p className="hand">Les demandes arrivées au comptoir.</p>
      <div className="checkout-inbox__head">
        <h2>Commandes reçues</h2>
        <Button
          variant="secondary"
          disabled={loading}
          onClick={() => {
            setLoading(true)
            setRetry((x) => x + 1)
          }}
        >
          Actualiser
        </Button>
      </div>
      <p>Les commandes des clients sont en attente : rien n'est encaissé automatiquement.</p>
      {loading && <p role="status">Lecture des demandes…</p>}
      {loadError && (
        <Notice tone="danger">
          <p>{loadError}</p>
        </Notice>
      )}
      {error && (
        <Notice tone="danger">
          <p>{error}</p>
        </Notice>
      )}
      {notice && <p role="status">{notice}</p>}
      {!loading && !loadError && orders.length === 0 && (
        <p role="status">Aucune demande en attente. Partagez votre lien pour en recevoir.</p>
      )}
      {!loading && !loadError && (
        <div className="checkout-inbox__list">
          {orders.map((order) => (
            <article className="checkout-inbox__order" key={order.orderId}>
              <header>
                <strong className="figures">{order.orderId.slice(0, 8).toUpperCase()}</strong>
                <span>{order.channel === 'qr' ? 'QR en boutique' : 'Réseaux sociaux'}</span>
              </header>
              <p className="checkout-inbox__meta">
                {new Date(order.createdAt).toLocaleString('fr-FR')}
                {' · '}
                {order.fulfillment === 'delivery' ? 'Livraison' : 'Retrait en boutique'}
              </p>
              <Ledger label={'Demande ' + order.orderId.slice(0, 8)}>
                {order.lines.map((line, index) => (
                  <LedgerRow
                    key={index}
                    label={line.label + ' · ' + line.quantity + ' pièce(s)'}
                    value={<Amount value={line.lineTotalXaf} unit />}
                  />
                ))}
                <LedgerRow
                  variant="total"
                  label="Montant proposé"
                  value={<Amount value={order.amountXaf} unit />}
                />
              </Ledger>
              {order.customerPhone && <p>Téléphone : {order.customerPhone}</p>}
              {order.customerNote && <p>Note du client : {order.customerNote}</p>}
              <p className="checkout-inbox__notice">
                Vérifiez vous-même la disponibilité et les prix proposés avant d'approuver.
              </p>
              <Button
                variant="sale"
                block
                busy={busyId === order.orderId}
                disabled={Boolean(busyId)}
                onClick={() => {
                  void approve(order)
                }}
              >
                {order.status === 'approved'
                  ? 'Ouvrir la confirmation du paiement'
                  : 'Approuver et passer à l’encaissement'}
              </Button>
              <Button
                variant="secondary"
                block
                disabled={Boolean(busyId)}
                onClick={() => {
                  void reject(order)
                }}
              >
                Refuser cette demande
              </Button>
            </article>
          ))}
        </div>
      )}
    </Sheet>
  )
}
