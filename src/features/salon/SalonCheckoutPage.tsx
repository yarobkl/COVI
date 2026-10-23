import { useCallback, useState } from 'react'
import {
  Amount,
  Badge,
  Button,
  EmptyState,
  Ledger,
  LedgerRow,
  PageHead,
  Sheet,
} from '../../components/ui'
import {
  operationKey,
  salonApi,
  type SalonRole,
  type Ticket,
  type TicketBrief,
} from '../../lib/salon'
import { ActionMessage, Loaded, SalonTabs } from './SalonParts'
import { TicketEditor } from './TicketEditor'
import { salonTime } from './salonFormat'
import { useSalonAction, useSalonLoad } from './useSalonLoad'

const statusText: Record<TicketBrief['status'], string> = {
  open: 'À encaisser',
  paid: 'Payée',
  partially_refunded: 'Remboursée en partie',
  refunded: 'Remboursée',
  cancelled: 'Annulée',
}

/** Caisse du salon : notes ouvertes, ventes du jour, nouvelle note sans rendez-vous. */
export function SalonCheckoutPage({ shopId, role }: { shopId: string; role: SalonRole }) {
  const [days, setDays] = useState<'1' | '7'>('1')
  const load = useCallback(async () => {
    const [tickets, catalog, supplies, settings] = await Promise.all([
      salonApi.recentTickets(shopId, Number(days)),
      salonApi.catalog(shopId),
      salonApi.supplies(shopId),
      salonApi.settings(shopId),
    ])
    return { tickets, catalog, supplies, tz: settings.settings.time_zone }
  }, [shopId, days])
  const data = useSalonLoad(load)
  const action = useSalonAction()
  const [ticket, setTicket] = useState<Ticket | null>(null)
  const [clientName, setClientName] = useState('')

  const open = (data.data?.tickets ?? []).filter((t) => t.status === 'open')
  const done = (data.data?.tickets ?? []).filter(
    (t) => t.status !== 'open' && t.status !== 'cancelled',
  )
  const net = done.reduce((s, t) => s + t.paid_xaf - t.refunded_xaf, 0)
  const tz = data.data?.tz ?? 'Africa/Brazzaville'

  async function newTicket() {
    const t = await action.run(() =>
      salonApi.openTicket(shopId, {
        appointmentId: null,
        clientId: null,
        clientName: clientName.trim(),
        key: operationKey(),
      }),
    )
    if (t) {
      setClientName('')
      setTicket(t)
    }
  }

  async function resume(id: string) {
    const t = await action.run(() => salonApi.ticket(shopId, id))
    if (t) setTicket(t)
  }

  const row = (t: TicketBrief) => (
    <LedgerRow
      key={t.id}
      variant="link"
      label={
        <button type="button" className="ledger__open" onClick={() => void resume(t.id)}>
          {t.client_name || 'Client de passage'}
        </button>
      }
      meta={[
        salonTime(t.paid_at ?? t.opened_at, tz),
        t.appointment_id ? 'rendez-vous' : 'sans rendez-vous',
      ].join(' · ')}
      value={
        <>
          <Badge tone={t.status === 'open' ? 'waiting' : t.status === 'paid' ? 'success' : 'low'}>
            {statusText[t.status]}
          </Badge>{' '}
          <Amount value={t.status === 'open' ? t.total_xaf : t.paid_xaf - t.refunded_xaf} />
        </>
      }
    />
  )

  return (
    <div className="page-stack">
      <PageHead
        title="Caisse"
        sub="Encaissez une note depuis l’agenda, ou ouvrez une note pour un client de passage ou une vente de produit."
      />
      <Sheet>
        <div className="form-grid">
          <label>
            Nom du client <small>(facultatif)</small>
            <input
              value={clientName}
              maxLength={160}
              onChange={(e) => setClientName(e.target.value)}
            />
          </label>
          <div className="form-grid__actions">
            <Button variant="primary" busy={action.busy} onClick={() => void newTicket()}>
              Nouvelle note
            </Button>
          </div>
        </div>
      </Sheet>
      <ActionMessage message={action.message} isError={action.isError} />
      <Loaded loading={data.loading} error={data.error}>
        <Sheet>
          <h2 className="section-title">Notes à encaisser</h2>
          {open.length === 0 ? (
            <p className="entry__meta">Aucune note en attente.</p>
          ) : (
            <Ledger label="Notes à encaisser">{open.map(row)}</Ledger>
          )}
        </Sheet>
        <Sheet>
          <SalonTabs
            label="Période"
            tabs={[
              { value: '1', label: 'Aujourd’hui' },
              { value: '7', label: '7 derniers jours' },
            ]}
            value={days}
            onChange={setDays}
          />
          {done.length === 0 ? (
            <EmptyState title="Aucune note réglée">Les notes payées apparaîtront ici.</EmptyState>
          ) : (
            <Ledger label="Notes réglées">
              {done.map(row)}
              <LedgerRow
                variant="total"
                label="Encaissé net (après remboursements)"
                value={<Amount value={net} size="lg" />}
              />
            </Ledger>
          )}
        </Sheet>
      </Loaded>
      {ticket && data.data && (
        <TicketEditor
          shopId={shopId}
          role={role}
          ticket={ticket}
          catalog={data.data.catalog}
          supplies={data.data.supplies}
          onClose={() => {
            setTicket(null)
            data.reload()
          }}
          onChanged={() => undefined}
        />
      )}
    </div>
  )
}
