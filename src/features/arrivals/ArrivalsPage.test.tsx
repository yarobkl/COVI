import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { localDay } from '../../lib/dates'
import {
  arrivalProfitability,
  createArrival,
  listArrivals,
  updateArrival,
  type ArrivalProfit,
} from '../../lib/operations'
import type { Arrival } from '../../lib/types'
import { ArrivalsPage } from './ArrivalsPage'

vi.mock('../../lib/operations', () => ({
  listArrivals: vi.fn(),
  arrivalProfitability: vi.fn(),
  createArrival: vi.fn(),
  updateArrival: vi.fn(),
}))
vi.mock('../../lib/covi', () => ({ addProduct: vi.fn() }))

const arrival = (id: string, code: string, extra: Partial<Arrival>): Arrival =>
  ({
    id,
    shop_id: 'shop-1',
    code,
    kind: 'supplier_order',
    origin_country: null,
    supplier_name: null,
    order_date: null,
    received_date: null,
    merchandise_cost: 0,
    transport_cost: 0,
    customs_cost: 0,
    global_cost: 0,
    status: 'received',
    is_test: false,
    created_at: '2026-10-01T00:00:00Z',
    updated_at: '2026-10-01T00:00:00Z',
    ...extra,
  }) as Arrival

const rows = [
  arrival('bal', 'BAL-003', {
    kind: 'balloon',
    global_cost: 250000,
    received_date: '2026-10-02',
  }),
  arrival('ind', 'IND-002', { origin_country: 'Inde', global_cost: 360000 }),
  arrival('cmd', 'CMD-0412', {
    origin_country: 'Chine',
    status: 'in_transit',
    global_cost: 380000,
    order_date: '2026-09-28',
  }),
]
const profit = (id: string, cost: number, revenue: number, sold: number, remaining: number) =>
  ({
    id,
    cost,
    revenue,
    sold,
    remaining,
    productCount: sold + remaining,
    products: [],
  }) as unknown as ArrivalProfit

beforeEach(() => {
  vi.mocked(listArrivals).mockResolvedValue(rows)
  vi.mocked(arrivalProfitability).mockResolvedValue([
    profit('bal', 250000, 186000, 31, 19),
    profit('ind', 360000, 700000, 60, 5),
    profit('cmd', 380000, 0, 0, 0),
  ])
})
afterEach(() => {
  cleanup()
  vi.clearAllMocks()
})

const nbsp = String.fromCharCode(0xa0)

describe('ArrivalsPage', () => {
  it('stamps each arrival and says what it brought back', async () => {
    render(<ArrivalsPage shopId="shop-1" />)
    expect(await screen.findByText('Ballon BAL-003')).toBeTruthy()
    expect(screen.getByText('Ouvert')).toBeTruthy()
    expect(screen.getByText('Rentabilisé')).toBeTruthy()
    expect(screen.getByText('En route')).toBeTruthy()
    expect(screen.getByText('31 vendues · 19 restent', { exact: false })).toBeTruthy()
    expect(
      screen.getByRole('img', {
        name: `186${nbsp}000${nbsp}FCFA récupérés sur 250${nbsp}000${nbsp}FCFA, soit 74${nbsp}%`,
      }),
    ).toBeTruthy()
    expect(document.body.textContent).toContain(`Encore 64${nbsp}000${nbsp}FCFA à récupérer.`)
    expect(document.body.textContent).toContain(`A rapporté 340${nbsp}000${nbsp}FCFA.`)
  })

  it('shows only the bales under « Ballons »', async () => {
    render(<ArrivalsPage shopId="shop-1" kind="balloon" />)
    expect(await screen.findByText('Ballon BAL-003')).toBeTruthy()
    expect(screen.queryByText('Commande CMD-0412')).toBeNull()
    expect(screen.getByRole('heading', { level: 1 }).textContent).toBe('Ballons')
  })

  it('asks before a step, then dates the reception with the local day', async () => {
    vi.mocked(updateArrival).mockResolvedValue({ ...rows[2], status: 'received' })
    render(<ArrivalsPage shopId="shop-1" />)
    fireEvent.click(await screen.findByText('C’est arrivé'))
    expect(screen.getByText('Vous avez reçu CMD-0412 ?')).toBeTruthy()
    fireEvent.click(screen.getByText('Confirmer la réception'))
    await waitFor(() =>
      expect(updateArrival).toHaveBeenCalledWith('shop-1', 'cmd', {
        status: 'received',
        received_date: localDay(new Date()),
      }),
    )
    expect(
      await screen.findByText('CMD-0412 est arrivé. Mettez maintenant les pièces en stock.'),
    ).toBeTruthy()
  })

  it('creates a bale already received, with the next readable code', async () => {
    vi.mocked(createArrival).mockImplementation(async (_shop, input) =>
      arrival('new', input.code, { ...input, kind: 'balloon' } as Partial<Arrival>),
    )
    render(<ArrivalsPage shopId="shop-1" kind="balloon" />)
    await screen.findByText('Ballon BAL-003')
    fireEvent.click(screen.getByText('Nouveau ballon'))
    expect((screen.getByLabelText('Je l’ai déjà reçu') as HTMLInputElement).checked).toBe(true)
    fireEvent.change(screen.getByLabelText('Prix payé pour le ballon (FCFA)'), {
      target: { value: '180 000' },
    })
    fireEvent.click(screen.getByText('Enregistrer le ballon'))
    await waitFor(() => expect(createArrival).toHaveBeenCalled())
    expect(vi.mocked(createArrival).mock.calls[0][1]).toMatchObject({
      code: 'BAL-004',
      kind: 'balloon',
      global_cost: 180000,
      status: 'received',
      order_date: null,
      received_date: localDay(new Date()),
    })
    expect(
      await screen.findByText('BAL-004 noté. Ajoutez ses pièces à mesure que vous déballez.'),
    ).toBeTruthy()
  })

  it('offers to retry when the arrivals do not load', async () => {
    vi.mocked(listArrivals).mockRejectedValueOnce(new Error('Failed to fetch'))
    render(<ArrivalsPage shopId="shop-1" />)
    expect(
      await screen.findByText('Les arrivages ne s’affichent pas : pas de réseau.'),
    ).toBeTruthy()
    fireEvent.click(screen.getByText('Réessayer'))
    expect(await screen.findByText('Ballon BAL-003')).toBeTruthy()
  })
})
