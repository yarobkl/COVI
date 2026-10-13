import { useState, type FormEvent } from 'react'
import { Button, Field, Input, LabelCard, Notice } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import type { Shop } from '../../lib/types'
import { CENTRAL_AFRICA, listedAfricanCities, OTHER_CITY } from '../../lib/centralAfricaLocations'
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
  const availableCities = listedAfricanCities(country)
  const selectedCity = city === OTHER_CITY ? customCity.trim() : city
  const [busy, setBusy] = useState(false)

  async function createShop(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    onMessage('')
    const f = new FormData(e.currentTarget)
    if (!selectedCity.trim()) {
      onMessage('Choisissez votre ville ou renseignez votre localité.')
      return
    }
    setBusy(true)
    try {
      const { data, error } = await supabase.rpc('create_my_shop', {
        p_name: String(f.get('name')).trim(),
        p_city: selectedCity.trim(),
        p_country: country,
        p_currency: 'XAF',
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
        <Field label="Pays">
          {(control) => (
            <select
              {...control}
              name="country"
              className="input"
              value={country}
              required
              onChange={(e) => {
                setCountry(e.target.value)
                setCity('')
                setCustomCity('')
              }}
            >
              {CENTRAL_AFRICA.map((entry) => (
                <option key={entry.country} value={entry.country}>
                  {entry.country}
                </option>
              ))}
            </select>
          )}
        </Field>
        <Field label="Ville">
          {(control) => (
            <select
              {...control}
              name="city"
              className="input"
              value={city}
              required
              onChange={(e) => {
                setCity(e.target.value)
                setCustomCity('')
              }}
            >
              <option value="">Choisir une ville</option>
              {availableCities.map((value) => (
                <option key={value} value={value}>
                  {value}
                </option>
              ))}
              <option value={OTHER_CITY}>Ma ville n’apparaît pas</option>
            </select>
          )}
        </Field>
        {city === OTHER_CITY && (
          <Field label="Ma ville ou localité">
            {(control) => (
              <Input
                {...control}
                name="customCity"
                required
                placeholder="Saisissez votre ville"
                value={customCity}
                onChange={(e) => setCustomCity(e.target.value)}
              />
            )}
          </Field>
        )}
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
