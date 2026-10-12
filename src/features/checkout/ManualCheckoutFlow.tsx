import { useEffect, useRef, useState } from 'react'
import {
  listCheckoutStockCategories,
  type CheckoutStockCategory,
} from '../../lib/checkoutCategoryStock'
import {
  approveManualCheckoutOrder,
  createManualCheckoutOrder,
  prepareManualOrderLines,
  type ManualOrderLineInput,
  type RecordedManualOrder,
} from '../../lib/manualOrder'
import { Button, Notice, Sheet } from '../../components/ui'
import { CashierCheckoutPanel } from './CashierCheckoutPanel'
import { ManualCheckoutBasket } from './ManualCheckoutBasket'

type Props = {
  shopId: string
  shopName: string
  isTest?: boolean
}

/**
 * FUTURE owner-only checkout entry point, not mounted on App/Root/SalePage.
 * This reads NEW category inventory and requires the reviewed create, approve,
 * and manual-confirmation RPCs. It never touches the legacy product cashier.
 */
export function ManualCheckoutFlow(props: Props) {
  return (
    <ManualCheckoutFlowInstance
      key={props.shopId + ':' + Boolean(props.isTest)}
      {...props}
    />
  )
}

function ManualCheckoutFlowInstance({
  shopId,
  shopName,
  isTest = false,
}: Props) {
  const [categories, setCategories] = useState<CheckoutStockCategory[]>([])
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState('')
  const [retryCount, setRetryCount] = useState(0)
  const [approved, setApproved] = useState<RecordedManualOrder | null>(null)

  // Hold the operation UUID across transient network errors for the SAME cart.
  // A modified cart receives a NEW UUID, never reused with changed payload.
  const attempt = useRef<{ fingerprint: string; operationId: string } | null>(null)

  useEffect(() => {
    let cancelled = false
    listCheckoutStockCategories(shopId, isTest)
      .then((items) => {
        if (!cancelled) setCategories(items)
      })
      .catch((reason: unknown) => {
        if (!cancelled) setLoadError(
          reason instanceof Error ? reason.message : 'Stock indisponible.',
        )
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => { cancelled = true }
  }, [shopId, isTest, retryCount])

  async function prepare(lines: readonly ManualOrderLineInput[]) {
    const prepared = prepareManualOrderLines(lines)
    const fingerprint = JSON.stringify([shopId, isTest, prepared.lines])
    if (!attempt.current || attempt.current.fingerprint !== fingerprint) {
      attempt.current = { fingerprint, operationId: crypto.randomUUID() }
    }

    const created = await createManualCheckoutOrder({
      shopId,
      operationId: attempt.current.operationId,
      lines,
      isTest,
      fulfillment: 'pickup',
    })
    if (created.amountXaf !== prepared.amountXaf ||
        !['submitted', 'approved'].includes(created.status)) {
      throw new Error('La commande renvoyée ne correspond pas au panier.')
    }

    // Approval checks availability but NEVER decrements stock.
    const record = await approveManualCheckoutOrder({
      shopId,
      orderId: created.orderId,
    })
    if (record.orderId !== created.orderId ||
        record.amountXaf !== prepared.amountXaf) {
      throw new Error('Le montant approuvé ne correspond pas au panier.')
    }
    setApproved(record)
  }

  if (approved) {
    return (
      <div className="checkout-flow">
        <p className="hand checkout-flow__step">Commande vérifiée. À encaisser.</p>
        <CashierCheckoutPanel
          shopId={shopId}
          shopName={shopName}
          orderId={approved.orderId}
          amountXaf={approved.amountXaf}
        />
      </div>
    )
  }

  if (loading) {
    return (
      <Sheet className="checkout-flow__loading" aria-busy="true">
        <p className="hand">On ouvre le cahier…</p>
        <p>Chargement du stock par catégorie.</p>
      </Sheet>
    )
  }

  if (loadError) {
    return (
      <Notice tone="danger" title="Le stock n'est pas disponible.">
        <p>{loadError}</p>
        <Button
          variant="secondary"
          onClick={() => {
            setLoadError('')
            setLoading(true)
            setRetryCount((count) => count + 1)
          }}
        >
          Réessayer
        </Button>
      </Notice>
    )
  }

  return (
    <div className="checkout-flow">
      {isTest && (
        <p className="checkout-flow__demo" role="status">
          Boutique de démonstration — aucune vente réelle.
        </p>
      )}
      <ManualCheckoutBasket categories={categories} onPrepare={prepare} />
    </div>
  )
}
