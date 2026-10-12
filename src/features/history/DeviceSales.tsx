import { useEffect, useState } from 'react'
import { CloudUpIcon } from '../../components/icons'
import { Amount, Badge, Button, Ledger, LedgerRow, Notice } from '../../components/ui'
import { whenLabel } from '../../lib/dates'
import { paidWith, plural } from '../../lib/format'
import {
  cachedStock,
  clearRejectedSaleCount,
  pendingSales,
  rejectedSaleCount,
  rejectedSales,
} from '../../lib/offline'
import { refusedSales, waitingSales, type DeviceSale } from './offlineSales'

type DeviceState = { refused: DeviceSale[]; refusedCount: number; waiting: DeviceSale[] }

function readDevice(shopId: string): DeviceState {
  const names = new Map(
    cachedStock<{ id: string; name: string }>(shopId).map((p) => [p.id, p.name]),
  )
  const mine = <T extends { shopId: string }>(rows: T[]) => rows.filter((s) => s.shopId === shopId)
  const refused = refusedSales(mine(rejectedSales()), names)
  return {
    refused,
    // The count also covers older refusals kept without detail (before lib/offline kept them).
    refusedCount: Math.max(rejectedSaleCount(), refused.length),
    waiting: waitingSales(mine(pendingSales()), names),
  }
}

/** Sales kept on this device, refreshed whenever the queue moves (sent, refused, network back). */
function useDeviceSales(shopId: string) {
  const [state, setState] = useState(() => readDevice(shopId))
  useEffect(() => {
    const update = () => setState(readDevice(shopId))
    window.addEventListener('covi-sync', update)
    window.addEventListener('online', update)
    update()
    return () => {
      window.removeEventListener('covi-sync', update)
      window.removeEventListener('online', update)
    }
  }, [shopId])
  return state
}

const what = (s: DeviceSale) => (s.quantity > 1 ? `${s.quantity} × ${s.name}` : s.name)

/**
 * « Ventes non enregistrées » (the account refused them, the stock was put back) and « Ventes en
 * attente d’envoi » (kept on this device until the network comes back). Nothing when both are
 * empty.
 */
export function DeviceSales({ shopId }: { shopId: string }) {
  const { refused, refusedCount, waiting } = useDeviceSales(shopId)
  const older = refusedCount - refused.length
  return (
    <>
      {refusedCount > 0 && (
        <section
          className="device-sales device-sales--refused"
          aria-labelledby="ventes-non-enregistrees"
        >
          <h2 className="section-title" id="ventes-non-enregistrees">
            Ventes non enregistrées
          </h2>
          <p className="device-sales__lead">
            {refusedCount > 1
              ? `${refusedCount} ventes faites sans réseau n’ont pas pu être enregistrées sur votre compte.`
              : 'Une vente faite sans réseau n’a pas pu être enregistrée sur votre compte.'}
          </p>
          {refused.length > 0 && (
            <Ledger label="Ventes non enregistrées">
              {refused.map((s) => (
                <LedgerRow
                  key={s.id}
                  label={what(s)}
                  meta={
                    <>
                      {paidWith(s.paymentLabel)}, {whenLabel(s.at)}{' '}
                      <Badge tone="danger">Non enregistrée</Badge>
                      <span className="device-sales__reason">{s.reason}</span>
                    </>
                  }
                  value={<Amount value={s.amount} />}
                />
              ))}
            </Ledger>
          )}
          {older > 0 && (
            <p className="muted">
              {older > 1
                ? `Et ${older} plus anciennes, dont le détail n’a pas été gardé.`
                : 'Et 1 plus ancienne, dont le détail n’a pas été gardé.'}
            </p>
          )}
          <Notice tone="danger" live={false}>
            <p>
              <strong>Le stock a été remis</strong> comme avant sur cet appareil. Si vous avez bien
              encaissé cet argent, refaites la vente avec un autre article ou notez-le.
            </p>
          </Notice>
          <div className="device-sales__actions">
            <Button variant="primary" onClick={clearRejectedSaleCount}>
              J’ai compris
            </Button>
          </div>
        </section>
      )}

      {waiting.length > 0 && (
        <section className="device-sales" aria-labelledby="ventes-en-attente">
          <h2 className="section-title" id="ventes-en-attente">
            Ventes en attente d’envoi
          </h2>
          <Notice icon={CloudUpIcon} live={false}>
            <p>
              {waiting.length > 1
                ? `${plural(waiting.length, 'vente')} sont gardées sur cet appareil. Elles partiront toutes seules dès que le réseau revient, puis s’ajouteront au journal.`
                : '1 vente est gardée sur cet appareil. Elle partira toute seule dès que le réseau revient, puis s’ajoutera au journal.'}
            </p>
          </Notice>
          <Ledger label="Ventes en attente d’envoi">
            {waiting.map((s) => (
              <LedgerRow
                key={s.id}
                label={what(s)}
                meta={
                  <>
                    {paidWith(s.paymentLabel)}, {whenLabel(s.at)}{' '}
                    <Badge tone="waiting">À envoyer</Badge>
                  </>
                }
                value={<Amount value={s.amount} />}
              />
            ))}
          </Ledger>
        </section>
      )}
    </>
  )
}
