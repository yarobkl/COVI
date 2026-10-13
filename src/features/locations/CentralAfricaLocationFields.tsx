import { Field, Input } from '../../components/ui'
import { CENTRAL_AFRICA, listedAfricanCities, OTHER_CITY } from '../../lib/centralAfricaLocations'

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
}: {
  country: string
  city: string
  customCity: string
  onCountryChange: (country: string) => void
  onCityChange: (city: string) => void
  onCustomCityChange: (city: string) => void
  requireCity?: boolean
}) {
  const cities = listedAfricanCities(country)
  const legacyCountry = country !== '' && !CENTRAL_AFRICA.some((entry) => entry.country === country)
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
    </>
  )
}
