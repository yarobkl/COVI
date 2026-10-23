import { useEffect, useMemo, useState, type FormEvent } from 'react'
import { Button, Dialog } from '../../components/ui'
import { fcfa } from '../../lib/format'
import {
  salonApi,
  type Appointment,
  type ClientBrief,
  type SalonCatalog,
  type SalonRole,
} from '../../lib/salon'
import { ActionMessage } from './SalonParts'
import { minutesLabel, salonDay, salonInstant, salonTime } from './salonFormat'
import { useSalonAction } from './useSalonLoad'

/**
 * Prise ou modification d'un rendez-vous, ou visite sans rendez-vous (`walkIn`). Les contrôles
 * (horaires, absences, habilitations, chevauchements) sont faits par le serveur ; ce formulaire
 * aide seulement à choisir un collaborateur habilité.
 */
export function AppointmentForm({
  shopId,
  role,
  tz,
  catalog,
  day,
  editing,
  walkIn = false,
  onClose,
  onSaved,
}: {
  shopId: string
  role: SalonRole
  tz: string
  catalog: SalonCatalog
  day: string
  editing: Appointment | null
  walkIn?: boolean
  onClose: () => void
  onSaved: (id: string) => void
}) {
  const action = useSalonAction()
  const services = catalog.services.filter((s) => s.active)
  const staff = catalog.staff.filter((s) => s.active)
  const [serviceIds, setServiceIds] = useState<string[]>(
    editing ? editing.services.map((s) => s.service_id) : [],
  )
  const [employeeId, setEmployeeId] = useState(editing?.employee_id ?? '')
  const [date, setDate] = useState(editing ? salonDay(new Date(editing.starts_at), tz) : day)
  const [time, setTime] = useState(editing ? salonTime(editing.starts_at, tz) : '10:00')
  const [clientName, setClientName] = useState(editing?.client_name ?? '')
  const [clientPhone, setClientPhone] = useState(editing?.client_phone ?? '')
  const [clientId, setClientId] = useState<string | null>(editing?.client_id ?? null)
  const [notes, setNotes] = useState(editing?.notes ?? '')
  const [duration, setDuration] = useState('')
  const [matches, setMatches] = useState<ClientBrief[]>([])
  const canSearchClients = role !== 'stylist'

  const qualified = useMemo(
    () =>
      staff.filter((m) =>
        serviceIds.every((id) => {
          const svc = services.find((s) => s.id === id)
          return !svc || svc.employee_ids.length === 0 || svc.employee_ids.includes(m.employee_id)
        }),
      ),
    [serviceIds, services, staff],
  )
  const chosen = services.filter((s) => serviceIds.includes(s.id))
  const totalMinutes = chosen.reduce((s, x) => s + x.duration_minutes, 0)
  const totalPrice = chosen.reduce((s, x) => s + x.price_xaf, 0)
  const employeeOk = qualified.some((m) => m.employee_id === employeeId)

  useEffect(() => {
    if (!canSearchClients || clientId || clientName.trim().length < 2) return
    let alive = true
    const timer = setTimeout(() => {
      salonApi.searchClients(shopId, clientName).then(
        (rows) => alive && setMatches(rows.slice(0, 5)),
        () => alive && setMatches([]),
      )
    }, 300)
    return () => {
      alive = false
      clearTimeout(timer)
    }
  }, [shopId, clientName, clientId, canSearchClients])

  async function submit(e: FormEvent) {
    e.preventDefault()
    const minutes = duration.trim() ? Number(duration) : null
    const startsAt = walkIn ? new Date() : salonInstant(date, time, tz)
    const id = await action.run(() =>
      salonApi.saveAppointment(shopId, {
        id: editing?.id ?? null,
        clientId,
        clientName,
        clientPhone,
        employeeId,
        startsAt,
        serviceIds,
        durationMinutes: minutes,
        notes,
        source: walkIn ? 'walk_in' : 'manual',
      }),
    )
    if (id) onSaved(id)
  }

  const title = walkIn
    ? 'Client sans rendez-vous'
    : editing
      ? 'Modifier ou reporter'
      : 'Nouveau rendez-vous'
  return (
    <Dialog open onClose={onClose} labelledBy="salon-appt-title" sheet>
      <form className="dialog__body" onSubmit={(e) => void submit(e)}>
        <h2 className="dialog__title" id="salon-appt-title">
          {title}
        </h2>
        <div className="form-grid">
          <fieldset className="salon-fieldset form-grid__full">
            <legend>Prestations</legend>
            {services.length === 0 && (
              <p className="entry__meta">Ajoutez d’abord vos prestations.</p>
            )}
            <div className="salon-checks">
              {services.map((s) => (
                <label className="form-check" key={s.id}>
                  <input
                    type="checkbox"
                    checked={serviceIds.includes(s.id)}
                    onChange={(e) =>
                      setServiceIds(
                        e.target.checked
                          ? [...serviceIds, s.id]
                          : serviceIds.filter((x) => x !== s.id),
                      )
                    }
                  />
                  {s.name} · {minutesLabel(s.duration_minutes)} · {fcfa(s.price_xaf)} F
                </label>
              ))}
            </div>
            {chosen.length > 0 && (
              <p className="entry__meta">
                Durée {minutesLabel(totalMinutes)} · prix estimé {fcfa(totalPrice)} FCFA
              </p>
            )}
          </fieldset>
          <label>
            Collaborateur
            <select value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} required>
              <option value="">Choisir…</option>
              {qualified.map((m) => (
                <option key={m.employee_id} value={m.employee_id}>
                  {m.full_name}
                </option>
              ))}
            </select>
            {serviceIds.length > 0 && qualified.length === 0 && (
              <small>Personne n’est habilité pour toutes ces prestations ensemble.</small>
            )}
          </label>
          {!walkIn && (
            <>
              <label>
                Date
                <input
                  type="date"
                  value={date}
                  onChange={(e) => setDate(e.target.value)}
                  required
                />
              </label>
              <label>
                Heure (heure du salon)
                <input
                  type="time"
                  value={time}
                  step={300}
                  onChange={(e) => setTime(e.target.value)}
                  required
                />
              </label>
            </>
          )}
          <label>
            Durée en minutes <small>(vide = durée des prestations)</small>
            <input
              inputMode="numeric"
              value={duration}
              onChange={(e) => setDuration(e.target.value)}
              placeholder={String(totalMinutes || '')}
            />
          </label>
          <label>
            Client
            <input
              value={clientName}
              maxLength={160}
              autoComplete="off"
              onChange={(e) => {
                setClientName(e.target.value)
                setClientId(null)
              }}
              required
            />
            {clientId && <small>Fiche client reliée</small>}
          </label>
          {matches.length > 0 && !clientId && (
            <div className="form-grid__full salon-suggest" role="list" aria-label="Clients connus">
              {matches.map((c) => (
                <button
                  type="button"
                  role="listitem"
                  key={c.id}
                  className="salon-link"
                  onClick={() => {
                    setClientId(c.id)
                    setClientName(`${c.first_name} ${c.last_name ?? ''}`.trim())
                    setClientPhone(c.phone ?? '')
                    setMatches([])
                  }}
                >
                  {c.first_name} {c.last_name} {c.phone ? `· ${c.phone}` : ''}
                </button>
              ))}
            </div>
          )}
          <label>
            Téléphone <small>(facultatif)</small>
            <input
              type="tel"
              value={clientPhone}
              onChange={(e) => setClientPhone(e.target.value)}
            />
          </label>
          <label className="form-grid__full">
            Notes <small>(facultatif)</small>
            <textarea value={notes} maxLength={500} onChange={(e) => setNotes(e.target.value)} />
          </label>
        </div>
        <ActionMessage message={action.message} isError={action.isError} />
        <div className="dialog__actions">
          <Button variant="ghost" onClick={onClose}>
            Fermer
          </Button>
          <Button
            type="submit"
            variant="primary"
            busy={action.busy}
            disabled={serviceIds.length === 0 || !employeeOk || !clientName.trim()}
          >
            {serviceIds.length === 0
              ? 'Choisissez une prestation'
              : !employeeOk
                ? 'Choisissez un collaborateur'
                : walkIn
                  ? 'Installer le client'
                  : 'Enregistrer le rendez-vous'}
          </Button>
        </div>
      </form>
    </Dialog>
  )
}
