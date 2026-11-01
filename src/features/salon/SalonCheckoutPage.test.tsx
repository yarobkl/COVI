import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { SalonCatalog, Ticket, TicketBrief } from '../../lib/salon'
import { SalonCheckoutPage } from './SalonCheckoutPage'

const api = {
  recentTickets: vi.fn(),
  ticket: vi.fn(),
  pay: vi.fn(),
}
vi.mock('../../lib/salon', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../../lib/salon')>()
  return {
    ...actual,
    salonApi: {
      ...actual.salonApi,
      recentTickets: (...a: unknown[]) => api.recentTickets(...a),
      ticket: (...a: unknown[]) => api.ticket(...a),
      pay: (...a: unknown[]) => api.pay(...a),
      catalog: () => Promise.resolve(catalog),
      supplies: () => Promise.resolve([]),
      settings: () => Promise.resolve({ settings: { time_zone: 'Africa/Brazzaville' } }),
    },
  }
})

const catalog: SalonCatalog = {
  services: [
    {
      id: 'svc-1',
      name: 'Tresses',
      category: null,
      description: null,
      price_xaf: 15000,
      duration_minutes: 120,
      direct_cost_xaf: null,
      active: true,
      employee_ids: [],
    },
  ],
  staff: [
    {
      employee_id: 'emp-1',
      full_name: 'Paul',
      job_title: 'Coiffeur',
      active: true,
      agenda_color: '#17408b',
    },
  ],
}

const ticket: Ticket = {
  id: 't-1',
  status: 'open',
  appointment_id: null,
  client_id: null,
  client_name: 'Mireille',
  subtotal_xaf: 15000,
  discount_xaf: 0,
  total_xaf: 15000,
  paid_xaf: 0,
  refunded_xaf: 0,
  opened_at: '2026-10-24T09:00:00Z',
  paid_at: null,
  lines: [
    {
      id: 'l-1',
      kind: 'service',
      service_id: 'svc-1',
      supply_id: null,
      employee_id: 'emp-1',
      employee_name: 'Paul',
      label: 'Tresses',
      quantity: 1,
      list_price_xaf: 15000,
      unit_price_xaf: 15000,
      line_total_xaf: 15000,
      net_xaf: null,
      refunded: false,
    },
  ],
  payments: [],
}
const paid: Ticket = {
  ...ticket,
  status: 'paid',
  paid_xaf: 15000,
  paid_at: '2026-10-24T10:00:00Z',
  payments: [
    {
      id: 'p-1',
      kind: 'payment',
      method: 'cash',
      amount_xaf: 15000,
      reference: null,
      confirmation: 'manual',
      recorded_at: '2026-10-24T10:00:00Z',
    },
  ],
}
const brief = (t: Ticket): TicketBrief => ({
  id: t.id,
  status: t.status,
  client_name: t.client_name,
  total_xaf: t.total_xaf,
  paid_xaf: t.paid_xaf,
  refunded_xaf: t.refunded_xaf,
  opened_at: t.opened_at,
  paid_at: t.paid_at,
  appointment_id: t.appointment_id,
})

afterEach(() => {
  cleanup()
  Object.values(api).forEach((f) => f.mockReset())
})

describe('caisse du salon', () => {
  it('met à jour les ventes du jour dès le paiement, sans attendre la fermeture de la note', async () => {
    api.recentTickets.mockResolvedValueOnce([brief(ticket)]).mockResolvedValue([brief(paid)])
    api.ticket.mockResolvedValue(ticket)
    api.pay.mockResolvedValue(paid)
    render(<SalonCheckoutPage shopId="shop-1" role="cashier" />)
    const open = await screen.findByRole('button', { name: 'Mireille' })
    await act(async () => {
      fireEvent.click(open)
    })
    const encaisser = await screen.findByRole('button', { name: /Encaisser 15/ })
    await act(async () => {
      fireEvent.click(encaisser)
    })
    expect(api.pay).toHaveBeenCalledTimes(1)
    expect(api.recentTickets).toHaveBeenCalledTimes(2)
    expect(screen.getByText('Paiement enregistré.')).toBeTruthy()
    expect(screen.getAllByText('Payée').length).toBeGreaterThan(0)
  })
})
