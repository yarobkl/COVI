import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { PlusIcon } from '../../components/icons'
import {
  Button,
  Field,
  Ledger,
  PageHead,
  PageMessage,
  SearchField,
  Segmented,
} from '../../components/ui'
import { addProduct, listProducts } from '../../lib/covi'
import { stockCacheDate } from '../../lib/offline'
import { listArrivals } from '../../lib/operations'
import { supabase } from '../../lib/supabase'
import type { Arrival, Product } from '../../lib/types'
import { ProductEditor } from './ProductEditor'
import { StockProductForm } from './StockProductForm'
import { StockRow } from './StockRow'

type StockView = 'active' | 'sold' | 'archived'

const emptyText: Record<StockView, string> = {
  active: 'Aucun produit en vente. Ajoutez votre premier produit.',
  sold: 'Aucun produit épuisé.',
  archived: 'Aucun produit retiré de la vente.',
}

/** Active stock (test products included and flagged), with the offline copy when disconnected. */
export function StockPage({ shopId }: { shopId: string }) {
  const [online, setOnline] = useState(navigator.onLine)
  const [p, setP] = useState<Product[]>([])
  const [arrivals, setArrivals] = useState<Arrival[]>([])
  const [show, setShow] = useState(false)
  const [msg, setMsg] = useState('')
  const [query, setQuery] = useState('')
  const [selectedProductId, setSelectedProductId] = useState('')
  const [view, setView] = useState<StockView>('active')
  // Épuisés et retirés de la vente : chargés seulement quand on ouvre leur onglet.
  const [others, setOthers] = useState<Product[] | null>(null)
  const [editingId, setEditingId] = useState<string | null>(null)
  const load = useCallback(
    () =>
      listProducts(shopId, false, true)
        .then(setP)
        .catch((e) => setMsg(e.message)),
    [shopId],
  )
  const loadOthers = useCallback(
    () =>
      listProducts(shopId, true, true)
        .then((rows) => setOthers(rows.filter((x) => x.status !== 'active')))
        .catch((e) => setMsg(e.message)),
    [shopId],
  )
  useEffect(() => {
    if (view !== 'active' && others === null) void loadOthers()
  }, [view, others, loadOthers])
  useEffect(() => {
    void load()
    if (navigator.onLine) void listArrivals(shopId).then(setArrivals)
    const status = () => {
      setOnline(navigator.onLine)
      if (navigator.onLine) void load()
    }
    window.addEventListener('online', status)
    window.addEventListener('offline', status)
    return () => {
      window.removeEventListener('online', status)
      window.removeEventListener('offline', status)
    }
  }, [shopId, load])
  // Mise a jour entre plusieurs appareils : le serveur reste la source de verite.
  // La RLS de products restreint les evenements aux boutiques autorisees.
  useEffect(() => {
    if (!online) return
    const channel = supabase
      .channel('covi-stock-' + shopId)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'products', filter: 'shop_id=eq.' + shopId },
        () => {
          void load()
          void loadOthers()
        },
      )
      .subscribe()
    return () => {
      void supabase.removeChannel(channel)
    }
  }, [shopId, online, load, loadOthers])

  async function save(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const f = new FormData(e.currentTarget),
      unique = f.get('unique') === 'on'
    try {
      await addProduct(shopId, {
        name: String(f.get('name')),
        category: String(f.get('category') || ''),
        brand: String(f.get('brand') || ''),
        size: String(f.get('size') || ''),
        initial_sale_price: Number(f.get('price')),
        quantity_on_hand: unique ? 1 : Number(f.get('quantity') || 1),
        is_unique_piece: unique,
        arrival_id: String(f.get('arrival') || '') || null,
        is_test: arrivals.find((a) => a.id === String(f.get('arrival') || ''))?.is_test ?? false,
        image: (f.get('image') as File)?.size ? (f.get('image') as File) : null,
      })
      setShow(false)
      setMsg('Produit ajouté au stock.')
      load()
    } catch (e) {
      setMsg((e as Error).message)
    }
  }
  const q = query.toLowerCase()
  const shown = view === 'active' ? p : (others ?? []).filter((x) => x.status === view)
  const editing = [...p, ...(others ?? [])].find((x) => x.id === editingId) ?? null
  const visible = shown.filter(
    (v) =>
      (!selectedProductId || v.id === selectedProductId) &&
      (v.name + ' ' + (v.brand ?? '') + ' ' + (v.category ?? '')).toLowerCase().includes(q),
  )
  const cacheDate = stockCacheDate(shopId)
  return (
    <div className="page-stack">
      <PageHead
        title="Mon stock"
        sub={
          online
            ? 'Stock réel ; les articles de test sont signalés.'
            : 'Hors connexion · dernière copie du ' +
              (cacheDate ? new Date(cacheDate).toLocaleString('fr-FR') : 'téléphone')
        }
        action={
          <Button variant="secondary" icon={<PlusIcon />} onClick={() => setShow(!show)}>
            {show ? 'Fermer' : 'Ajouter un produit'}
          </Button>
        }
      />
      {show && <StockProductForm arrivals={arrivals} products={p} onSubmit={save} />}
      {msg && <PageMessage>{msg}</PageMessage>}
      <section className="stock-list" aria-label="Articles du stock">
        <Segmented
          legend="Afficher"
          value={view}
          onChange={(next) => {
            setView(next)
            setSelectedProductId('')
          }}
          options={[
            { value: 'active' as const, label: 'En vente' },
            { value: 'sold' as const, label: 'Épuisés' },
            { value: 'archived' as const, label: 'Retirés' },
          ]}
        />
        <Field label="Choisir un article du stock">
          {(control) => (
            <select
              {...control}
              className="select"
              value={selectedProductId}
              onChange={(event) => setSelectedProductId(event.target.value)}
            >
              <option value="">Tous les articles</option>
              {shown.map((product) => (
                <option value={product.id} key={product.id}>
                  {product.name} · {product.category || 'Sans catégorie'}
                </option>
              ))}
            </select>
          )}
        </Field>
        <SearchField
          label="Rechercher un article"
          placeholder="Rechercher…"
          value={query}
          onChange={setQuery}
        />
        {visible.length === 0 ? (
          <p className="stock-list__empty">{emptyText[view]}</p>
        ) : (
          <Ledger label="Articles du stock">
            {visible.map((x) => (
              <StockRow key={x.id} product={x} onOpen={() => setEditingId(x.id)} />
            ))}
          </Ledger>
        )}
      </section>
      {editing && (
        <ProductEditor
          key={editing.id}
          product={editing}
          onClose={() => setEditingId(null)}
          onChanged={(message) => {
            setMsg(message)
            void load()
            void loadOthers()
          }}
        />
      )}
    </div>
  )
}
