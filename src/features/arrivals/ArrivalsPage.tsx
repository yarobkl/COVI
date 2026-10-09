import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { Plus } from 'lucide-react'
import { addProduct } from '../../lib/covi'
import { localDay } from '../../lib/dates'
import {
  arrivalProfitability,
  createArrival,
  listArrivals,
  updateArrival,
  type ArrivalProfit,
} from '../../lib/operations'
import type { Arrival } from '../../lib/types'
import { ArrivalCard } from './ArrivalCard'
import { ArrivalForm } from './ArrivalForm'
import { ArrivalProductForm } from './ArrivalProductForm'
import { arrivalCode, nextStatus } from './arrivalStatus'

const titles = {
  supplier_order: 'Mes commandes',
  balloon: 'Mes ballons',
} as const

const errorMessage = (e: unknown) => (e as Error).message

/** Arrivals (all, supplier orders only or balloons only) with their lifecycle and products. */
export function ArrivalsPage({ shopId, kind }: { shopId: string; kind?: Arrival['kind'] }) {
  const [rows, setRows] = useState<Arrival[]>([])
  const [profit, setProfit] = useState<ArrivalProfit[]>([])
  const [show, setShow] = useState(false)
  const [arrivalKind, setArrivalKind] = useState<Arrival['kind']>(kind ?? 'supplier_order')
  const [addTo, setAddTo] = useState<Arrival | null>(null)
  const [expanded, setExpanded] = useState<string | null>(null)
  const [msg, setMsg] = useState('')
  const [busy, setBusy] = useState(false)
  const load = useCallback(() => {
    void listArrivals(shopId)
      .then((x) => setRows(kind ? x.filter((a) => a.kind === kind) : x))
      .catch((e) => setMsg(errorMessage(e)))
    void arrivalProfitability(shopId)
      .then((x) => setProfit(kind ? x.filter((a) => a.kind === kind) : x))
      .catch((e) => setMsg(errorMessage(e)))
  }, [shopId, kind])
  useEffect(() => {
    load()
  }, [load])
  async function save(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const f = new FormData(e.currentTarget),
      k = kind ?? arrivalKind,
      goods = Number(f.get('goods') || 0),
      transport = Number(f.get('transport') || 0),
      customs = Number(f.get('customs') || 0),
      global = k === 'balloon' ? Number(f.get('global') || 0) : goods + transport + customs
    setBusy(true)
    setMsg('')
    try {
      await createArrival(shopId, {
        code: arrivalCode(k === 'balloon' ? 'BAL' : 'CMD'),
        kind: k,
        origin_country: String(f.get('country') || ''),
        supplier_name: k === 'supplier_order' ? String(f.get('supplier') || '') : null,
        merchandise_cost: goods,
        transport_cost: transport,
        customs_cost: customs,
        global_cost: global,
        order_date: k === 'supplier_order' ? String(f.get('orderDate') || '') || null : null,
        received_date: null,
        status: 'draft',
      })
      setShow(false)
      setMsg('Arrivage enregistré en brouillon.')
      load()
    } catch (e) {
      setMsg(errorMessage(e))
    } finally {
      setBusy(false)
    }
  }
  async function advance(a: Arrival) {
    const status = nextStatus[a.status]
    if (!status) return
    setBusy(true)
    setMsg('')
    try {
      await updateArrival(shopId, a.id, {
        status,
        ...(status === 'received' ? { received_date: localDay(new Date()) } : {}),
      })
      setMsg(
        status === 'received'
          ? 'Arrivage reçu. Vous pouvez enregistrer les produits.'
          : 'Statut mis à jour.',
      )
      load()
    } catch (e) {
      setMsg(errorMessage(e))
    } finally {
      setBusy(false)
    }
  }
  async function saveProduct(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    if (!addTo) return
    const f = new FormData(e.currentTarget),
      unique = addTo.kind === 'balloon',
      qty = unique ? 1 : Math.max(1, Number(f.get('quantity') || 1))
    try {
      await addProduct(shopId, {
        arrival_id: addTo.id,
        is_test: addTo.is_test ?? false,
        name: String(f.get('name') || ''),
        category: String(f.get('category') || ''),
        brand: String(f.get('brand') || ''),
        size: String(f.get('size') || ''),
        initial_sale_price: Number(f.get('price') || 0),
        quantity_on_hand: qty,
        is_unique_piece: unique,
        image: (f.get('image') as File)?.size ? (f.get('image') as File) : null,
      })
      setMsg('Produit ajouté à ' + addTo.code + '.')
      setAddTo(null)
      load()
    } catch (e) {
      setMsg(errorMessage(e))
    }
  }
  return (
    <div>
      <div className="hello">
        <div>
          <h1>{kind ? titles[kind] : 'Mes arrivages'}</h1>
          <span>Suivi des arrivages réels et de la simulation marquée TEST.</span>
        </div>
        <button onClick={() => setShow(!show)}>
          <Plus />
          Nouvel arrivage
        </button>
      </div>
      {show && (
        <ArrivalForm
          kind={kind}
          arrivalKind={arrivalKind}
          onArrivalKindChange={setArrivalKind}
          busy={busy}
          onSubmit={save}
        />
      )}
      {msg && <p className="successmsg">{msg}</p>}
      <section className="card">
        {rows.length === 0 ? (
          <p>
            Aucun arrivage enregistré. Créez une commande fournisseur ou un ballon pour commencer.
          </p>
        ) : (
          rows.map((a) => (
            <ArrivalCard
              key={a.id}
              arrival={a}
              profit={profit.find((x) => x.id === a.id)}
              busy={busy}
              expanded={expanded === a.id}
              onAdvance={() => void advance(a)}
              onAddProduct={() => setAddTo(a)}
              onToggleDetail={() => setExpanded(expanded === a.id ? null : a.id)}
            />
          ))
        )}
      </section>
      {addTo && (
        <ArrivalProductForm
          arrival={addTo}
          onSubmit={saveProduct}
          onCancel={() => setAddTo(null)}
        />
      )}
    </div>
  )
}
