import { useCallback, useEffect, useMemo, useState } from 'react'
import { CloudOffIcon, PlusIcon } from '../../components/icons'
import { Button, ButtonLink, EmptyState, Notice, SearchField, Skeleton } from '../../components/ui'
import { listProducts } from '../../lib/covi'
import { plural, pluralize } from '../../lib/format'
import { stockCacheDate } from '../../lib/offline'
import { listArrivals } from '../../lib/operations'
import type { Arrival, Product } from '../../lib/types'
import '../../styles/app/stock.css'
import { ProductSheet } from './ProductSheet'
import { StockFilters } from './StockFilters'
import {
  filterCounts,
  filterStock,
  keptStockLabel,
  piecesInShop,
  type StockFilter,
} from './stockFilters'
import { StockRow } from './StockRow'

function useOnline() {
  const [online, setOnline] = useState(() => navigator.onLine)
  useEffect(() => {
    const update = () => setOnline(navigator.onLine)
    window.addEventListener('online', update)
    window.addEventListener('offline', update)
    return () => {
      window.removeEventListener('online', update)
      window.removeEventListener('offline', update)
    }
  }, [])
  return online
}

const filterEmpty: Record<StockFilter, string> = {
  all: 'Aucun article pour cet arrivage.',
  low: 'Aucun modèle bientôt épuisé. Tout va bien de ce côté.',
  unique: 'Aucune pièce unique en ce moment.',
}

/**
 * Stock: how many pieces are in the shop, then the notebook lines (photo or initial, name, type ·
 * brand · size, what is left, where it came from, displayed price), with an instant local search
 * and simple filters. Adding an article opens a sheet. Without network, the copy kept on the
 * device is shown, calmly dated.
 */
export function StockPage({ shopId }: { shopId: string }) {
  const online = useOnline()
  const [products, setProducts] = useState<Product[] | null>(null)
  const [failed, setFailed] = useState(false)
  const [arrivals, setArrivals] = useState<Arrival[]>([])
  const [attempt, setAttempt] = useState(0)
  const [query, setQuery] = useState('')
  const [filter, setFilter] = useState<StockFilter>('all')
  const [arrival, setArrival] = useState('')
  const [adding, setAdding] = useState(false)
  const [added, setAdded] = useState<string | null>(null)

  const load = useCallback(
    () =>
      listProducts(shopId, false, true).then(
        (rows) => {
          setProducts(rows)
          setFailed(false)
        },
        () => setFailed(true),
      ),
    [shopId],
  )

  useEffect(() => {
    void load()
    // Arrival codes (BAL-003…) for the lines, the filter and the form: optional.
    listArrivals(shopId).then(setArrivals, () => {})
  }, [shopId, load, attempt])

  // The network comes back, or sales kept on the device were sent: the stock moved.
  useEffect(() => {
    const reload = () => void load()
    window.addEventListener('online', reload)
    window.addEventListener('covi-sync', reload)
    return () => {
      window.removeEventListener('online', reload)
      window.removeEventListener('covi-sync', reload)
    }
  }, [load])

  const codes = useMemo(() => new Map(arrivals.map((a) => [a.id, a.code])), [arrivals])
  const visible = useMemo(
    () => filterStock(products ?? [], { query, filter, arrival, codes }),
    [products, query, filter, arrival, codes],
  )
  const counts = useMemo(() => filterCounts(products ?? []), [products])
  // Only the arrivals some article comes from are offered in the filter.
  const usedArrivals = useMemo(
    () => arrivals.filter((a) => (products ?? []).some((p) => p.arrival_id === a.id)),
    [arrivals, products],
  )
  const received = useMemo(() => arrivals.filter((a) => a.status === 'received'), [arrivals])
  const pieces = piecesInShop(products ?? [])

  const add = () => {
    setAdded(null)
    setAdding(true)
  }

  return (
    <div className="stock">
      <header className="page-head stock-head">
        <div>
          <h1>Stock</h1>
          {products && products.length > 0 && (
            <p className="stock-head__count">
              <strong className="figures">{pieces}</strong> {pluralize(pieces, 'pièce')} en boutique
            </p>
          )}
        </div>
        {products?.length !== 0 && (
          <Button variant="primary" icon={<PlusIcon />} onClick={add}>
            Ajouter au stock
          </Button>
        )}
      </header>

      {!online && products !== null && (
        <Notice icon={CloudOffIcon} title={keptStockLabel(stockCacheDate(shopId))}>
          <p>Pas de réseau. Pour ajouter un article, attendez qu’il revienne.</p>
        </Notice>
      )}

      {added && (
        <Notice tone="success" className="stock-added">
          <p>{added} est en stock.</p>
        </Notice>
      )}

      {products === null && !failed && <Skeleton caption="On sort le stock…" />}

      {products === null && failed && (
        <Notice
          icon={CloudOffIcon}
          title="Le stock ne s’affiche pas : pas de réseau."
          actions={
            <Button variant="secondary" onClick={() => setAttempt((n) => n + 1)}>
              Réessayer
            </Button>
          }
        >
          <p>Réessayez dans un instant.</p>
        </Notice>
      )}

      {products !== null && products.length === 0 && (
        <EmptyState
          title="Pas encore de produits."
          actions={
            <>
              <Button variant="primary" onClick={add}>
                Ajouter au stock
              </Button>
              <ButtonLink variant="secondary" href="#/arrivages">
                Nouvel arrivage
              </ButtonLink>
            </>
          }
        >
          <p>Ajoutez votre premier article ou enregistrez un arrivage.</p>
        </EmptyState>
      )}

      {products !== null && products.length > 0 && (
        <section className="stock-book" aria-label="Articles en stock">
          <SearchField
            className="stock-search"
            label="Chercher un article"
            placeholder="Nom, type, marque, BAL-003…"
            value={query}
            onChange={setQuery}
          />
          <StockFilters
            filter={filter}
            onFilter={setFilter}
            counts={counts}
            arrival={arrival}
            onArrival={setArrival}
            arrivals={usedArrivals}
            hasLoose={(products ?? []).some((p) => !p.arrival_id)}
          />
          {visible.length > 0 ? (
            <>
              <p className="stock-shown" aria-live="polite">
                {visible.length === products.length
                  ? plural(visible.length, 'article')
                  : `${plural(visible.length, 'article')} sur ${products.length}`}
              </p>
              <ul className="stock-list">
                {visible.map((p) => (
                  <StockRow
                    key={p.id}
                    product={p}
                    arrivalCode={p.arrival_id ? codes.get(p.arrival_id) : undefined}
                  />
                ))}
              </ul>
            </>
          ) : (
            <p className="stock-none" role="status">
              {query.trim()
                ? `Rien ne correspond à « ${query.trim()} ». Vérifiez l’orthographe.`
                : filterEmpty[filter]}
            </p>
          )}
        </section>
      )}

      <ProductSheet
        open={adding}
        onClose={() => setAdding(false)}
        shopId={shopId}
        arrivals={received}
        onSaved={(product) => {
          setAdding(false)
          setAdded(product.name)
          void load()
        }}
      />
    </div>
  )
}
