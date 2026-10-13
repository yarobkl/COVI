import { useEffect, useState, type FormEvent } from 'react'
import {
  OTHER_CITY,
  resolveAfricanCity,
  resolveAfricanCountry,
} from '../../lib/centralAfricaLocations'
import { CentralAfricaLocationFields } from '../locations/CentralAfricaLocationFields'
import { ShopGpsControl, type ShopGpsPosition } from '../locations/ShopGpsControl'
import { OTHER_NEIGHBORHOOD, resolveNeighborhood } from '../../lib/neighborhoods'
import { supabase } from '../../lib/supabase'
import type { Shop } from '../../lib/types'
import { ProfilePhotoEditor } from '../profile/ProfilePhotoEditor'

type ShopDraft = {
  name: string
  country: string
  city: string
  customCity: string
  neighborhood: string
  customNeighborhood: string
  gps: ShopGpsPosition | null
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
      .select('id,name,city,country,currency,neighborhood,latitude,longitude,location_accuracy_m')
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
        const neighborhood = resolveNeighborhood(data.neighborhood, country, data.city ?? '')
        setShop(data)
        setDraft({
          name: data.name,
          country,
          city,
          customCity: city === OTHER_CITY ? (data.city ?? '') : '',
          neighborhood,
          customNeighborhood:
            neighborhood === OTHER_NEIGHBORHOOD ? (data.neighborhood ?? '') : '',
          gps:
            data.latitude !== null && data.longitude !== null
              ? { latitude: data.latitude, longitude: data.longitude,
                  accuracy: data.location_accuracy_m ?? 0.1 }
              : null,
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
      neighborhood: (
        draft.neighborhood === OTHER_NEIGHBORHOOD
          ? draft.customNeighborhood
          : draft.neighborhood
      ).trim(),
      latitude: draft.gps?.latitude ?? null,
      longitude: draft.gps?.longitude ?? null,
      location_accuracy_m: draft.gps?.accuracy ?? null,
    }
    if (!payload.name) {
      setMsg('Le nom de la boutique est obligatoire.')
      return
    }
    if (
      !payload.country ||
      (draft.city === OTHER_CITY && !payload.city) ||
      (resolveAfricanCountry(shop.country) !== payload.country && !payload.city) ||
      ((resolveAfricanCountry(shop.country) !== payload.country ||
        (shop.city ?? '') !== payload.city) &&
        !payload.neighborhood) ||
      (draft.neighborhood === OTHER_NEIGHBORHOOD && !payload.neighborhood)
    ) {
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
    return loadError ? <p role="alert">{msg}</p> : <p>Chargement des paramètres…</p>
  }

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
        <CentralAfricaLocationFields
          country={draft.country}
          city={draft.city}
          customCity={draft.customCity}
          neighborhood={draft.neighborhood}
          customNeighborhood={draft.customNeighborhood}
          onNeighborhoodChange={(neighborhood) =>
            setDraft({ ...draft, neighborhood, customNeighborhood: '' })
          }
          onCustomNeighborhoodChange={(customNeighborhood) =>
            setDraft({ ...draft, customNeighborhood })
          }
          onCountryChange={(country) =>
            setDraft({
              ...draft,
              country,
              city: '',
              customCity: '',
              neighborhood: '',
              customNeighborhood: '',
              gps: null,
            })
          }
          onCityChange={(city) =>
            setDraft({
              ...draft,
              city,
              customCity: '',
              neighborhood: '',
              customNeighborhood: '',
            })
          }
          onCustomCityChange={(customCity) =>
            setDraft({ ...draft, customCity, neighborhood: '', customNeighborhood: '', gps: null })
          }
        />
        <ShopGpsControl value={draft.gps} onChange={(gps) => setDraft({ ...draft, gps })} />
        <label>
          Devise
          <input value={shop.currency} disabled />
          <small>La devise du commerce reste XAF pour cette version.</small>
        </label>
        <button className="primary span2" disabled={busy}>
          {busy ? 'Enregistrement…' : 'Enregistrer les paramètres'}
        </button>
      </form>
      {msg && (
        <p className="successmsg" role="status">
          {msg}
        </p>
      )}
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
