import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { useState } from 'react'
import { afterEach, describe, expect, it } from 'vitest'
import { CemacBusinessAddressFields, type BusinessLocation } from './CemacBusinessAddressFields'

afterEach(cleanup)

function Harness() {
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
  return (
    <form>
      <CemacBusinessAddressFields value={location} onChange={setLocation} />
      <output data-testid="address">{JSON.stringify(location)}</output>
    </form>
  )
}

describe('CEMAC business address onboarding', () => {
  it('displays Congo-first CEMAC countries and cascading Brazzaville districts', () => {
    render(<Harness />)
    const country = screen.getByRole('combobox', { name: 'Pays de l’établissement' })
    expect(country.querySelectorAll('option')).toHaveLength(26)
    fireEvent.change(screen.getByRole('combobox', { name: 'Ville' }), {
      target: { value: 'Brazzaville' },
    })
    expect(screen.getByRole('option', { name: 'Moungali' })).toBeTruthy()
    expect(screen.getByRole('option', { name: 'Makélékélé' })).toBeTruthy()
    fireEvent.change(screen.getByRole('combobox', { name: 'Arrondissement / commune' }), {
      target: { value: 'Moungali' },
    })
    fireEvent.change(screen.getByRole('searchbox', { name: 'Rechercher un quartier' }), {
      target: { value: 'Mouk' },
    })
    expect(screen.getByRole('option', { name: 'Moukondo' })).toBeTruthy()
    expect(screen.queryByRole('option', { name: 'Plateau des 15 ans' })).toBeNull()
    fireEvent.change(screen.getByRole('combobox', { name: 'Quartier' }), {
      target: { value: 'Moukondo' },
    })
    fireEvent.change(screen.getByRole('textbox', { name: 'Adresse physique de l’établissement' }), {
      target: { value: 'Avenue de la Paix, près du marché' },
    })
    expect(screen.getByTestId('address').textContent).toContain('Moukondo')
    expect(screen.getByTestId('address').textContent).toContain('Avenue de la Paix')
  })

  it('chooses a country-specific currency and preserves separate CFA zones', () => {
    render(<Harness />)
    expect(screen.getByText(/Franc CFA d’Afrique centrale \(XAF\)/)).toBeTruthy()
    fireEvent.change(screen.getByRole('combobox', { name: 'Pays de l’établissement' }), {
      target: { value: 'Côte d’Ivoire' },
    })
    expect(screen.getByText(/Franc CFA d’Afrique de l’Ouest \(XOF\)/)).toBeTruthy()
    expect(screen.getByRole('option', { name: 'Abidjan' })).toBeTruthy()
    fireEvent.change(screen.getByRole('combobox', { name: 'Pays de l’établissement' }), {
      target: { value: 'République démocratique du Congo' },
    })
    expect(screen.getByText(/Franc congolais \(CDF\)/)).toBeTruthy()
    expect(screen.getByText(/les paiements en USD seront pris en charge/)).toBeTruthy()
    expect(screen.getByRole('option', { name: 'Kinshasa' })).toBeTruthy()
    fireEvent.change(screen.getByRole('combobox', { name: 'Pays de l’établissement' }), {
      target: { value: 'Nigeria' },
    })
    expect(screen.getByText(/Naira nigérian \(NGN\)/)).toBeTruthy()
  })

  it('clears dependent geographic data when the selected CEMAC country changes', () => {
    render(<Harness />)
    fireEvent.change(screen.getByRole('combobox', { name: 'Ville' }), {
      target: { value: 'Brazzaville' },
    })
    fireEvent.change(screen.getByRole('combobox', { name: 'Arrondissement / commune' }), {
      target: { value: 'Moungali' },
    })
    fireEvent.change(screen.getByRole('combobox', { name: 'Pays de l’établissement' }), {
      target: { value: 'Cameroun' },
    })
    expect(screen.getByRole('combobox', { name: 'Ville' })).toHaveProperty('value', '')
    expect(screen.getByRole('combobox', { name: 'Arrondissement / commune' })).toHaveProperty(
      'value',
      '',
    )
    expect(screen.getByRole('option', { name: 'Yaoundé' })).toBeTruthy()
  })

  it('provides truthful manual fallback for towns without a validated list', () => {
    render(<Harness />)
    fireEvent.change(screen.getByRole('combobox', { name: 'Ville' }), {
      target: { value: 'Dolisie' },
    })
    fireEvent.change(screen.getByRole('combobox', { name: 'Arrondissement / commune' }), {
      target: { value: '__other_admin_area__' },
    })
    expect(screen.getByRole('textbox', { name: 'Nom de l’arrondissement / commune' })).toBeTruthy()
    fireEvent.change(screen.getByRole('textbox', { name: 'Nom de l’arrondissement / commune' }), {
      target: { value: 'Quartier central' },
    })
    fireEvent.change(screen.getByRole('combobox', { name: 'Quartier' }), {
      target: { value: '__other_neighborhood__' },
    })
    expect(screen.getByRole('textbox', { name: 'Nom de votre quartier' })).toBeTruthy()
  })
})
