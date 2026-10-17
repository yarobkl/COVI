import { afterEach, describe, expect, it } from 'vitest'
import { cleanup, render, screen } from '@testing-library/react'
import { SaleDone } from './SaleDone'
import type { SoldSale } from './SaleForm'

const sale: SoldSale = {
  product: {
    name: 'Robe',
    initial_sale_price: 3500,
    quantity_on_hand: 4,
    is_unique_piece: false,
  } as SoldSale['product'],
  quantity: 1,
  price: 3500,
  payment: 'Mobile Money',
  received: null,
  offline: false,
  operationId: '489a49a2-0652-4ee1-be84-61e9173b9e38',
  at: new Date('2026-10-17T08:15:00.000Z'),
}

afterEach(cleanup)

describe('current notebook sale: PDF invoice availability', () => {
  it('offers share and download only after server-recorded sale', () => {
    render(<SaleDone sale={sale} shopName="YARO BOUTIQUE" today={null} onNext={() => {}} />)
    expect(screen.getByRole('button', { name: 'Partager la facture PDF' })).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Télécharger le PDF' })).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Vente suivante' })).toBeTruthy()
  })

  it('never issues a paid PDF for an offline sale awaiting server sync', () => {
    render(<SaleDone sale={{ ...sale, offline: true }} shopName="YARO BOUTIQUE"
      today={null} onNext={() => {}} />)
    expect(screen.queryByRole('button', { name: 'Partager la facture PDF' })).toBeNull()
    expect(screen.getByText(/attente de synchronisation/)).toBeTruthy()
  })

  it('does not invent a receipt reference when an old sale lacks its operation ID', () => {
    render(<SaleDone sale={{ ...sale, operationId: undefined }} shopName="YARO BOUTIQUE"
      today={null} onNext={() => {}} />)
    expect(screen.queryByRole('button', { name: 'Partager la facture PDF' })).toBeNull()
  })
})
