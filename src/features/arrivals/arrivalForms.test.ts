import { describe, expect, it } from 'vitest'
import type { Arrival } from '../../lib/types'
import { arrivalFromForm, arrivalProductFromForm } from './arrivalForms'

const form = (fields: Record<string, string>) => {
  const f = new FormData()
  for (const [k, v] of Object.entries(fields)) f.set(k, v)
  return f
}

describe('arrivalFromForm', () => {
  it('sums the costs of a supplier order into a draft', () => {
    const input = arrivalFromForm(
      form({
        country: 'Chine',
        supplier: 'Textiles Wang',
        orderDate: '2026-10-01',
        goods: '300000',
        transport: '50000',
        customs: '20000',
        global: '999',
      }),
      'supplier_order',
    )
    expect(input).toMatchObject({
      kind: 'supplier_order',
      origin_country: 'Chine',
      supplier_name: 'Textiles Wang',
      order_date: '2026-10-01',
      merchandise_cost: 300000,
      transport_cost: 50000,
      customs_cost: 20000,
      global_cost: 370000,
      received_date: null,
      status: 'draft',
    })
    expect(input.code).toMatch(/^CMD-[0-9A-F]{6}$/)
  })

  it('keeps the global cost of a balloon without supplier or order date', () => {
    const input = arrivalFromForm(form({ country: 'France', global: '150000' }), 'balloon')
    expect(input).toMatchObject({
      kind: 'balloon',
      supplier_name: null,
      order_date: null,
      merchandise_cost: 0,
      global_cost: 150000,
    })
    expect(input.code).toMatch(/^BAL-/)
  })
})

describe('arrivalProductFromForm', () => {
  const arrival = { id: 'a1', kind: 'supplier_order', is_test: true } as Arrival

  it('adds a supplier reference with its quantity and test flag', () => {
    expect(
      arrivalProductFromForm(
        form({ name: 'Robe wax', category: 'Robes', price: '18000', quantity: '4' }),
        arrival,
      ),
    ).toMatchObject({
      arrival_id: 'a1',
      is_test: true,
      name: 'Robe wax',
      category: 'Robes',
      initial_sale_price: 18000,
      quantity_on_hand: 4,
      is_unique_piece: false,
      image: null,
    })
  })

  it('records a balloon piece as a unique piece', () => {
    const balloon = { ...arrival, kind: 'balloon', is_test: false } as Arrival
    expect(arrivalProductFromForm(form({ name: 'Pièce', quantity: '3' }), balloon)).toMatchObject({
      quantity_on_hand: 1,
      is_unique_piece: true,
      is_test: false,
    })
  })
})
