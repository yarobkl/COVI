import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { PlusIcon } from '../../components/icons'
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
import { arrivalFromForm, arrivalProductFromForm } from './arrivalForms'
import { nextStatus } from './arrivalStatus'

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
    const input = arrivalFromForm(new FormData(e.currentTarget), kind ?? arrivalKind)
    setBusy(true)
    setMsg('')
    try {
      await createArrival(shopId, input)
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
    const input = arrivalProductFromForm(new FormData(e.currentTarget), addTo)
    try {
      await addProduct(shopId, input)
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
          <PlusIcon />
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
