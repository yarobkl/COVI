import { useCallback, useMemo, useState } from 'react'
import { Badge, Button, Dialog, EmptyState, Notice, PageHead, Sheet } from '../../components/ui'
import { fcfa } from '../../lib/format'
import {
  operationKey,
  salonApi,
  type Appointment,
  type AppointmentStatus,
  type SalonRole,
  type Supply,
  type Ticket,
} from '../../lib/salon'
import { AppointmentForm } from './AppointmentForm'
import { ActionMessage, Loaded, SalonTabs } from './SalonParts'
import { TicketEditor } from './TicketEditor'
import {
  addDays,
  mondayOf,
  nextStatuses,
  salonDateLabel,
  salonDay,
  salonInstant,
  salonTime,
  statusLabels,
  statusTone,
  whatsappHref,
} from './salonFormat'
import { useSalonAction, useSalonLoad } from './useSalonLoad'

type View = 'day' | 'week' | 'list'
const views = [
  { value: 'day', label: 'Journée' },
  { value: 'week', label: 'Semaine' },
  { value: 'list', label: 'À venir' },
] as const

const statusAction: Partial<Record<AppointmentStatus, string>> = {
  confirmed: 'Confirmer',
  arrived: 'Client arrivé',
  in_progress: 'Commencer',
  completed: 'Terminer',
  no_show: 'Client absent',
  cancelled: 'Annuler',
}

/** Agenda du salon : journée par collaborateur, semaine, liste. */
export function SalonAgendaPage({ shopId, role }: { shopId: string; role: SalonRole }) {
  const loadBase = useCallback(async () => {
    const [settings, catalog, supplies] = await Promise.all([
      salonApi.settings(shopId),
      salonApi.catalog(shopId),
      role === 'stylist' ? Promise.resolve([] as Supply[]) : salonApi.supplies(shopId),
    ])
    return { settings, catalog, supplies }
  }, [shopId, role])
  const base = useSalonLoad(loadBase)
  const tz = base.data?.settings.settings.time_zone ?? 'Africa/Brazzaville'
  const [view, setView] = useState<View>('day')
  const [day, setDay] = useState(() => salonDay(new Date(), 'Africa/Brazzaville'))
  const [staffFilter, setStaffFilter] = useState('')

  const range = useMemo(() => {
    if (view === 'day') return { from: day, to: addDays(day, 1) }
    if (view === 'week') {
      const monday = mondayOf(day)
      return { from: monday, to: addDays(monday, 7) }
    }
    return { from: day, to: addDays(day, 14) }
  }, [view, day])
  const loadAgenda = useCallback(
    () =>
      salonApi.agenda(
        shopId,
        salonInstant(range.from, '00:00', tz),
        salonInstant(range.to, '00:00', tz),
      ),
    [shopId, range, tz],
  )
  const agenda = useSalonLoad(loadAgenda)

  const [form, setForm] = useState<{ editing: Appointment | null; walkIn: boolean } | null>(null)
  const [opened, setOpened] = useState<Appointment | null>(null)
  const [ticket, setTicket] = useState<Ticket | null>(null)
  const [scheduling, setScheduling] = useState<{ requestId: string; employeeId: string } | null>(
    null,
  )
  const action = useSalonAction()
  const canWrite = role !== 'stylist'
  const canCheckout = role !== 'stylist'

  const appointments = (agenda.data?.appointments ?? []).filter(
    (a) => !staffFilter || a.employee_id === staffFilter,
  )
  const staff = (base.data?.catalog.staff ?? []).filter(
    (s) => s.active && (!staffFilter || s.employee_id === staffFilter),
  )
  const today = salonDay(new Date(), tz)

  const [reason, setReason] = useState('')
  // Annuler ou noter une absence se fait en deux temps : le motif n'apparaît qu'après le clic.
  const [confirming, setConfirming] = useState<AppointmentStatus | null>(null)
  async function changeStatus(a: Appointment, status: AppointmentStatus) {
    const done = await action.run(
      () => salonApi.setStatus(shopId, a.id, status, reason),
      `${statusLabels[status]}.`,
    )
    if (done) {
      setOpened(null)
      setReason('')
      setConfirming(null)
      agenda.reload()
    }
  }

  async function checkout(a: Appointment) {
    const t = await action.run(() =>
      salonApi.openTicket(shopId, {
        appointmentId: a.id,
        clientId: null,
        clientName: '',
        key: operationKey(),
      }),
    )
    if (t) {
      setOpened(null)
      setTicket(t)
    }
  }

  const byDay = (d: string) => appointments.filter((a) => salonDay(new Date(a.starts_at), tz) === d)

  const card = (a: Appointment) => (
    <li key={a.id} className="salon-appt" data-status={a.status}>
      <button
        type="button"
        className="salon-appt__open"
        onClick={() => {
          setOpened(a)
          setConfirming(null)
          setReason('')
        }}
      >
        <span className="salon-appt__time">
          {salonTime(a.starts_at, tz)} – {salonTime(a.ends_at, tz)}
        </span>
        <span className="salon-appt__client">{a.client_name}</span>
        <span className="salon-appt__meta">
          {a.services.map((s) => s.name).join(', ')}
          {!staffFilter && view !== 'day' ? ` · ${a.employee_name}` : ''}
        </span>
        <Badge tone={statusTone[a.status]}>{statusLabels[a.status]}</Badge>
      </button>
    </li>
  )

  return (
    <div className="page-stack">
      <PageHead
        title={role === 'stylist' ? 'Mes rendez-vous' : 'Agenda'}
        sub="Chaque collaborateur a son planning : deux clients ne peuvent pas lui être donnés au même moment."
        action={
          canWrite && base.data ? (
            <div className="row-actions">
              <Button variant="primary" onClick={() => setForm({ editing: null, walkIn: false })}>
                Nouveau rendez-vous
              </Button>
              <Button onClick={() => setForm({ editing: null, walkIn: true })}>
                Client sans rendez-vous
              </Button>
            </div>
          ) : undefined
        }
      />
      <Loaded loading={base.loading} error={base.error}>
        <SalonTabs label="Vue de l’agenda" tabs={views} value={view} onChange={setView} />
        <div className="salon-toolbar">
          <div className="row-actions">
            <Button
              variant="ghost"
              onClick={() => setDay(addDays(day, view === 'week' ? -7 : -1))}
              aria-label="Période précédente"
            >
              ‹
            </Button>
            <Button variant="ghost" onClick={() => setDay(today)}>
              Aujourd’hui
            </Button>
            <Button
              variant="ghost"
              onClick={() => setDay(addDays(day, view === 'week' ? 7 : 1))}
              aria-label="Période suivante"
            >
              ›
            </Button>
          </div>
          <p className="salon-toolbar__date">
            {view === 'week'
              ? `Semaine du ${salonDateLabel(salonInstant(range.from, '12:00', tz), tz)}`
              : salonDateLabel(salonInstant(day, '12:00', tz), tz)}
          </p>
          {role !== 'stylist' && (
            <label className="salon-toolbar__filter">
              Collaborateur
              <select value={staffFilter} onChange={(e) => setStaffFilter(e.target.value)}>
                <option value="">Tous</option>
                {(base.data?.catalog.staff ?? [])
                  .filter((s) => s.active)
                  .map((s) => (
                    <option key={s.employee_id} value={s.employee_id}>
                      {s.full_name}
                    </option>
                  ))}
              </select>
            </label>
          )}
        </div>
        <ActionMessage message={action.message} isError={action.isError} />

        <Loaded loading={agenda.loading && !agenda.data} error={agenda.error}>
          {view === 'day' &&
            (staff.length === 0 ? (
              <EmptyState
                title="Aucun collaborateur"
                actions={
                  role === 'owner' || role === 'manager' ? (
                    <Button onClick={() => (window.location.hash = '#/salon-equipe')}>
                      Ajouter un collaborateur
                    </Button>
                  ) : undefined
                }
              >
                L’agenda se remplit par collaborateur. Ajoutez votre équipe (vous compris si vous
                coiffez).
              </EmptyState>
            ) : (
              <div className="salon-columns">
                {staff.map((s) => {
                  const own = byDay(day).filter((a) => a.employee_id === s.employee_id)
                  return (
                    <Sheet
                      key={s.employee_id}
                      className="salon-column"
                      aria-label={`Planning de ${s.full_name}`}
                    >
                      <h2
                        className="section-title salon-column__name"
                        style={{ borderColor: s.agenda_color }}
                      >
                        {s.full_name}
                      </h2>
                      {own.length === 0 ? (
                        <p className="entry__meta">Aucun rendez-vous — journée libre.</p>
                      ) : (
                        <ul className="salon-appts">{own.map(card)}</ul>
                      )}
                    </Sheet>
                  )
                })}
              </div>
            ))}

          {view === 'week' && (
            <div className="salon-week">
              {Array.from({ length: 7 }, (_, i) => addDays(range.from, i)).map((d) => {
                const list = byDay(d)
                return (
                  <Sheet
                    key={d}
                    className={d === today ? 'salon-week__day is-today' : 'salon-week__day'}
                  >
                    <h2 className="section-title">
                      <button
                        type="button"
                        className="salon-link"
                        onClick={() => {
                          setDay(d)
                          setView('day')
                        }}
                      >
                        {salonDateLabel(salonInstant(d, '12:00', tz), tz)}
                      </button>
                    </h2>
                    {list.length === 0 ? (
                      <p className="entry__meta">Libre</p>
                    ) : (
                      <ul className="salon-appts">{list.map(card)}</ul>
                    )}
                  </Sheet>
                )
              })}
            </div>
          )}

          {view === 'list' &&
            (appointments.filter((a) =>
              ['pending', 'confirmed', 'arrived', 'in_progress'].includes(a.status),
            ).length === 0 ? (
              <EmptyState title="Aucun rendez-vous à venir">
                Les 14 prochains jours sont libres.
              </EmptyState>
            ) : (
              <Sheet>
                {Array.from({ length: 14 }, (_, i) => addDays(day, i)).map((d) => {
                  const list = byDay(d).filter((a) =>
                    ['pending', 'confirmed', 'arrived', 'in_progress'].includes(a.status),
                  )
                  if (list.length === 0) return null
                  return (
                    <section key={d} className="entry">
                      <h2 className="entry__title">
                        {salonDateLabel(salonInstant(d, '12:00', tz), tz)}
                      </h2>
                      <ul className="salon-appts">{list.map(card)}</ul>
                    </section>
                  )
                })}
              </Sheet>
            ))}

          {canWrite && (agenda.data?.pending_requests.length ?? 0) > 0 && (
            <Sheet>
              <h2 className="section-title">Demandes à planifier</h2>
              <ul className="salon-appts">
                {agenda.data!.pending_requests.map((r) => (
                  <li key={r.id} className="salon-appt">
                    <span className="salon-appt__time">
                      {salonDateLabel(r.requested_at, tz)} · {salonTime(r.requested_at, tz)}
                    </span>
                    <span className="salon-appt__client">{r.client_name}</span>
                    <span className="salon-appt__meta">{r.phone}</span>
                    <span className="row-actions">
                      <Button
                        variant="ghost"
                        onClick={() => setScheduling({ requestId: r.id, employeeId: '' })}
                        disabled={!r.service_id}
                      >
                        {r.service_id
                          ? 'Planifier'
                          : 'Sans prestation : à saisir comme rendez-vous'}
                      </Button>
                      <Button
                        variant="ghost"
                        busy={action.busy}
                        onClick={() =>
                          void action
                            .run(() => salonApi.declineRequest(shopId, r.id), 'Demande refusée.')
                            .then((ok) => ok && agenda.reload())
                        }
                      >
                        Refuser
                      </Button>
                    </span>
                  </li>
                ))}
              </ul>
            </Sheet>
          )}
        </Loaded>
      </Loaded>

      {opened && base.data && (
        <Dialog open onClose={() => setOpened(null)} labelledBy="salon-opened-title" sheet>
          <div className="dialog__body">
            <h2 className="dialog__title" id="salon-opened-title">
              {opened.client_name}
            </h2>
            <p className="dialog__text">
              {salonDateLabel(opened.starts_at, tz)}, {salonTime(opened.starts_at, tz)} –{' '}
              {salonTime(opened.ends_at, tz)} avec {opened.employee_name}
            </p>
            <p className="dialog__text">
              {opened.services.map((s) => s.name).join(', ')} · environ{' '}
              {fcfa(opened.estimated_price_xaf)} FCFA
            </p>
            {opened.notes && <p className="dialog__text">Note : {opened.notes}</p>}
            <p>
              <Badge tone={statusTone[opened.status]}>{statusLabels[opened.status]}</Badge>
            </p>
            {opened.client_phone && (
              <p className="row-actions">
                <a className="btn btn--ghost" href={`tel:${opened.client_phone}`}>
                  Appeler {opened.client_phone}
                </a>
                <a
                  className="btn btn--ghost"
                  href={whatsappHref(
                    opened.client_phone,
                    `Bonjour ${opened.client_name}, nous vous attendons le ${salonDateLabel(opened.starts_at, tz)} à ${salonTime(opened.starts_at, tz)}.`,
                  )}
                  target="_blank"
                  rel="noreferrer"
                >
                  Préparer un message WhatsApp
                </a>
              </p>
            )}
            <p className="entry__meta">
              Le bouton WhatsApp ouvre l’application avec un message prêt : rien n’est envoyé tant
              que vous ne l’envoyez pas vous-même.
            </p>
            {confirming ? (
              <>
                <label className="field">
                  <span className="field__label">
                    Motif {confirming === 'no_show' ? 'de l’absence' : 'de l’annulation'}{' '}
                    (facultatif)
                  </span>
                  <input
                    className="input"
                    value={reason}
                    maxLength={200}
                    onChange={(e) => setReason(e.target.value)}
                  />
                </label>
                <div className="row-actions">
                  <Button
                    variant="danger"
                    busy={action.busy}
                    onClick={() => void changeStatus(opened, confirming)}
                  >
                    {confirming === 'no_show' ? 'Confirmer l’absence' : 'Confirmer l’annulation'}
                  </Button>
                  <Button
                    onClick={() => {
                      setConfirming(null)
                      setReason('')
                    }}
                  >
                    Ne rien changer
                  </Button>
                </div>
              </>
            ) : (
              <div className="row-actions">
                {nextStatuses(opened.status, role).map((s) => (
                  <Button
                    key={s}
                    variant={s === 'cancelled' || s === 'no_show' ? 'danger' : 'secondary'}
                    busy={action.busy}
                    onClick={() =>
                      s === 'cancelled' || s === 'no_show'
                        ? setConfirming(s)
                        : void changeStatus(opened, s)
                    }
                  >
                    {statusAction[s]}
                  </Button>
                ))}
                {canWrite &&
                  ['pending', 'confirmed', 'arrived'].includes(opened.status) &&
                  !opened.ticket && (
                    <Button
                      onClick={() => {
                        setForm({ editing: opened, walkIn: false })
                        setOpened(null)
                      }}
                    >
                      Modifier / reporter
                    </Button>
                  )}
                {canCheckout &&
                  ['confirmed', 'arrived', 'in_progress', 'completed'].includes(opened.status) &&
                  (!opened.ticket || opened.ticket.status === 'open') && (
                    <Button
                      variant="primary"
                      busy={action.busy}
                      onClick={() => void checkout(opened)}
                    >
                      {opened.ticket ? 'Reprendre la note' : 'Encaisser'}
                    </Button>
                  )}
              </div>
            )}
            <ActionMessage message={action.message} isError={action.isError} />
            <div className="dialog__actions">
              <Button onClick={() => setOpened(null)}>Fermer</Button>
            </div>
          </div>
        </Dialog>
      )}

      {form && base.data && (
        <AppointmentForm
          shopId={shopId}
          role={role}
          tz={tz}
          catalog={base.data.catalog}
          day={day}
          editing={form.editing}
          walkIn={form.walkIn}
          onClose={() => setForm(null)}
          onSaved={() => {
            setForm(null)
            action.setIsError(false)
            action.setMessage(form.walkIn ? 'Client installé.' : 'Rendez-vous enregistré.')
            agenda.reload()
          }}
        />
      )}

      {scheduling && base.data && (
        <Dialog open onClose={() => setScheduling(null)} labelledBy="salon-schedule-title">
          <div className="dialog__body">
            <h2 className="dialog__title" id="salon-schedule-title">
              Planifier la demande
            </h2>
            <label className="field">
              <span className="field__label">Avec quel collaborateur ?</span>
              <select
                className="input"
                value={scheduling.employeeId}
                onChange={(e) => setScheduling({ ...scheduling, employeeId: e.target.value })}
              >
                <option value="">Choisir…</option>
                {base.data.catalog.staff
                  .filter((s) => s.active)
                  .map((s) => (
                    <option key={s.employee_id} value={s.employee_id}>
                      {s.full_name}
                    </option>
                  ))}
              </select>
            </label>
            <ActionMessage message={action.message} isError={action.isError} />
            <div className="dialog__actions">
              <Button variant="ghost" onClick={() => setScheduling(null)}>
                Fermer
              </Button>
              <Button
                variant="primary"
                disabled={!scheduling.employeeId}
                busy={action.busy}
                onClick={() =>
                  void action
                    .run(
                      () =>
                        salonApi.scheduleRequest(
                          shopId,
                          scheduling.requestId,
                          scheduling.employeeId,
                        ),
                      'Demande planifiée.',
                    )
                    .then((id) => {
                      if (id) {
                        setScheduling(null)
                        agenda.reload()
                      }
                    })
                }
              >
                Planifier
              </Button>
            </div>
          </div>
        </Dialog>
      )}

      {ticket && base.data && (
        <TicketEditor
          shopId={shopId}
          role={role}
          ticket={ticket}
          catalog={base.data.catalog}
          supplies={base.data.supplies}
          onClose={() => {
            setTicket(null)
            agenda.reload()
          }}
          onChanged={() => undefined}
        />
      )}
      {role === 'stylist' && (
        <Notice live={false}>
          Vous voyez uniquement vos rendez-vous. L’encaissement se fait à la caisse.
        </Notice>
      )}
    </div>
  )
}
