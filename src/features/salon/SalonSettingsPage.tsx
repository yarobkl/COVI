import { useCallback, useState, type FormEvent } from 'react'
import { Button, PageHead, Sheet } from '../../components/ui'
import { salonApi, type SalonSettings, type SalonType } from '../../lib/salon'
import { ActionMessage, Loaded } from './SalonParts'
import { salonTypeLabels, weekdayLabels } from './salonFormat'
import { useSalonAction, useSalonLoad } from './useSalonLoad'

type Hours = { on: boolean; opens: string; closes: string }[]

const zones = [
  ['Africa/Brazzaville', 'Brazzaville, Pointe-Noire (UTC+1)'],
  ['Africa/Kinshasa', 'Kinshasa (UTC+1)'],
  ['Africa/Douala', 'Douala, Yaoundé (UTC+1)'],
  ['Africa/Libreville', 'Libreville (UTC+1)'],
  ['Africa/Ndjamena', 'N’Djamena (UTC+1)'],
  ['Africa/Bangui', 'Bangui (UTC+1)'],
  ['Africa/Malabo', 'Malabo (UTC+1)'],
  ['Africa/Lubumbashi', 'Lubumbashi (UTC+2)'],
  ['Africa/Abidjan', 'Abidjan (UTC+0)'],
  ['Africa/Dakar', 'Dakar (UTC+0)'],
] as const

function hoursOf(s: SalonSettings): Hours {
  const base: Hours = Array.from({ length: 7 }, (_, i) => ({
    on: i < 6,
    opens: '08:00',
    closes: '19:00',
  }))
  // Suggested hours only for a salon that has never configured its schedule.
  // After saving every day as closed, don't silently switch the UI back to "open".
  if (!s.configured) return base
  return base.map((_, i) => {
    const h = s.opening_hours.find((x) => x.weekday === i + 1)
    return h
      ? { on: true, opens: h.opens_at, closes: h.closes_at }
      : { on: false, opens: '08:00', closes: '19:00' }
  })
}

/** Réglages du salon : type, responsable, téléphone, fuseau, jours et heures d'ouverture. */
export function SalonSettingsPage({ shopId, onSaved }: { shopId: string; onSaved?: () => void }) {
  const load = useCallback(() => salonApi.settings(shopId), [shopId])
  const data = useSalonLoad(load)
  return (
    <div className="page-stack">
      <PageHead
        title="Réglages du salon"
        sub="Ces informations servent à l’agenda : on ne peut pas réserver quand le salon est fermé."
      />
      <Loaded loading={data.loading} error={data.error}>
        {data.data && (
          <SettingsForm
            key={data.data.shop.id}
            shopId={shopId}
            initial={data.data}
            onSaved={onSaved}
          />
        )}
      </Loaded>
    </div>
  )
}

function SettingsForm({
  shopId,
  initial,
  onSaved,
}: {
  shopId: string
  initial: SalonSettings
  onSaved?: () => void
}) {
  const action = useSalonAction()
  const [type, setType] = useState<SalonType>(initial.settings.salon_type)
  const [owner, setOwner] = useState(initial.settings.owner_name ?? '')
  const [phone, setPhone] = useState(initial.settings.business_phone ?? '')
  const [staffCount, setStaffCount] = useState(
    initial.settings.expected_staff_count?.toString() ?? '',
  )
  const [zone, setZone] = useState(initial.settings.time_zone)
  const [hours, setHours] = useState<Hours>(() => hoursOf(initial))

  async function save(e: FormEvent) {
    e.preventDefault()
    const bad = hours.some((h) => h.on && h.closes <= h.opens)
    if (bad) {
      action.setIsError(true)
      action.setMessage('L’heure de fermeture doit être après l’ouverture.')
      return
    }
    const done = await action.run(
      () =>
        salonApi.saveSettings(shopId, {
          salonType: type,
          ownerName: owner,
          phone,
          staffCount: staffCount.trim() ? Number(staffCount) : null,
          timeZone: zone,
          hours: hours.flatMap((h, i) =>
            h.on ? [{ weekday: i + 1, opens_at: h.opens, closes_at: h.closes }] : [],
          ),
        }),
      'Réglages enregistrés.',
    )
    if (done) onSaved?.()
  }

  return (
    <Sheet>
      <form className="form-grid" onSubmit={(e) => void save(e)}>
        <p className="form-grid__note">
          {initial.shop.name} ·{' '}
          {[initial.shop.neighborhood, initial.shop.city, initial.shop.country]
            .filter(Boolean)
            .join(', ')}
          {initial.shop.address_line ? ` · ${initial.shop.address_line}` : ''} ·{' '}
          {initial.shop.currency}
        </p>
        <label>
          Type de salon
          <select value={type} onChange={(e) => setType(e.target.value as SalonType)}>
            {(Object.keys(salonTypeLabels) as SalonType[]).map((t) => (
              <option key={t} value={t}>
                {salonTypeLabels[t]}
              </option>
            ))}
          </select>
        </label>
        <label>
          Nom du propriétaire
          <input value={owner} maxLength={120} onChange={(e) => setOwner(e.target.value)} />
        </label>
        <label>
          Téléphone professionnel
          <input type="tel" value={phone} onChange={(e) => setPhone(e.target.value)} />
        </label>
        <label>
          Nombre de collaborateurs prévus <small>(facultatif)</small>
          <input
            inputMode="numeric"
            value={staffCount}
            onChange={(e) => setStaffCount(e.target.value)}
          />
        </label>
        <label className="form-grid__full">
          Fuseau horaire
          <select value={zone} onChange={(e) => setZone(e.target.value)}>
            {zones.map(([z, label]) => (
              <option key={z} value={z}>
                {label}
              </option>
            ))}
          </select>
        </label>
        <fieldset className="salon-fieldset form-grid__full">
          <legend>Jours et heures d’ouverture</legend>
          {hours.map((h, i) => (
            <div className="salon-hours" key={i}>
              <label className="form-check">
                <input
                  type="checkbox"
                  checked={h.on}
                  onChange={(e) =>
                    setHours(hours.map((x, j) => (j === i ? { ...x, on: e.target.checked } : x)))
                  }
                />
                {weekdayLabels[i]}
              </label>
              {h.on ? (
                <>
                  <input
                    type="time"
                    aria-label={`Ouverture ${weekdayLabels[i]}`}
                    value={h.opens}
                    onChange={(e) =>
                      setHours(hours.map((x, j) => (j === i ? { ...x, opens: e.target.value } : x)))
                    }
                  />
                  <input
                    type="time"
                    aria-label={`Fermeture ${weekdayLabels[i]}`}
                    value={h.closes}
                    onChange={(e) =>
                      setHours(
                        hours.map((x, j) => (j === i ? { ...x, closes: e.target.value } : x)),
                      )
                    }
                  />
                </>
              ) : (
                <span className="entry__meta">Fermé</span>
              )}
            </div>
          ))}
        </fieldset>
        <div className="form-grid__actions">
          <Button type="submit" variant="primary" busy={action.busy}>
            Enregistrer les réglages
          </Button>
        </div>
        <div className="form-grid__full">
          <ActionMessage message={action.message} isError={action.isError} />
        </div>
      </form>
    </Sheet>
  )
}
