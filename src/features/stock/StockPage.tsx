import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { Plus, Search } from 'lucide-react'
import { addProduct, listProducts, type Product } from '../../lib/covi'
import { stockCacheDate } from '../../lib/offline'
import { listArrivals, type Arrival } from '../../lib/operations'
import { StockProductForm } from './StockProductForm'
import { StockRow } from './StockRow'

/** Active stock (test products included and flagged), with the offline copy when disconnected. */
export function StockPage({ shopId }: { shopId: string }) {
  const [online, setOnline] = useState(navigator.onLine)
  const [p, setP] = useState<Product[]>([])
  const [arrivals, setArrivals] = useState<Arrival[]>([])
  const [show, setShow] = useState(false)
  const [msg, setMsg] = useState('')
  const load = useCallback(
    () =>
      listProducts(shopId, false, true)
        .then(setP)
        .catch((e) => setMsg(e.message)),
    [shopId],
  )
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
  const cacheDate = stockCacheDate(shopId)
  return (
    <>
      <div className="hello">
        <div>
          <h1>Mon stock</h1>
          <span>
            {online
              ? 'Stock réel et éléments TEST signalés.'
              : 'Stock hors connexion · dernière copie ' +
                (cacheDate ? new Date(cacheDate).toLocaleString('fr-FR') : 'locale')}
          </span>
        </div>
        <button onClick={() => setShow(!show)}>
          <Plus />
          Ajouter un produit
        </button>
      </div>
      {show && <StockProductForm arrivals={arrivals} onSubmit={save} />}
      {msg && <p className="successmsg">{msg}</p>}
      <section className="card">
        <div className="search">
          <Search />
          <input
            placeholder="Rechercher…"
            onChange={(e) => {
              const q = e.target.value.toLowerCase()
              listProducts(shopId, false, true).then((x) =>
                setP(
                  x.filter((v) =>
                    (v.name + ' ' + (v.brand ?? '') + ' ' + (v.category ?? ''))
                      .toLowerCase()
                      .includes(q),
                  ),
                ),
              )
            }}
          />
        </div>
        {p.length === 0 ? (
          <p>Aucun produit disponible. Ajoutez votre premier produit.</p>
        ) : (
          p.map((x) => <StockRow key={x.id} product={x} />)
        )}
      </section>
    </>
  )
}
