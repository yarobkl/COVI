import { useState, type FormEvent } from 'react'
import { Button, Field, Input, LabelCard, Notice } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import type { Shop } from '../../lib/types'
import { AuthPage } from './AuthPage'
import { authError } from './authErrors'

const CENTRAL_AFRICA = [
  { country: 'République du Congo', cities: ['Brazzaville', 'Pointe-Noire', 'Dolisie', 'Nkayi', 'Ouesso', 'Owando', 'Oyo', 'Impfondo', 'Sibiti', 'Madingou', 'Kinkala', 'Djambala', 'Ewo', 'Mossendjo', 'Makoua', 'Gamboma', 'Mindouli', 'Loango'] },
  { country: 'République démocratique du Congo', cities: ['Kinshasa', 'Lubumbashi', 'Mbuji-Mayi', 'Kananga', 'Kisangani', 'Goma', 'Bukavu', 'Kolwezi', 'Likasi', 'Matadi', 'Kikwit', 'Bunia', 'Beni'] },
  { country: 'Cameroun', cities: ['Yaoundé', 'Douala', 'Bafoussam', 'Garoua', 'Bamenda', 'Maroua', 'Ngaoundéré', 'Bertoua', 'Ebolowa', 'Kribi', 'Limbé', 'Buéa'] },
  { country: 'Gabon', cities: ['Libreville', 'Port-Gentil', 'Franceville', 'Oyem', 'Moanda', 'Lambaréné', 'Mouila', 'Tchibanga', 'Makokou'] },
  { country: 'République centrafricaine', cities: ['Bangui', 'Bimbo', 'Berbérati', 'Bambari', 'Bouar', 'Bossangoa', 'Bria', 'Carnot'] },
  { country: 'Tchad', cities: ["N'Djamena", 'Moundou', 'Sarh', 'Abéché', 'Kélo', 'Doba', 'Koumra', 'Mongo', 'Pala'] },
  { country: 'Guinée équatoriale', cities: ['Malabo', 'Bata', 'Ebebiyín', 'Mongomo', 'Luba', 'Evinayong'] },
  { country: 'São Tomé-et-Príncipe', cities: ['São Tomé', 'Santo António', 'Trindade', 'Neves', 'Santana'] },
  { country: 'Angola', cities: ['Luanda', 'Huambo', 'Benguela', 'Lobito', 'Lubango', 'Cabinda', 'Malanje', 'Namibe', 'Soyo', 'Uíge'] },
  { country: 'Burundi', cities: ['Bujumbura', 'Gitega', 'Ngozi', 'Rumonge', 'Muyinga', 'Kayanza', 'Bururi'] },
  { country: 'Rwanda', cities: ['Kigali', 'Huye', 'Musanze', 'Rubavu', 'Muhanga', 'Rusizi', 'Nyagatare'] },
] as const

const OTHER_CITY = '__other__'

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
  const availableCities = CENTRAL_AFRICA.find((entry) => entry.country === country)?.cities ?? []
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
                <option key={entry.country} value={entry.country}>{entry.country}</option>
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
                <option key={value} value={value}>{value}</option>
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
