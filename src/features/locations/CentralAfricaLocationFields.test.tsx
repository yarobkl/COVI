import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { useState } from 'react'
import { afterEach, describe, expect, it } from 'vitest'
import { OTHER_CITY } from '../../lib/centralAfricaLocations'
import { CentralAfricaLocationFields } from './CentralAfricaLocationFields'

afterEach(cleanup)

function Harness({ initialCountry = 'République du Congo' }: { initialCountry?: string }) {
  const [country, setCountry] = useState(initialCountry)
  const [city, setCity] = useState('')
  const [customCity, setCustomCity] = useState('')
  return (
    <form>
      <CentralAfricaLocationFields
        country={country}
        city={city}
        customCity={customCity}
        requireCity
        onCountryChange={(value) => {
          setCountry(value)
          setCity('')
          setCustomCity('')
        }}
        onCityChange={(value) => {
          setCity(value)
          setCustomCity('')
        }}
        onCustomCityChange={setCustomCity}
      />
    </form>
  )
}

describe('country and dependent city controls shared across COVI', () => {
  it('changes cities when country is changed, without carrying over the former city', () => {
    render(<Harness />)
    const country = screen.getByRole('combobox', { name: 'Pays' }) as HTMLSelectElement
    const city = screen.getByRole('combobox', { name: 'Ville' }) as HTMLSelectElement
    expect(country.value).toBe('République du Congo')
    expect(screen.getByRole('option', { name: 'Brazzaville' })).toBeTruthy()
    fireEvent.change(city, { target: { value: 'Brazzaville' } })
    expect(city.value).toBe('Brazzaville')
    fireEvent.change(country, { target: { value: 'Gabon' } })
    expect(city.value).toBe('')
    expect(screen.queryByRole('option', { name: 'Brazzaville' })).toBeNull()
    expect(screen.getByRole('option', { name: 'Libreville' })).toBeTruthy()
  })

  it('shows a free-text fallback for small towns omitted from the list', () => {
    render(<Harness />)
    const city = screen.getByRole('combobox', { name: 'Ville' })
    fireEvent.change(city, { target: { value: OTHER_CITY } })
    const custom = screen.getByRole('textbox', {
      name: 'Ma ville ou localité',
    }) as HTMLInputElement
    fireEvent.change(custom, { target: { value: 'Ngo' } })
    expect(custom.value).toBe('Ngo')
  })

  it('keeps historical country values instead of silently replacing them', () => {
    render(<Harness initialCountry="Autre pays historique" />)
    const country = screen.getByRole('combobox', { name: 'Pays' }) as HTMLSelectElement
    expect(country.value).toBe('Autre pays historique')
    expect(screen.getByRole('option', { name: 'Autre pays historique' })).toBeTruthy()
  })
})
