import { Field, Input } from '../../components/ui'
import { CENTRAL_AFRICA, listedAfricanCities, OTHER_CITY } from '../../lib/centralAfricaLocations'
import { neighborhoodSuggestions, OTHER_NEIGHBORHOOD } from '../../lib/neighborhoods'

/** Shared country -> city controls for both account opening and existing shop settings.
 * No data is saved until the enclosing form is submitted.
 */
export function CentralAfricaLocationFields({
  country,
  city,
  customCity,
  onCountryChange,
  onCityChange,
  onCustomCityChange,
  requireCity = false,
  neighborhood,
  customNeighborhood,
  onNeighborhoodChange,
  onCustomNeighborhoodChange,
  requireNeighborhood = false,
}: {
  country: string
  city: string
  customCity: string
  onCountryChange: (country: string) => void
  onCityChange: (city: string) => void
  onCustomCityChange: (city: string) => void
  requireCity?: boolean
  neighborhood?: string
  customNeighborhood?: string
  onNeighborhoodChange?: (value: string) => void
  onCustomNeighborhoodChange?: (value: string) => void
  requireNeighborhood?: boolean
}) {
  const cities = listedAfricanCities(country)
  const legacyCountry = country !== '' && !CENTRAL_AFRICA.some((entry) => entry.country === country)
  const chosenCity = city === OTHER_CITY ? customCity : city
  const neighborhoods = neighborhoodSuggestions(country, chosenCity)
  return (
    <>
      <Field label="Pays">
        {(control) => (
          <select
            {...control}
            className="input"
            name="country"
            value={country}
            required
            onChange={(event) => onCountryChange(event.target.value)}
          >
            {legacyCountry && <option value={country}>{country}</option>}
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
            className="input"
            name="city"
            value={city}
            required={requireCity}
            onChange={(event) => onCityChange(event.target.value)}
          >
            <option value="">Choisir une ville</option>
            {cities.map((value) => (
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
              onChange={(event) => onCustomCityChange(event.target.value)}
            />
          )}
        </Field>
      )}
      {onNeighborhoodChange && onCustomNeighborhoodChange && (
        <>
          <Field
            label="Quartier / secteur"
            hint="Choisissez la zone où se trouve la boutique, pas votre domicile."
          >
            {(control) => (
              <select
                {...control}
                className="input"
                name="neighborhood"
                value={neighborhood ?? ''}
                required={requireNeighborhood}
                disabled={!chosenCity?.trim()}
                onChange={(event) => onNeighborhoodChange(event.target.value)}
              >
                <option value="">Choisir un quartier ou secteur</option>
                {neighborhoods.map((value) => (
                  <option key={value} value={value}>
                    {value}
                  </option>
                ))}
                <option value={OTHER_NEIGHBORHOOD}>Mon quartier n’apparaît pas</option>
              </select>
            )}
          </Field>
          {neighborhood === OTHER_NEIGHBORHOOD && (
            <Field label="Nom de mon quartier / secteur">
              {(control) => (
                <Input
                  {...control}
                  name="customNeighborhood"
                  required
                  maxLength={120}
                  placeholder="Saisissez votre quartier"
                  value={customNeighborhood ?? ''}
                  onChange={(event) => onCustomNeighborhoodChange(event.target.value)}
                />
              )}
            </Field>
          )}
        </>
      )}
    </>
  )
}
