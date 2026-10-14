import { useCallback, useEffect, useId, useMemo, useState } from 'react'
import { LoadError } from '../../components/LoadError'
import { useAsyncData } from '../../hooks/useAsyncData'
import { listSales } from '../../lib/covi'
import { money, plural } from '../../lib/format'
import { listShopMembers } from '../../lib/team'
import type { SoldItem } from '../../lib/types'
import { ALL, OWNER, sellerKey, sellerTotals } from './sellerTotals'
import { SoldRow } from './SoldRow'

/**
 * Every sold line, most recent sale first. Owner: summary and filter « Ventes par caissier ».
 * Cashier (`mine`): « Mes ventes », the server only returns what they may see.
 */
export function HistoryPage({
  shopId,
  mine = false,
  ownerId = null,
  sellerId,
}: {
  shopId: string
  /** Cashier space: title « Mes ventes », no seller filter. */
  mine?: boolean
  /** Owner's user id, to group their sales and the sales recorded before the team. */
  ownerId?: string | null
  /**
   * Counter mode on the owner's device: only the sales of this cashier (the owner's session can
   * read them all, so the filter is done here). Undefined: no filter.
   */
  sellerId?: string
}) {
  const load = useCallback(() => listSales(shopId), [shopId])
  const { data: rows, error, retry } = useAsyncData(load)
  const [names, setNames] = useState<Map<string, string>>(new Map())
  const [seller, setSeller] = useState(ALL)
  const filterId = useId()

  useEffect(() => {
    if (mine) return
    let active = true
    listShopMembers(shopId).then(
      (members) => {
        if (active) setNames(new Map(members.map((m) => [m.user_id, m.display_name])))
      },
      () => {},
    )
    return () => {
      active = false
    }
  }, [shopId, mine])

  const totals = useMemo(
    () => (rows && !mine ? sellerTotals(rows, ownerId, names) : []),
    [rows, mine, ownerId, names],
  )
  const hasTeam = totals.some((t) => t.key !== OWNER) || names.size > 0

  const items = useMemo<SoldItem[] | null>(
    () =>
      rows &&
      rows
        .filter((s) => {
          if (sellerId !== undefined) return s.seller_id === sellerId
          if (seller === ALL) return true
          return sellerKey(s.seller_id, ownerId) === seller
        })
        .flatMap((s) =>
          (s.sale_items ?? []).map((i) => ({
            ...i,
            sold_at: s.sold_at,
            payment_method: s.payment_method,
            id: s.id,
            is_test: s.is_test,
            seller_id: s.seller_id,
          })),
        ),
    [rows, seller, ownerId, sellerId],
  )
  return (
    <>
      <div className="hello">
        <div>
          <h1>{mine ? 'Mes ventes' : 'Produits vendus'}</h1>
          <span>
            {mine
              ? 'Les ventes que vous avez encaissées · les lignes TEST sont fictives.'
              : 'Historique des ventes · les lignes TEST sont fictives.'}
          </span>
        </div>
      </div>
      {!mine && hasTeam && totals.length > 0 && (
        <section className="card seller-totals" aria-labelledby={`${filterId}-title`}>
          <h2 id={`${filterId}-title`}>Ventes par caissier</h2>
          <ul>
            {totals.map((t) => (
              <li key={t.key}>
                <span>{t.name}</span>
                <span>
                  {plural(t.count, 'vente')} · <b>{money(t.total)}</b>
                </span>
              </li>
            ))}
          </ul>
          <label className="seller-filter" htmlFor={filterId}>
            Voir les ventes de
            <select id={filterId} value={seller} onChange={(e) => setSeller(e.target.value)}>
              <option value={ALL}>Tout le monde</option>
              {totals.map((t) => (
                <option key={t.key} value={t.key}>
                  {t.name}
                </option>
              ))}
            </select>
          </label>
        </section>
      )}
      {error ? (
        <LoadError
          message="Impossible de charger l’historique des ventes. Vérifiez votre connexion puis réessayez."
          onRetry={retry}
        />
      ) : (
        <section className="card">
          {items === null ? (
            <p>Chargement des ventes…</p>
          ) : items.length === 0 ? (
            <p>Aucune vente enregistrée.</p>
          ) : (
            items.map((x, i) => <SoldRow key={x.id + i} item={x} />)
          )}
        </section>
      )}
    </>
  )
}
