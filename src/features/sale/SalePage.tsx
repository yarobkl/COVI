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
  useWriteLock,
} from '../../components/ui'
import { ChevronRightIcon, CloudOffIcon } from '../../components/icons'
import { DESKTOP, useMediaQuery } from '../../hooks/useMediaQuery'
import { listProducts } from '../../lib/covi'
import { fcfa, plural } from '../../lib/format'
import { listArrivals, todaySales } from '../../lib/operations'
import type { Product } from '../../lib/types'
import { SaleDone } from './SaleDone'
import {
  addToCart,
  cartCount,
  cartTotal,
  lineOf,
  MAX_CART_LINES,
  refreshLines,
  soldTotal,
  type AddOutcome,
  type Cart,
  type SoldSale,
} from './cart'
import type { CartOperation } from './cartSubmit'
import { EMPTY_CART_TEXT, SaleForm } from './SaleForm'
import { SaleTile } from './SaleTile'
import { matchesSearch } from './saleMath'

/** What touching a tile did, said to screen readers (the tile and the cart show it). */
function addedText(outcome: AddOutcome, product: Product, inCart: number) {
  switch (outcome) {
    case 'added':
      return `Ajouté au panier : ${product.name}.`
    case 'more':
      return `${product.name} : ${inCart} dans le panier.`
    case 'max':
      return product.is_unique_piece
        ? `${product.name} est une pièce unique, elle est déjà dans le panier.`
        : `Tout le stock de ${product.name} est déjà dans le panier.`
    case 'full':
      return `Le panier est plein : ${MAX_CART_LINES} articles différents au plus. Validez cette vente, puis commencez-en une autre.`
  }
}

type Today = { count: number; total: number } | null

/**
 * Vendre: find the articles (instant local search), touch them to fill the cart, agree on the
 * prices and the payment, validate — one sale for the whole cart. Computer: the cart sits beside
 * the articles; phone: a bar at the bottom (« Panier · 3 articles · 54 000 ») opens it in a sheet.
 */
export function SalePage({ shopId, shopName }: { shopId: string; shopName: string }) {
  const desktop = useMediaQuery(DESKTOP)
  const lock = useWriteLock()
  const [products, setProducts] = useState<Product[] | null>(null)
  const [loadFailed, setLoadFailed] = useState(false)
  const [codes, setCodes] = useState<Map<string, string>>(new Map())
  const [today, setToday] = useState<Today>(null)
  const [query, setQuery] = useState('')
  const [cart, setCart] = useState<Cart>([])
  const [sheetOpen, setSheetOpen] = useState(false)
  // One operation id per cart, reused on every retry of the same cart; a new one after a sale.
  const [operation, setOperation] = useState<CartOperation | null>(null)
  const [said, setSaid] = useState('')
  const [done, setDone] = useState<SoldSale | null>(null)
  const [sales, setSales] = useState(0)
  const [attempt, setAttempt] = useState(0)
  const sheetTitle = useId()
  const aside = useRef<HTMLElement>(null)
  const articles = useRef<HTMLDivElement>(null)

  // « Vendu. » starts at the top of the sale column (computer).
  useEffect(() => {
    aside.current?.scrollTo?.(0, 0)
  }, [done])

  const loadProducts = useCallback(
    () =>
      listProducts(shopId, false, true).then(
        (rows) => {
          setProducts(rows)
          setLoadFailed(false)
          // The cart follows the fresh stock (names, quantities left).
          setCart((c) => refreshLines(c, rows))
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
  const codeOf = (p: Product) => (p.arrival_id ? codes.get(p.arrival_id) : undefined)
  const count = cartCount(cart)
  const total = cartTotal(cart)

  const add = (product: Product) => {
    if (lock) return
    const result = addToCart(cart, product)
    setCart(result.cart)
    setDone(null)
    setSaid(addedText(result.outcome, product, lineOf(result.cart, product.id)?.quantity ?? 0))
  }

  const sold = (sale: SoldSale) => {
    setDone(sale)
    setCart([])
    setOperation(null)
    setSheetOpen(false)
    setSales((n) => n + 1)
    setQuery('')
    setSaid('')
    setToday((t) => (t ? { count: t.count + 1, total: t.total + soldTotal(sale) } : t))
    void loadProducts()
  }

  const addMore = () => {
    if (desktop) articles.current?.querySelector('input')?.focus()
    else setSheetOpen(false)
  }

  const form = (
    <SaleForm
      // A new sale starts afresh (payment, cash received, operation id).
      key={sales}
      shopId={shopId}
      lines={cart}
      onLinesChange={setCart}
      codeOf={codeOf}
      keyboard={desktop}
      onBack={desktop ? undefined : () => setSheetOpen(false)}
      onAddMore={addMore}
      operation={operation}
      onOperation={setOperation}
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
        <div className="sale-layout__articles" ref={articles}>
          <SearchField
            className="sale-search"
            label="Chercher un article"
            placeholder="Chercher : robe, jean, BAL-003…"
            value={query}
            onChange={setQuery}
            autoFocus={desktop}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && visible.length === 1) add(visible[0])
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

          {products !== null &&
            products.length === 0 &&
            (navigator.onLine ? (
              <EmptyState
                title="Rien à vendre pour l’instant."
                actions={
                  <ButtonLink write variant="primary" href="#/stock">
                    Ajouter au stock
                  </ButtonLink>
                }
              >
                <p>Mettez vos pièces en stock : elles apparaîtront ici, prêtes à vendre.</p>
              </EmptyState>
            ) : (
              <Notice icon={CloudOffIcon}>
                <p>
                  Pas de réseau, et aucun stock n’est encore gardé sur cet appareil. Vous pourrez
                  vendre dès que le réseau revient.
                </p>
              </Notice>
            ))}

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
                    inCart={lineOf(cart, p.id)?.quantity ?? 0}
                    locked={lock ?? undefined}
                    onAdd={() => add(p)}
                  />
                </li>
              ))}
            </ul>
          )}
        </div>

        {desktop && (
          <aside className="sale-layout__sale" aria-label="La vente" ref={aside}>
            {doneScreen ??
              (cart.length > 0 ? (
                form
              ) : (
                <div className="sale-waiting">
                  <h2 className="section-title">La vente</h2>
                  <p className="muted">
                    {lock
                      ? 'Abonnement suspendu : la caisse est fermée. Le stock reste consultable.'
                      : EMPTY_CART_TEXT}
                  </p>
                </div>
              ))}
          </aside>
        )}
      </div>

      <p className="visually-hidden" role="status">
        {said}
      </p>

      {!desktop && cart.length > 0 && (
        <div className="sale-cartbar">
          <button
            type="button"
            className="sale-bar sale-cartbar__open"
            aria-haspopup="dialog"
            onClick={() => setSheetOpen(true)}
          >
            <span className="sale-cartbar__what">
              <span className="sale-bar__count">Panier · {plural(count, 'article')}</span>
              <span className="amount">
                {fcfa(total)}
                <span className="amount__unit">FCFA</span>
              </span>
            </span>
            <span className="sale-cartbar__go">
              Voir le panier
              <ChevronRightIcon />
            </span>
          </button>
        </div>
      )}

      {!desktop && (
        <Dialog
          open={sheetOpen}
          onClose={() => setSheetOpen(false)}
          labelledBy={sheetTitle}
          sheet
          className="is-sale sale-sheet"
        >
          <h2 className="visually-hidden" id={sheetTitle}>
            Le panier
          </h2>
          {form}
        </Dialog>
      )}
    </section>
  )
}
