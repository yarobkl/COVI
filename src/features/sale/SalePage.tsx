import { useCallback, useEffect, useState } from 'react'
import { Search } from 'lucide-react'
import { listProducts } from '../../lib/covi'
import type { Product } from '../../lib/types'
import { pendingCount, resilientSale, syncPendingSales } from '../../lib/offline'
import { Checkout } from './Checkout'
import { SaleProductRow } from './SaleProductRow'

/** Records a sale, online or queued offline, and shows the synchronisation state. */
export function SalePage({ shopId }: { shopId: string }) {
  const [online, setOnline] = useState(navigator.onLine)
  const [pending, setPending] = useState(pendingCount())
  const [p, setP] = useState<Product[]>([])
  const [query, setQuery] = useState('')
  const [selected, setSelected] = useState<Product | null>(null)
  const [price, setPrice] = useState('')
  const [qty, setQty] = useState(1)
  const [pay, setPay] = useState('Espèces')
  const [msg, setMsg] = useState('')
  const [busy, setBusy] = useState(false)
  const load = useCallback(() => listProducts(shopId, false, true).then(setP), [shopId])
  useEffect(() => {
    void load()
    const sync = () => {
      setOnline(navigator.onLine)
      setPending(pendingCount())
      if (navigator.onLine && pendingCount() > 0)
        void syncPendingSales().then(() => {
          setPending(pendingCount())
          void load()
        })
    }
    window.addEventListener('online', sync)
    window.addEventListener('offline', sync)
    window.addEventListener('covi-sync', sync)
    sync()
    return () => {
      window.removeEventListener('online', sync)
      window.removeEventListener('offline', sync)
      window.removeEventListener('covi-sync', sync)
    }
  }, [load])
  async function sell() {
    if (!selected) return
    setBusy(true)
    setMsg('')
    try {
      const result = await resilientSale({
        shopId,
        productId: selected.id,
        quantity: qty,
        soldUnitPrice: Number(price),
        paymentLabel: pay,
      })
      setPending(pendingCount())
      setMsg(
        result.offline
          ? '✓ Vente sauvegardée hors connexion. Synchronisation automatique au retour du réseau.'
          : '✓ Vente enregistrée et stock mis à jour.',
      )
      setSelected(null)
      setPrice('')
      setQty(1)
      await load()
    } catch (e) {
      setMsg((e as Error).message)
    } finally {
      setBusy(false)
    }
  }
  const visible = p.filter((x) =>
    (x.name + ' ' + (x.brand || '') + ' ' + (x.category || ''))
      .toLowerCase()
      .includes(query.toLowerCase()),
  )
  return (
    <>
      <div className="hello">
        <div>
          <h1>Nouvelle vente</h1>
          <span>Enregistrez une vente réelle en quelques secondes.</span>
        </div>
        <div className={online ? 'pill green' : 'pill orange'}>
          {online ? 'En ligne' : 'Hors connexion'}
          {pending > 0 ? ' · ' + pending + ' à synchroniser' : ''}
        </div>
      </div>
      <div className="sale">
        <section className="card">
          <div className="search">
            <Search />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Rechercher un produit à vendre…"
            />
          </div>
          {visible.map((x) => (
            <SaleProductRow
              key={x.id}
              product={x}
              onSelect={() => {
                setSelected(x)
                setPrice(String(x.initial_sale_price))
                setQty(1)
              }}
            />
          ))}
        </section>
        <Checkout
          selected={selected}
          price={price}
          onPriceChange={setPrice}
          qty={qty}
          onQtyChange={setQty}
          pay={pay}
          onPayChange={setPay}
          busy={busy}
          msg={msg}
          onSell={sell}
        />
      </div>
    </>
  )
}
