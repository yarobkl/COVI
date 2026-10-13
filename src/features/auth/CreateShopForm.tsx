import { useState, type FormEvent } from 'react'
import { Button, Field, Input, LabelCard, Notice } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import type { Shop } from '../../lib/types'
import { OTHER_CITY } from '../../lib/centralAfricaLocations'
import { OTHER_NEIGHBORHOOD } from '../../lib/neighborhoods'
import { CentralAfricaLocationFields } from '../locations/CentralAfricaLocationFields'
import { ShopGpsControl, type ShopGpsPosition } from '../locations/ShopGpsControl'
import { AuthPage } from './AuthPage'
import { authError } from './authErrors'

/** First sign-in: creates the owner's shop (currency fixed to XAF). */
export function CreateShopForm({
  message,
  onMessage,
  onCreated,
}: {
  message: string
  onMessage: (message: string) => void
  onCreated: (shop: Shop) => void
}) {
  const [name, setName] = useState('')
  const [city, setCity] = useState('')
  const [country, setCountry] = useState<string>('République du Congo')
  const [customCity, setCustomCity] = useState('')
  const [neighborhood, setNeighborhood] = useState('')
  const [customNeighborhood, setCustomNeighborhood] = useState('')
  const [gps, setGps] = useState<ShopGpsPosition | null>(null)
  const selectedCity = city === OTHER_CITY ? customCity.trim() : city
  const selectedNeighborhood =
    neighborhood === OTHER_NEIGHBORHOOD ? customNeighborhood.trim() : neighborhood.trim()
  const [busy, setBusy] = useState(false)

  async function createShop(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    onMessage('')
    const f = new FormData(e.currentTarget)
    if (!selectedCity.trim() || !selectedNeighborhood) {
      onMessage('Choisissez votre ville et votre quartier, ou saisissez-les manuellement.')
      return
    }
    setBusy(true)
    try {
      const { data, error } = await supabase.rpc('create_my_shop_with_location', {
        p_name: String(f.get('name')).trim(),
        p_city: selectedCity.trim(),
        p_neighborhood: selectedNeighborhood,
        p_country: country,
        p_currency: 'XAF',
        p_latitude: gps?.latitude ?? undefined,
        p_longitude: gps?.longitude ?? undefined,
        p_location_accuracy_m: gps?.accuracy ?? undefined,
      })
      if (error) onMessage(authError(error))
      else onCreated(data)
    } finally {
      setBusy(false)
    }
  }

  // The notebook label fills in as the name is typed.
  const preview = (
    <figure className="auth__preview">
      <LabelCard>
        <p className="sommaire__shop-kicker">Cahier de caisse</p>
        <p className="sommaire__shop-name">{name.trim() || 'Votre boutique'}</p>
        <p className="sommaire__shop-place">{selectedCity || 'Votre ville'}</p>
      </LabelCard>
      <figcaption className="hand auth__preview-note">
        votre étiquette, en haut du cahier
      </figcaption>
    </figure>
  )

  return (
    <AuthPage
      title="Comment s’appelle votre boutique ?"
      lead="Ce nom s’affichera en haut de l’écran. Vous pourrez le changer plus tard."
      aside={preview}
    >
      <form className="auth__form" onSubmit={createShop}>
        <Field label="Nom de la boutique">
          {(control) => (
            <Input
              {...control}
              name="name"
              required
              placeholder="Ex. Chez Mama Grâce"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          )}
        </Field>
        <CentralAfricaLocationFields
          country={country}
          city={city}
          customCity={customCity}
          requireCity
          requireNeighborhood
          neighborhood={neighborhood}
          customNeighborhood={customNeighborhood}
          onNeighborhoodChange={(value) => {
            setNeighborhood(value)
            setCustomNeighborhood('')
          }}
          onCustomNeighborhoodChange={setCustomNeighborhood}
          onCountryChange={(value) => {
            setCountry(value)
            setCity('')
            setCustomCity('')
            setNeighborhood('')
            setCustomNeighborhood('')
            setGps(null)
          }}
          onCityChange={(value) => {
            setCity(value)
            setCustomCity('')
            setNeighborhood('')
            setCustomNeighborhood('')
            setGps(null)
          }}
          onCustomCityChange={(value) => {
            setCustomCity(value)
            setNeighborhood('')
            setCustomNeighborhood('')
            setGps(null)
          }}
        />
        <ShopGpsControl value={gps} onChange={setGps} />
        {message && (
          <Notice tone="danger">
            <p>{message}</p>
          </Notice>
        )}
        <Button variant="primary" size="lg" block type="submit" busy={busy}>
          Créer ma boutique
        </Button>
      </form>
    </AuthPage>
  )
}
