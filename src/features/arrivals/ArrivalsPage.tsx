import { useCallback, useId, useMemo, useState } from 'react'
import { CloudOffIcon, PlusIcon } from '../../components/icons'
import { Button, Dialog, EmptyState, Notice, Skeleton } from '../../components/ui'
import { useAsyncData } from '../../hooks/useAsyncData'
import { localDay } from '../../lib/dates'
import { arrivalProfitability, listArrivals, updateArrival } from '../../lib/operations'
import type { Arrival, ArrivalKind, Product } from '../../lib/types'
import '../../styles/app/arrivals.css'
import { ProductSheet } from '../stock/ProductSheet'
import { arrivalSaveError } from './arrivalForms'
import { ArrivalDetail } from './ArrivalDetail'
import { ArrivalFormSheet } from './ArrivalFormSheet'
import { groupArrivals, nextStepOf, type NextStep } from './arrivalMath'
import { ArrivalRow } from './ArrivalRow'

const heads = {
  all: {
    title: 'Arrivages',
    sub: 'Ce que vous avez acheté, et ce que ça a déjà rapporté.',
    add: 'Nouvel arrivage',
    empty: 'Pas encore d’arrivage.',
    emptyText:
      'Notez votre dernier ballon ou votre prochaine commande : vous verrez ce que chacun vous rapporte.',
  },
  supplier_order: {
    title: 'Commandes',
    sub: 'De la commande à la réception.',
    add: 'Nouvelle commande',
    empty: 'Pas encore de commande.',
    emptyText: 'Notez votre prochaine commande : vous la suivrez jusqu’à la boutique.',
  },
  balloon: {
    title: 'Ballons',
    sub: 'Chaque ballon : payé, vendu, ce qui reste.',
    add: 'Nouveau ballon',
    empty: 'Pas encore de ballon.',
    emptyText: 'Notez votre dernier ballon : vous verrez quand il est remboursé.',
  },
} as const

/** Confirmation of a step (« Marquer en route », « Confirmer la réception »). */
function StepDialog({
  arrival,
  step,
  onClose,
  onDone,
  shopId,
}: {
  arrival: Arrival | null
  step: NextStep | null
  onClose: () => void
  onDone: (arrival: Arrival, step: NextStep) => void
  shopId: string
}) {
  const titleId = useId()
  const [busy, setBusy] = useState(false)
  const [failure, setFailure] = useState('')
  const confirm = async () => {
    if (!arrival || !step) return
    setBusy(true)
    setFailure('')
    try {
      const saved = await updateArrival(shopId, arrival.id, {
        status: step.status,
        ...(step.status === 'received' ? { received_date: localDay(new Date()) } : {}),
      })
      onDone(saved, step)
    } catch (e) {
      setFailure(arrivalSaveError(e))
    } finally {
      setBusy(false)
    }
  }
  return (
    <Dialog
      open={Boolean(arrival && step)}
      onClose={() => {
        setFailure('')
        onClose()
      }}
      labelledBy={titleId}
    >
      {step && (
        <div className="dialog__body">
          <h2 className="dialog__title" id={titleId}>
            {step.question}
          </h2>
          <p className="dialog__text">{step.text}</p>
          {failure && (
            <Notice tone="danger">
              <p>{failure}</p>
            </Notice>
          )}
          <div className="dialog__actions">
            <Button variant="secondary" onClick={onClose} autoFocus>
              Pas encore
            </Button>
            <Button variant="primary" busy={busy} onClick={() => void confirm()}>
              {step.confirm}
            </Button>
          </div>
        </div>
      )}
    </Dialog>
  )
}

/**
 * Arrivages (all, or only Commandes / Ballons): each arrival with its stamp, what it cost, what is
 * sold and left, and the ruler of what came back. An arrival opens in a sheet with its pieces;
 * new orders and bales are written in their own form.
 */
export function ArrivalsPage({ shopId, kind }: { shopId: string; kind?: ArrivalKind }) {
  const load = useCallback(
    () => Promise.all([listArrivals(shopId), arrivalProfitability(shopId)]),
    [shopId],
  )
  const { data, error, retry } = useAsyncData(load)
  const [creating, setCreating] = useState(false)
  const [openId, setOpenId] = useState<string | null>(null)
  const [stepFor, setStepFor] = useState<string | null>(null)
  const [addTo, setAddTo] = useState<string | null>(null)
  const [message, setMessage] = useState<{ text: string; addTo?: string } | null>(null)
  const [added, setAdded] = useState<string | null>(null)

  const all = useMemo(() => data?.[0] ?? [], [data])
  const profits = useMemo(() => data?.[1] ?? [], [data])
  const shown = useMemo(() => (kind ? all.filter((a) => a.kind === kind) : all), [all, kind])
  const groups = useMemo(() => groupArrivals(shown, profits), [shown, profits])
  const head = heads[kind ?? 'all']
  const find = (id: string | null) => all.find((a) => a.id === id) ?? null
  const opened = find(openId)
  const stepping = find(stepFor)
  const adding = find(addTo)

  const create = () => {
    setMessage(null)
    setCreating(true)
  }

  const rows = (lines: typeof groups.waiting) => (
    <ul className="arrival-list">
      {lines.map(({ arrival, profit }) => (
        <ArrivalRow
          key={arrival.id}
          arrival={arrival}
          profit={profit}
          onOpen={() => {
            setAdded(null)
            setOpenId(arrival.id)
          }}
          onStep={() => setStepFor(arrival.id)}
        />
      ))}
    </ul>
  )

  return (
    <div className="arrivals">
      <header className="page-head arrivals-head">
        <div>
          <h1>{head.title}</h1>
          <p className="page-head__sub">{head.sub}</p>
        </div>
        {!(data && shown.length === 0) && (
          <Button variant="primary" icon={<PlusIcon />} onClick={create}>
            {head.add}
          </Button>
        )}
      </header>

      {message && (
        <Notice
          tone="success"
          actions={
            message.addTo ? (
              <Button variant="secondary" onClick={() => setAddTo(message.addTo ?? null)}>
                {find(message.addTo)?.kind === 'balloon' ? 'Ajouter ses pièces' : 'Mettre en stock'}
              </Button>
            ) : undefined
          }
        >
          <p>{message.text}</p>
        </Notice>
      )}

      {error && (
        <Notice
          icon={CloudOffIcon}
          title="Les arrivages ne s’affichent pas : pas de réseau."
          actions={
            <Button variant="secondary" onClick={retry}>
              Réessayer
            </Button>
          }
        >
          <p>Réessayez dans un instant.</p>
        </Notice>
      )}

      {!data && !error && <Skeleton caption="On ouvre le carnet des arrivages…" />}

      {data && shown.length === 0 && (
        <EmptyState
          title={head.empty}
          actions={
            <Button variant="primary" onClick={create}>
              {head.add}
            </Button>
          }
        >
          <p>{head.emptyText}</p>
        </EmptyState>
      )}

      {groups.waiting.length > 0 && (
        <section className="arrivals-part" aria-labelledby="arrivals-waiting">
          <h2 className="section-title" id="arrivals-waiting">
            À recevoir
          </h2>
          {rows(groups.waiting)}
        </section>
      )}
      {groups.received.length > 0 && (
        <section className="arrivals-part" aria-labelledby="arrivals-received">
          <h2 className="section-title" id="arrivals-received">
            {kind === 'balloon' ? 'Ouverts' : 'Reçus'}
          </h2>
          {rows(groups.received)}
        </section>
      )}

      <ArrivalFormSheet
        open={creating}
        onClose={() => setCreating(false)}
        shopId={shopId}
        kind={kind}
        codes={all.map((a) => a.code)}
        onSaved={(arrival) => {
          setCreating(false)
          const ready = arrival.status === 'received'
          setMessage({
            text:
              arrival.kind === 'balloon'
                ? ready
                  ? `${arrival.code} noté. Ajoutez ses pièces à mesure que vous déballez.`
                  : `${arrival.code} noté. Indiquez quand il arrive.`
                : `${arrival.code} noté. Indiquez « C’est commandé » une fois payé.`,
            addTo: ready ? arrival.id : undefined,
          })
          retry()
        }}
      />

      <ArrivalDetail
        arrival={opened}
        profit={profits.find((p) => p.id === openId)}
        added={added}
        onClose={() => setOpenId(null)}
        onStep={() => setStepFor(openId)}
        onAdd={() => setAddTo(openId)}
      />

      <StepDialog
        shopId={shopId}
        arrival={stepping}
        step={stepping ? nextStepOf(stepping) : null}
        onClose={() => setStepFor(null)}
        onDone={(arrival, step) => {
          setStepFor(null)
          setMessage({
            text: step.done,
            addTo: step.status === 'received' ? arrival.id : undefined,
          })
          retry()
        }}
      />

      <ProductSheet
        open={Boolean(adding)}
        onClose={() => setAddTo(null)}
        shopId={shopId}
        arrival={adding}
        onSaved={(product: Product) => {
          const text = `${product.name} est en stock${adding ? ` (${adding.code})` : ''}.`
          setAddTo(null)
          if (openId) setAdded(text)
          else setMessage({ text })
          retry()
        }}
      />
    </div>
  )
}
