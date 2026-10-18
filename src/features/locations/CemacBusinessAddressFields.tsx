import { useState } from 'react'
import { Field, Input } from '../../components/ui'
import { listedAfricanCities, OTHER_CITY } from '../../lib/centralAfricaLocations'
import { OTHER_NEIGHBORHOOD } from '../../lib/neighborhoods'
import { administrativeAreas, neighborhoodsForArea, OTHER_ADMIN_AREA } from '../../lib/cemacAreas'
import {
  AFRICAN_MARKET_GROUPS,
  AFRICAN_MARKETS,
  currencyLabel,
  marketForCountry,
  paymentCurrenciesForCountry,
} from '../../lib/africanMarkets'

export type BusinessLocation = {
  country: string
  city: string
  customCity: string
  area: string
  customArea: string
  neighborhood: string
  customNeighborhood: string
  streetAddress: string
}

export function CemacBusinessAddressFields({
  value,
  onChange,
}: {
  value: BusinessLocation
  onChange: (value: BusinessLocation) => void
}) {
  const [query, setQuery] = useState('')
  const market = marketForCountry(value.country)
  const cityName = value.city === OTHER_CITY ? value.customCity.trim() : value.city
  const areaName = value.area === OTHER_ADMIN_AREA ? value.customArea.trim() : value.area
  const cities = listedAfricanCities(value.country)
  const areas = administrativeAreas(value.country, cityName)
  const quartiers = neighborhoodsForArea(value.country, cityName, areaName)
  const visibleQuartiers = quartiers.filter((name) =>
    name.toLocaleLowerCase('fr').includes(query.trim().toLocaleLowerCase('fr')),
  )
  const change = (patch: Partial<BusinessLocation>) => onChange({ ...value, ...patch })

  return (
    <>
      <Field label="Pays de l’établissement">
        {(control) => (
          <select
            {...control}
            className="input"
            name="country"
            value={value.country}
            required
            onChange={(e) => {
              setQuery('')
              change({
                country: e.target.value,
                city: '',
                customCity: '',
                area: '',
                customArea: '',
                neighborhood: '',
                customNeighborhood: '',
              })
            }}
          >
            {AFRICAN_MARKET_GROUPS.map((group) => (
              <optgroup key={group.key} label={group.label}>
                {AFRICAN_MARKETS.filter((item) => item.region === group.key).map((item) => (
                  <option key={item.country} value={item.country}>
                    {item.country}
                  </option>
                ))}
              </optgroup>
            ))}
          </select>
        )}
      </Field>
      {market && (
        <div className="field" role="status">
          <p className="field__label">Monnaie de référence : {currencyLabel(market.currency)}</p>
          <p className="field__hint">
            Devise définie automatiquement selon le pays. Elle ne change pas avec la ville.
          </p>
          {paymentCurrenciesForCountry(value.country).length > 1 && (
            <p className="field__hint">
              En RDC, les paiements en USD seront pris en charge après validation du module de
              conversion. Les comptes et états financiers restent en CDF : aucun taux automatique
              n'est supposé.
            </p>
          )}
        </div>
      )}
      <Field label="Ville">
        {(control) => (
          <select
            {...control}
            className="input"
            name="city"
            value={value.city}
            required
            onChange={(e) => {
              setQuery('')
              change({
                city: e.target.value,
                customCity: '',
                area: '',
                customArea: '',
                neighborhood: '',
                customNeighborhood: '',
              })
            }}
          >
            <option value="">Choisir une ville</option>
            {cities.map((city) => (
              <option key={city} value={city}>
                {city}
              </option>
            ))}
            <option value={OTHER_CITY}>Autre ville / localité</option>
          </select>
        )}
      </Field>
      {value.city === OTHER_CITY && (
        <Field label="Nom de la ville">
          {(control) => (
            <Input
              {...control}
              name="customCity"
              required
              maxLength={120}
              value={value.customCity}
              onChange={(e) =>
                change({
                  customCity: e.target.value,
                  area: '',
                  customArea: '',
                  neighborhood: '',
                  customNeighborhood: '',
                })
              }
            />
          )}
        </Field>
      )}
      <Field label="Arrondissement / commune">
        {(control) => (
          <select
            {...control}
            className="input"
            name="administrativeArea"
            value={value.area}
            required
            disabled={!cityName}
            onChange={(e) => {
              setQuery('')
              change({
                area: e.target.value,
                customArea: '',
                neighborhood: '',
                customNeighborhood: '',
              })
            }}
          >
            <option value="">Choisir un arrondissement / une commune</option>
            {areas.map((area) => (
              <option key={area} value={area}>
                {area}
              </option>
            ))}
            <option value={OTHER_ADMIN_AREA}>Autre arrondissement / commune</option>
          </select>
        )}
      </Field>
      {value.area === OTHER_ADMIN_AREA && (
        <Field label="Nom de l’arrondissement / commune">
          {(control) => (
            <Input
              {...control}
              name="customArea"
              required
              maxLength={120}
              value={value.customArea}
              onChange={(e) =>
                change({
                  customArea: e.target.value,
                  neighborhood: '',
                  customNeighborhood: '',
                })
              }
            />
          )}
        </Field>
      )}
      {!!areaName && quartiers.length > 0 && (
        <Field
          label="Rechercher un quartier"
          hint="Filtre les quartiers proposés pour cet arrondissement."
        >
          {(control) => (
            <Input
              {...control}
              type="search"
              name="neighborhoodSearch"
              placeholder="Tapez quelques lettres…"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
          )}
        </Field>
      )}
      <Field label="Quartier">
        {(control) => (
          <select
            {...control}
            className="input"
            name="neighborhood"
            value={value.neighborhood}
            required
            disabled={!areaName}
            onChange={(e) => change({ neighborhood: e.target.value, customNeighborhood: '' })}
          >
            <option value="">Choisir un quartier</option>
            {quartiers
              .filter((name) => name === value.neighborhood || visibleQuartiers.includes(name))
              .map((name) => (
                <option key={name} value={name}>
                  {name}
                </option>
              ))}
            <option value={OTHER_NEIGHBORHOOD}>Autre quartier (saisie libre)</option>
          </select>
        )}
      </Field>
      {value.neighborhood === OTHER_NEIGHBORHOOD && (
        <Field label="Nom de votre quartier">
          {(control) => (
            <Input
              {...control}
              name="customNeighborhood"
              required
              maxLength={120}
              placeholder="Ex. votre quartier ou secteur exact"
              value={value.customNeighborhood}
              onChange={(e) => change({ customNeighborhood: e.target.value })}
            />
          )}
        </Field>
      )}
      <Field
        label="Adresse physique de l’établissement"
        hint="Obligatoire : avenue/rue, numéro s’il existe, ou repère précis. Indiquez l’adresse de votre activité, pas nécessairement votre domicile."
      >
        {(control) => (
          <Input
            {...control}
            name="streetAddress"
            autoComplete="street-address"
            required
            minLength={10}
            maxLength={240}
            placeholder="Ex. avenue de la Paix, près du marché, entrée côté pharmacie"
            value={value.streetAddress}
            onChange={(e) => change({ streetAddress: e.target.value })}
          />
        )}
      </Field>
    </>
  )
}
