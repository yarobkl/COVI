import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { useState } from 'react'
import { afterEach, describe, expect, it } from 'vitest'
import { OTHER_CITY } from '../../lib/centralAfricaLocations'
import { OTHER_NEIGHBORHOOD } from '../../lib/neighborhoods'
import { CentralAfricaLocationFields } from './CentralAfricaLocationFields'

afterEach(cleanup)

function FormWithNeighborhood() {
  const [country, setCountry] = useState('République du Congo')
  const [city, setCity] = useState('')
  const [customCity, setCustomCity] = useState('')
  const [neighborhood, setNeighborhood] = useState('')
  const [customNeighborhood, setCustomNeighborhood] = useState('')

  return (
    <form>
      <CentralAfricaLocationFields
        country={country}
        city={city}
        customCity={customCity}
        neighborhood={neighborhood}
        customNeighborhood={customNeighborhood}
        requireCity
        requireNeighborhood
        onCountryChange={(value) => {
          setCountry(value)
          setCity('')
          setCustomCity('')
          setNeighborhood('')
          setCustomNeighborhood('')
        }}
        onCityChange={(value) => {
          setCity(value)
          setCustomCity('')
          setNeighborhood('')
          setCustomNeighborhood('')
        }}
        onCustomCityChange={(value) => {
          setCustomCity(value)
          setNeighborhood('')
          setCustomNeighborhood('')
        }}
        onNeighborhoodChange={(value) => {
          setNeighborhood(value)
          setCustomNeighborhood('')
        }}
        onCustomNeighborhoodChange={setCustomNeighborhood}
      />
    </form>
  )
}

describe('quartiers at COVI signup', () => {
  it('requires a neighborhood and offers Brazzaville selections when the city is chosen', () => {
    render(<FormWithNeighborhood />)
    const city = screen.getByRole('combobox', { name: 'Ville' })
    const neighborhood = screen.getByRole('combobox', { name: 'Quartier / secteur' }) as HTMLSelectElement
    expect(neighborhood.disabled).toBe(true)
    expect(neighborhood.required).toBe(true)
    fireEvent.change(city, { target: { value: 'Brazzaville' } })
    expect(neighborhood.disabled).toBe(false)
    expect(screen.getByRole('option', { name: 'Poto-Poto' })).toBeTruthy()
    expect(screen.getByRole('option', { name: 'Moungali' })).toBeTruthy()
    fireEvent.change(neighborhood, { target: { value: 'Poto-Poto' } })
    expect(neighborhood.value).toBe('Poto-Poto')
  })

  it('removes the old quartiers when switching city, and allows unknown neighborhoods', () => {
    render(<FormWithNeighborhood />)
    const city = screen.getByRole('combobox', { name: 'Ville' })
    const neighborhood = screen.getByRole('combobox', { name: 'Quartier / secteur' }) as HTMLSelectElement
    fireEvent.change(city, { target: { value: 'Brazzaville' } })
    fireEvent.change(neighborhood, { target: { value: 'Poto-Poto' } })
    fireEvent.change(city, { target: { value: 'Dolisie' } })
    expect(neighborhood.value).toBe('')
    expect(screen.queryByRole('option', { name: 'Poto-Poto' })).toBeNull()
    fireEvent.change(neighborhood, { target: { value: OTHER_NEIGHBORHOOD } })
    const input = screen.getByRole('textbox', { name: 'Nom de mon quartier / secteur' }) as HTMLInputElement
    fireEvent.change(input, { target: { value: 'Mon quartier' } })
    expect(input.value).toBe('Mon quartier')
  })

  it('lets custom cities select a quarter without a pre-existing list', () => {
    render(<FormWithNeighborhood />)
    fireEvent.change(screen.getByRole('combobox', { name: 'Ville' }), { target: { value: OTHER_CITY } })
    fireEvent.change(screen.getByRole('textbox', { name: 'Ma ville ou localité' }), {
      target: { value: 'Ngo' },
    })
    const neighborhood = screen.getByRole('combobox', { name: 'Quartier / secteur' }) as HTMLSelectElement
    expect(neighborhood.disabled).toBe(false)
    expect(screen.getByRole('option', { name: 'Mon quartier n’apparaît pas' })).toBeTruthy()
  })
})
