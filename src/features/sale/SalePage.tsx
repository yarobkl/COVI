import { useCallback, useEffect, useId, useMemo, useRef, useState } from 'react'
import {
  Amount,
  Button,
  ButtonLink,
  Dialog,
  EmptyState,
  Notice,
  SearchField,
  Skeleton,
} from '../../components/ui'
import { CloudOffIcon } from '../../components/icons'
import { DESKTOP, useMediaQuery } from '../../hooks/useMediaQuery'
import { listProducts } from '../../lib/covi'
import { plural } from '../../lib/format'
import { listArrivals, todaySales } from '../../lib/operations'
import type { Product } from '../../lib/types'
import { SaleDone } from './SaleDone'
import { SaleForm, type SoldSale } from './SaleForm'
import { SaleTile } from './SaleTile'
import { matchesSearch } from './saleMath'

type Today = { count: number; total: number } | null

/**
 * Vendre: find the article (instant local search), touch it, agree on the price and the payment,
 * validate — one article per sale, as the server records it. Phone: the sale opens in a sheet;
 * computer: beside the articles.
 */
export function SalePage({ shopId, shopName }: { shopId: string; shopName: string }) {
  const desktop = useMediaQuery(DESKTOP)
  const [products, setProducts] = useState<Product[] | null>(null)
  const [loadFailed, setLoadFailed] = useState(false)
  const [codes, setCodes] = useState<Map<string, string>>(new Map())
  const [today, setToday] = useState<Today>(null)
  const [query, setQuery] = useState('')
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [done, setDone] = useState<SoldSale | null>(null)
  const [attempt, setAttempt] = useState(0)
  const sheetTitle = useId()
  const aside = useRef<HTMLElement>(null)

  // A new article or « Vendu. » starts at the top of the sale column (computer).
  useEffect(() => {
    aside.current?.scrollTo?.(0, 0)
  }, [selectedId, done])

  const loadProducts = useCallback(
    () =>
      listProducts(shopId, false, true).then(
        (rows) => {
          setProducts(rows)
          setLoadFailed(false)
        },
        () => setLoadFailed(true),
      ),
    [shopId],
  )

  useEffect(() => {
    void loadProducts()
    // Arrival codes (BAL-003…) for the search; today's figures for the header. Both optional.
    listArrivals(shopId).then(
      (rows) => setCodes(new Map(rows.map((a) => [a.id, a.code]))),
      () => {},
    )
    todaySales(shopId).then(setToday, () => {})
  }, [shopId, loadProducts, attempt])

  // Sales sent after a network cut change the stock: reload it.
  useEffect(() => {
    const reload = () => void loadProducts()
    window.addEventListener('covi-sync', reload)
    return () => window.removeEventListener('covi-sync', reload)
  }, [loadProducts])

  const visible = useMemo(
    () =>
      (products ?? []).filter((p) =>
        matchesSearch(p, p.arrival_id ? codes.get(p.arrival_id) : undefined, query),
      ),
    [products, codes, query],
  )
  const selected = products?.find((p) => p.id === selectedId) ?? null
  const codeOf = (p: Product) => (p.arrival_id ? codes.get(p.arrival_id) : undefined)

  const sold = (sale: SoldSale) => {
    setDone(sale)
    setSelectedId(null)
    setQuery('')
    setToday((t) => (t ? { count: t.count + 1, total: t.total + sale.price * sale.quantity } : t))
    void loadProducts()
  }

  const form = selected && (
    <SaleForm
      key={selected.id}
      shopId={shopId}
      product={selected}
      arrivalCode={codeOf(selected)}
      keyboard={desktop}
      onBack={desktop ? undefined : () => setSelectedId(null)}
      onSold={sold}
    />
  )
  const doneScreen = done && (
    <SaleDone sale={done} shopName={shopName} today={today} onNext={() => setDone(null)} />
  )

  // Phone: « Vendu. » takes the whole page.
  if (doneScreen && !desktop) return <section className="is-sale sale-page">{doneScreen}</section>

  return (
    <section className="is-sale sale-page">
      <header className="page-head sale-head">
        <div>
          <h1>Vendre</h1>
          {today && (
            <p className="page-head__sub">
              Aujourd’hui : {plural(today.count, 'vente')} · <Amount value={today.total} unit />
            </p>
          )}
        </div>
      </header>

      <div className="sale-layout">
        <div className="sale-layout__articles">
          <SearchField
            className="sale-search"
            label="Chercher un article"
            placeholder="Chercher : robe, jean, BAL-003…"
            value={query}
            onChange={setQuery}
            autoFocus={desktop}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && visible.length === 1) setSelectedId(visible[0].id)
            }}
          />

          {products === null && !loadFailed && <Skeleton caption="On sort le stock…" />}

          {products === null && loadFailed && (
            <Notice
              icon={CloudOffIcon}
              actions={
                <Button variant="secondary" onClick={() => setAttempt((n) => n + 1)}>
                  Réessayer
                </Button>
              }
            >
              <p>Le stock ne s’affiche pas : pas de réseau. Réessayez dans un instant.</p>
            </Notice>
          )}

          {products !== null && products.length === 0 && (
            <EmptyState
              title="Rien à vendre pour l’instant."
              actions={
                <ButtonLink variant="primary" href="#/stock">
                  Ajouter au stock
                </ButtonLink>
              }
            >
              <p>Mettez vos pièces en stock : elles apparaîtront ici, prêtes à vendre.</p>
            </EmptyState>
          )}

          {products !== null && products.length > 0 && visible.length === 0 && (
            <p className="sale-none" role="status">
              Rien ne correspond à « {query.trim()} ». Vérifiez l’orthographe.
            </p>
          )}

          {visible.length > 0 && (
            <ul className="sale-tiles" aria-label="Articles en stock">
              {visible.map((p) => (
                <li key={p.id}>
                  <SaleTile
                    product={p}
                    arrivalCode={codeOf(p)}
                    selected={p.id === selectedId}
                    onSelect={() => {
                      setDone(null)
                      setSelectedId(p.id)
                    }}
                  />
                </li>
              ))}
            </ul>
          )}
        </div>

        {desktop && (
          <aside className="sale-layout__sale" aria-label="La vente" ref={aside}>
            {doneScreen ?? form ?? (
              <div className="sale-waiting">
                <h2 className="section-title">La vente</h2>
                <p className="muted">Touchez un article pour l’ajouter.</p>
              </div>
            )}
          </aside>
        )}
      </div>

      {!desktop && (
        <Dialog
          open={Boolean(selected)}
          onClose={() => setSelectedId(null)}
          labelledBy={sheetTitle}
          sheet
          className="is-sale sale-sheet"
        >
          <h2 className="visually-hidden" id={sheetTitle}>
            {selected ? `Vendre ${selected.name}` : 'La vente'}
          </h2>
          {form}
        </Dialog>
      )}
    </section>
  )
}
