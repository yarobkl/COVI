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
import { OTHER_ADMIN_AREA, isCemacCountry, isValidBusinessAddress } from '../../lib/cemacAreas'
import {
  CemacBusinessAddressFields,
  type BusinessLocation,
} from '../locations/CemacBusinessAddressFields'
import { ShopGpsControl, type ShopGpsPosition } from '../locations/ShopGpsControl'
import { AuthPage } from './AuthPage'
import { authError } from './authErrors'

/** First sign-in: creates the owner's shop (currency fixed to XAF). */
export function CreateShopForm({
  message,
  onMessage,
  onCreated,
  onJoin,
  onRestaurantJoin,
  accountMetadata,
}: {
  message: string
  onMessage: (message: string) => void
  onCreated: (shop: Shop) => void
  /** « J’ai un code de caissier » : opens the join page instead of creating a shop. */
  onJoin?: () => void
  onRestaurantJoin?: () => void
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
  const selectedCity =
    location.city === OTHER_CITY ? location.customCity.trim() : location.city
  const selectedArea =
    location.area === OTHER_ADMIN_AREA ? location.customArea.trim() : location.area.trim()
  const selectedNeighborhood =
    location.neighborhood === OTHER_NEIGHBORHOOD
      ? location.customNeighborhood.trim()
      : location.neighborhood.trim()
  const [busy, setBusy] = useState(false)

  async function createShop(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    onMessage('')
    const f = new FormData(e.currentTarget)
    if (!isCemacCountry(location.country)) {
      onMessage('Choisissez un pays de la zone CEMAC.')
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
      const { data, error } = await supabase.rpc('create_my_business_with_address', {
        p_business_kind: businessKind,
        p_name: String(f.get('name')).trim(),
        p_city: selectedCity.trim(),
        p_administrative_area: selectedArea,
        p_neighborhood: selectedNeighborhood,
        p_address_line: location.streetAddress.trim(),
        p_country: location.country,
        p_currency: 'XAF',
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
      </LabelCard>
      <figcaption className="hand auth__preview-note">
        votre étiquette, en haut du cahier
      </figcaption>
    </figure>
  )

  return (
    <AuthPage
      title="Finalisez votre établissement"
      lead="Votre compte est connecté. Vérifiez votre activité et indiquez où se trouve votre établissement."
      aside={
        <>
          {preview}
          {onRestaurantJoin && (
            <div className="auth__join">
              <p>Vous travaillez dans le restaurant de quelqu’un ?</p>
              <Button variant="secondary" size="lg" block onClick={onRestaurantJoin}>
                J’ai un code d’employé de restaurant
              </Button>
            </div>
          )}
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
        {message && (
          <Notice tone="danger">
            <p>{message}</p>
          </Notice>
        )}
        <Button variant="primary" size="lg" block type="submit" busy={busy}>
          Créer mon établissement
        </Button>
      </form>
    </AuthPage>
  )
}
