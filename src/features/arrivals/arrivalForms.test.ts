import { describe, expect, it } from 'vitest'
import {
  arrivalSaveError,
  balloonFromValues,
  isCodeTaken,
  orderFromValues,
  orderTotal,
  type OrderValues,
} from './arrivalForms'

const order: OrderValues = {
  country: 'Chine',
  supplier: 'Textiles Wang',
  orderDate: '2026-10-01',
  goods: '300 000',
  transport: '50000',
  customs: '20 000',
}

describe('orderFromValues', () => {
  it('sums goods, transport and customs into an order still to place', () => {
    const { input, errors } = orderFromValues(order, 'CMD-005', '2026-10-08')
    expect(errors).toBeNull()
    expect(input).toEqual({
      code: 'CMD-005',
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
    expect(orderTotal(order)).toBe(370000)
  })

  it('says what is missing, and refuses an order date not yet reached', () => {
    const { errors } = orderFromValues(
      {
        country: ' ',
        supplier: '',
        orderDate: '2026-10-20',
        goods: '',
        transport: '',
        customs: '',
      },
      'CMD-005',
      '2026-10-08',
    )
    expect(Object.keys(errors ?? {})).toEqual(['country', 'supplier', 'goods', 'orderDate'])
    expect(errors?.goods).toBe('Indiquez le prix de la marchandise, en FCFA.')
  })
})

describe('balloonFromValues', () => {
  it('a bale bought on the spot is saved received today, with no order date', () => {
    const { input } = balloonFromValues(
      { place: 'Brazzaville', price: '250 000', received: true },
      'BAL-004',
      '2026-10-08',
    )
    // The database accepts it: status in arrivals_status_check, and the dates check passes when
    // order_date is null.
    expect(input).toMatchObject({
      code: 'BAL-004',
      kind: 'balloon',
      origin_country: 'Brazzaville',
      supplier_name: null,
      global_cost: 250000,
      merchandise_cost: 0,
      order_date: null,
      received_date: '2026-10-08',
      status: 'received',
    })
  })

  it('a bale not received yet is paid and waits; the price is required', () => {
    expect(
      balloonFromValues({ place: '', price: '90000', received: false }, 'BAL-004', '2026-10-08')
        .input,
    ).toMatchObject({ origin_country: null, status: 'ordered', received_date: null })
    expect(
      balloonFromValues({ place: '', price: '', received: true }, 'BAL-004', '2026-10-08').errors,
    ).toEqual({ price: 'Indiquez le prix payé pour le ballon.' })
  })
})

describe('arrival errors', () => {
  it('recognises a code already taken', () => {
    expect(isCodeTaken({ code: '23505', message: 'duplicate key' })).toBe(true)
    expect(isCodeTaken(new Error('boom'))).toBe(false)
  })

  it('never shows the database message', () => {
    expect(
      arrivalSaveError({ message: 'new row violates check constraint "arrivals_dates_check"' }),
    ).toMatch(/avant la commande/)
    expect(arrivalSaveError(new Error('permission denied for table arrivals'))).toBe(
      'Ça n’a pas marché. Vérifiez le réseau puis réessayez.',
    )
  })
})
