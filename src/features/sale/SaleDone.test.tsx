import { afterEach, describe, expect, it } from 'vitest'
import { cleanup, render, screen } from '@testing-library/react'
import { SaleDone } from './SaleDone'
import type { SoldSale } from './cart'

const example: SoldSale = {
  lines: [{
    product: {
      id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      name: 'Robe',
      quantity_on_hand: 4,
      initial_sale_price: 3500,
      is_unique_piece: false,
    } as SoldSale['lines'][number]['product'],
    quantity: 1,
    price: 3500,
  }],
  payment: 'Mobile Money',
  received: null,
  offline: false,
  sellerName: 'Rodrin',
  saleId: '489a49a2-0652-4ee1-be84-61e9173b9e38',
  at: new Date('2026-10-17T08:15:00Z'),
}

afterEach(cleanup)

describe('the real production checkout: PDF invoice sharing', () => {
  it('shows native share and download after a confirmed multi-cashier sale', () => {
    render(<SaleDone sale={example} shopName="YARO BOUTIQUE" today={null} onNext={() => {}} />)
    expect(screen.getByText('Caissier : Rodrin')).toBeTruthy()
    expect(screen.getByText(/COVI-489A49A2/)).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Partager la facture PDF' })).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Télécharger le PDF' })).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Vente suivante' })).toBeTruthy()
  })

  it('also supports multiple lines from the current cart', () => {
    const sale: SoldSale = {
      ...example,
      lines: [...example.lines, {
        product: {
          id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          name: 'Chemise',
          quantity_on_hand: 3,
          initial_sale_price: 3000,
          is_unique_piece: false,
        } as SoldSale['lines'][number]['product'],
        quantity: 2,
        price: 2500,
      }],
    }
    render(<SaleDone sale={sale} shopName="YARO BOUTIQUE" today={null} onNext={() => {}} />)
    expect(screen.getByRole('button', { name: 'Partager la facture PDF' })).toBeTruthy()
    expect(screen.getByText('Caissier : Rodrin')).toBeTruthy()
  })

  it('never presents an unpaid queued sale as a downloadable PAID invoice', () => {
    render(<SaleDone sale={{ ...example, offline: true, saleId: undefined }}
      shopName="YARO BOUTIQUE" today={null} onNext={() => {}} />)
    expect(screen.queryByRole('button', { name: 'Partager la facture PDF' })).toBeNull()
    expect(screen.getByText(/lorsque la vente aura été enregistrée/)).toBeTruthy()
  })

  it('does not invent a COVI reference for older sales without a confirmed sale ID', () => {
    render(<SaleDone sale={{ ...example, saleId: undefined }}
      shopName="YARO BOUTIQUE" today={null} onNext={() => {}} />)
    expect(screen.queryByRole('button', { name: 'Partager la facture PDF' })).toBeNull()
  })
})
