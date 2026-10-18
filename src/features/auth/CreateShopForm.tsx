import { useState, type FormEvent } from 'react'
import { Button, Field, Input, LabelCard, Notice } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { BUSINESS_KINDS, businessKindInfo, type BusinessKind } from '../../lib/businessKinds'
import {
  clearOwnerOAuthIntent,
  createOwnerSignupDetails,
  isValidOwnerPhone,
  ownerOnboardingHints,
} from '../../lib/ownerSignup'
import type { Shop } from '../../lib/types'
import { OTHER_CITY } from '../../lib/centralAfricaLocations'
import { OTHER_NEIGHBORHOOD } from '../../lib/neighborhoods'
import { OTHER_ADMIN_AREA, isValidBusinessAddress } from '../../lib/cemacAreas'
import { currencyLabel, officialCurrencyForCountry } from '../../lib/africanMarkets'
import {
  CemacBusinessAddressFields,
  type BusinessLocation,
} from '../locations/CemacBusinessAddressFields'
import { ShopGpsControl, type ShopGpsPosition } from '../locations/ShopGpsControl'
import { AuthPage } from './AuthPage'
import { authError } from './authErrors'

/** First sign-in: creates the owner's business with country-specific bookkeeping currency. */
export function CreateShopForm({
  message,
  onMessage,
  onCreated,
  onJoin,
  accountMetadata,
}: {
  message: string
  onMessage: (message: string) => void
  onCreated: (shop: Shop) => void
  /** « J’ai un code de caissier » : opens the join page instead of creating a shop. */
  onJoin?: () => void
  accountMetadata?: Record<string, unknown> | null
}) {
  const hints = ownerOnboardingHints(accountMetadata)
  const [name, setName] = useState(hints.businessName)
  const [businessKind, setBusinessKind] = useState<BusinessKind>(hints.businessKind)
  const [firstName, setFirstName] = useState(hints.firstName)
  const [lastName, setLastName] = useState(hints.lastName)
  const [phone, setPhone] = useState(hints.phone)
  const needsOwnerIdentity = !hints.firstName || !hints.lastName || !isValidOwnerPhone(hints.phone)
  const kindInfo = businessKindInfo(businessKind)
  const [location, setLocation] = useState<BusinessLocation>({
    country: 'République du Congo',
    city: '',
    customCity: '',
    area: '',
    customArea: '',
    neighborhood: '',
    customNeighborhood: '',
    streetAddress: '',
  })
  const [gps, setGps] = useState<ShopGpsPosition | null>(null)
  const selectedCity = location.city === OTHER_CITY ? location.customCity.trim() : location.city
  const selectedArea =
    location.area === OTHER_ADMIN_AREA ? location.customArea.trim() : location.area.trim()
  const selectedNeighborhood =
    location.neighborhood === OTHER_NEIGHBORHOOD
      ? location.customNeighborhood.trim()
      : location.neighborhood.trim()
  const currency = officialCurrencyForCountry(location.country)
  const [busy, setBusy] = useState(false)

  async function createShop(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    onMessage('')
    const f = new FormData(e.currentTarget)
    if (!currency) {
      onMessage('Choisissez un pays couvert par COVI.')
      return
    }
    if (!selectedCity.trim() || !selectedArea || !selectedNeighborhood) {
      onMessage('Indiquez votre ville, arrondissement / commune et quartier.')
      return
    }
    if (!isValidBusinessAddress(location.streetAddress)) {
      onMessage('L’adresse physique de votre établissement est obligatoire (10 à 240 caractères).')
      return
    }
    if (businessKind !== 'retail') {
      onMessage(
        'Le module Restaurant ou Salon est encore en préparation. Votre compte est conservé ; l’ouverture de cet établissement sera disponible après validation.',
      )
      return
    }
    if (currency !== 'XAF') {
      onMessage(
        'Le pays et sa monnaie sont enregistrés dans votre choix, mais la caisse de ce pays n’est pas encore validée. Les ouvertures actives sont limitées à la zone CEMAC (XAF).',
      )
      return
    }
    setBusy(true)
    try {
      // Google/Facebook and older users may need to complete their owner profile.
      // Metadata is profile-only, NEVER a tenant authorization source.
      if (needsOwnerIdentity) {
        const details = createOwnerSignupDetails({
          firstName,
          lastName,
          phone,
          businessKind,
          businessName: name,
        })
        const { error: profileError } = await supabase.auth.updateUser({
          data: {
            first_name: details.first_name,
            last_name: details.last_name,
            full_name: details.full_name,
            phone_number: details.phone_number,
            business_kind: details.business_kind,
            business_name: details.business_name,
          },
        })
        if (profileError) throw profileError
      }
      const { data, error } = await supabase.rpc('create_my_retail_shop_with_address', {
        p_name: String(f.get('name')).trim(),
        p_city: selectedCity.trim(),
        p_administrative_area: selectedArea,
        p_neighborhood: selectedNeighborhood,
        p_address_line: location.streetAddress.trim(),
        p_country: location.country,
        p_currency: currency,
        p_latitude: gps?.latitude ?? undefined,
        p_longitude: gps?.longitude ?? undefined,
        p_location_accuracy_m: gps?.accuracy ?? undefined,
      })
      if (error) onMessage(authError(error))
      else {
        clearOwnerOAuthIntent()
        onCreated(data)
      }
    } catch (error) {
      onMessage(error instanceof Error ? error.message : 'Création impossible. Réessayez.')
    } finally {
      setBusy(false)
    }
  }

  // The notebook label fills in as the name is typed.
  const preview = (
    <figure className="auth__preview">
      <LabelCard>
        <p className="sommaire__shop-kicker">Cahier de gestion</p>
        <p className="sommaire__shop-name">{name.trim() || kindInfo.preview}</p>
        <p className="sommaire__shop-place">{selectedCity || 'Votre ville'}</p>
        {currency && <p className="sommaire__shop-place">{currencyLabel(currency)}</p>}
      </LabelCard>
      <figcaption className="hand auth__preview-note">
        votre étiquette, en haut du cahier
      </figcaption>
    </figure>
  )

  return (
    <AuthPage
      title="Finalisez votre établissement"
      lead="Choisissez votre activité, votre pays et renseignez l’adresse physique de votre établissement."
      aside={
        <>
          {preview}
          {onJoin && (
            <div className="auth__join">
              <p>Vous travaillez dans la boutique de quelqu’un ?</p>
              <Button variant="secondary" size="lg" block onClick={onJoin}>
                J’ai un code de caissier
              </Button>
            </div>
          )}
        </>
      }
    >
      <form className="auth__form" onSubmit={createShop}>
        {needsOwnerIdentity && (
          <>
            <Field label="Prénom du propriétaire">
              {(control) => (
                <Input
                  {...control}
                  name="first-name"
                  autoComplete="given-name"
                  required
                  minLength={2}
                  maxLength={80}
                  value={firstName}
                  onChange={(e) => setFirstName(e.target.value)}
                />
              )}
            </Field>
            <Field label="Nom du propriétaire">
              {(control) => (
                <Input
                  {...control}
                  name="last-name"
                  autoComplete="family-name"
                  required
                  minLength={2}
                  maxLength={80}
                  value={lastName}
                  onChange={(e) => setLastName(e.target.value)}
                />
              )}
            </Field>
            <Field
              label="Téléphone du propriétaire"
              hint="Indiquez un numéro international, par exemple +242061234567."
            >
              {(control) => (
                <Input
                  {...control}
                  name="phone"
                  autoComplete="tel"
                  type="tel"
                  required
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                />
              )}
            </Field>
          </>
        )}
        <fieldset>
          <legend>Que gérez-vous avec COVI ?</legend>
          {BUSINESS_KINDS.map((kind) => (
            <label key={kind.value} style={{ display: 'block', marginTop: '0.65rem' }}>
              <input
                type="radio"
                name="business-kind"
                value={kind.value}
                checked={businessKind === kind.value}
                onChange={() => setBusinessKind(kind.value)}
              />{' '}
              {kind.label}
            </label>
          ))}
        </fieldset>
        <Field label={kindInfo.nameLabel}>
          {(control) => (
            <Input
              {...control}
              name="name"
              required
              placeholder={kindInfo.example}
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          )}
        </Field>
        <CemacBusinessAddressFields
          value={location}
          onChange={(next) => {
            if (
              next.country !== location.country ||
              next.city !== location.city ||
              next.customCity !== location.customCity
            ) {
              setGps(null)
            }
            setLocation(next)
          }}
        />
        <ShopGpsControl value={gps} onChange={setGps} />
        {(businessKind !== 'retail' || currency !== 'XAF') && (
          <Notice tone="info">
            <p>
              {businessKind !== 'retail'
                ? 'Le module Restaurant / Salon est en préparation : votre compte existe, mais cet établissement ne peut pas encore être créé.'
                : 'COVI prépare les calculs financiers pour cette devise. Les ouvertures actuellement actives concernent les boutiques de la zone CEMAC (XAF).'}
            </p>
          </Notice>
        )}
        {message && (
          <Notice tone="danger">
            <p>{message}</p>
          </Notice>
        )}
        <Button
          variant="primary"
          size="lg"
          block
          type="submit"
          busy={busy}
          disabled={businessKind !== 'retail' || currency !== 'XAF'}
        >
          Créer mon établissement
        </Button>
      </form>
    </AuthPage>
  )
}
