import { useCallback, useEffect, useState } from 'react'
import { Button, Ledger, LedgerRow, Notice } from '../../components/ui'
import { whenLabel } from '../../lib/dates'
import {
  listBlockedCustomers,
  orderErrorMessage,
  unblockCustomer,
  type BlockedCustomer,
} from '../../lib/publicOrders'

/** Clients bloqués (Commandes → QR & liens) : la boutique peut les débloquer à tout moment. */
export function BlockedCustomersPanel({ shopId }: { shopId: string }) {
  const [rows, setRows] = useState<BlockedCustomer[] | null>(null)
  const [error, setError] = useState('')
  const load = useCallback(
    () =>
      listBlockedCustomers(shopId).then(setRows, () => {
        setRows([])
      }),
    [shopId],
  )
  useEffect(() => {
    void load()
  }, [load])
  return (
    <section className="order-channel" aria-labelledby="blocked-title">
      <h2 className="section-title" id="blocked-title">
        Clients bloqués
      </h2>
      <p className="muted">
        Un client bloqué ne peut plus envoyer de commande à la boutique. Pour bloquer quelqu’un :
        ouvrez sa commande puis « Bloquer ou signaler ce client ».
      </p>
      {error && (
        <Notice tone="danger">
          <p>{error}</p>
        </Notice>
      )}
      {rows === null ? (
        <p className="muted">Chargement…</p>
      ) : rows.length === 0 ? (
        <p className="muted">Aucun client bloqué.</p>
      ) : (
        <Ledger label="Clients bloqués">
          {rows.map((c) => (
            <LedgerRow
              key={c.phoneKey}
              label={c.name ? `${c.name} · ${c.phone}` : c.phone}
              meta={`bloqué ${whenLabel(new Date(c.blockedAt))}`}
              value={
                <Button
                  variant="ghost"
                  onClick={async () => {
                    setError('')
                    try {
                      await unblockCustomer(shopId, c.phoneKey)
                      await load()
                    } catch (e) {
                      setError(orderErrorMessage(e))
                    }
                  }}
                >
                  Débloquer
                </Button>
              }
            />
          ))}
        </Ledger>
      )}
    </section>
  )
}
