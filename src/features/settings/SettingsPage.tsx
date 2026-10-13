import { useEffect, useState, type FormEvent } from 'react'
import {
  CENTRAL_AFRICA,
  listedAfricanCities,
  OTHER_CITY,
  resolveAfricanCity,
  resolveAfricanCountry,
} from '../../lib/centralAfricaLocations'
import { supabase } from '../../lib/supabase'
import type { Shop } from '../../lib/types'
import { ProfilePhotoEditor } from '../profile/ProfilePhotoEditor'

type ShopDraft = {
  name: string
  country: string
  city: string
  customCity: string
}

/** Existing shops get the same country/city selector as new boutiques. */
export function SettingsPage({
  shopId,
  onShopUpdated,
}: {
  shopId: string
  onShopUpdated: (shop: Shop) => void
}) {
  const [shop, setShop] = useState<Shop | null>(null)
  const [draft, setDraft] = useState<ShopDraft | null>(null)
  const [msg, setMsg] = useState('')
  const [loadError, setLoadError] = useState(false)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    let active = true
    void supabase
      .from('shops')
      .select('id,name,city,country,currency')
      .eq('id', shopId)
      .single()
      .then(({ data, error }) => {
        if (!active) return
        if (error || !data) {
          setLoadError(true)
          setMsg('Impossible de charger votre boutique. Vérifiez votre connexion puis réessayez.')
          return
        }
        const country = resolveAfricanCountry(data.country)
        const city = resolveAfricanCity(data.city, country)
        setShop(data)
        setDraft({
          name: data.name,
          country,
          city,
          customCity: city === OTHER_CITY ? (data.city ?? '') : '',
        })
        setLoadError(false)
        setMsg('')
      })
    return () => {
      active = false
    }
  }, [shopId])

  async function save(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    if (!shop || !draft || busy) return

    const payload = {
      name: draft.name.trim(),
      country: draft.country.trim(),
      city: (draft.city === OTHER_CITY ? draft.customCity : draft.city).trim(),
    }
    if (!payload.name) {
      setMsg('Le nom de la boutique est obligatoire.')
      return
    }
    if (!payload.country || (draft.city === OTHER_CITY && !payload.city)) {
      setMsg('Choisissez un pays et renseignez votre ville ou localité.')
      return
    }

    setBusy(true)
    setMsg('')
    try {
      const { data, error } = await supabase
        .from('shops')
        .update(payload)
        .eq('id', shopId)
        .select('id,name,city,country,currency')
        .single()
      if (error || !data) {
        setMsg('Impossible d’enregistrer les paramètres. Vérifiez votre connexion puis réessayez.')
        return
      }
      const next: Shop = data
      setShop(next)
      onShopUpdated(next)
      setMsg('✓ Paramètres enregistrés.')
    } catch {
      setMsg('Impossible d’enregistrer les paramètres. Vérifiez votre connexion puis réessayez.')
    } finally {
      setBusy(false)
    }
  }

  if (!shop || !draft) {
    return loadError ? (
      <p role="alert">{msg}</p>
    ) : (
      <p>Chargement des paramètres…</p>
    )
  }

  const cities = listedAfricanCities(draft.country)
  const legacyCountry = !CENTRAL_AFRICA.some((entry) => entry.country === draft.country)

  return (
    <div>
      <div className="hello">
        <div>
          <h1>Paramètres</h1>
          <span>Identité et informations principales de votre commerce.</span>
        </div>
      </div>
      <ProfilePhotoEditor />
      <form className="card formgrid" onSubmit={(e) => void save(e)}>
        <label>
          Nom de la boutique
          <input
            name="name"
            required
            value={draft.name}
            onChange={(e) => setDraft({ ...draft, name: e.target.value })}
          />
        </label>
        <label>
          Pays
          <select
            className="input"
            name="country"
            required
            value={draft.country}
            onChange={(e) =>
              setDraft({
                ...draft,
                country: e.target.value,
                city: '',
                customCity: '',
              })
            }
          >
            {legacyCountry && <option value={draft.country}>{draft.country}</option>}
            {CENTRAL_AFRICA.map((entry) => (
              <option key={entry.country} value={entry.country}>
                {entry.country}
              </option>
            ))}
          </select>
        </label>
        <label>
          Ville
          <select
            className="input"
            name="city"
            value={draft.city}
            onChange={(e) =>
              setDraft({
                ...draft,
                city: e.target.value,
                customCity: e.target.value === OTHER_CITY ? draft.customCity : '',
              })
            }
          >
            <option value="">Choisir une ville</option>
            {cities.map((value) => (
              <option key={value} value={value}>
                {value}
              </option>
            ))}
            <option value={OTHER_CITY}>Ma ville n’apparaît pas</option>
          </select>
        </label>
        {draft.city === OTHER_CITY && (
          <label>
            Ma ville ou localité
            <input
              name="customCity"
              required
              placeholder="Ex. quartier ou localité"
              value={draft.customCity}
              onChange={(e) => setDraft({ ...draft, customCity: e.target.value })}
            />
          </label>
        )}
        <label>
          Devise
          <input value={shop.currency} disabled />
          <small>La devise du commerce reste XAF pour cette version.</small>
        </label>
        <button className="primary span2" disabled={busy}>
          {busy ? 'Enregistrement…' : 'Enregistrer les paramètres'}
        </button>
      </form>
      {msg && <p className="successmsg" role="status">{msg}</p>}
      <section className="card">
        <small>COVI V1</small>
        <h2>Commerce connecté</h2>
        <p>
          Vos données sont protégées par votre compte COVI et synchronisées avec votre espace
          Supabase.
        </p>
      </section>
    </div>
  )
}
