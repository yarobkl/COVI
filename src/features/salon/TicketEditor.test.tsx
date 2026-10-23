import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { SalonCatalog, Ticket } from '../../lib/salon'
import { TicketEditor } from './TicketEditor'

const pay = vi.fn()
vi.mock('../../lib/salon', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../../lib/salon')>()
  return { ...actual, salonApi: { ...actual.salonApi, pay: (...args: unknown[]) => pay(...args) } }
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

const openTicket: Ticket = {
  id: 't-1',
  status: 'open',
  appointment_id: 'a-1',
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
  ...openTicket,
  status: 'paid',
  paid_xaf: 15000,
  paid_at: '2026-10-24T11:00:00Z',
  payments: [
    {
      id: 'p-1',
      kind: 'payment',
      method: 'mobile_money',
      amount_xaf: 15000,
      reference: 'MP42',
      confirmation: 'manual',
      recorded_at: '2026-10-24T11:00:00Z',
    },
  ],
}

function renderEditor(role: 'owner' | 'cashier') {
  return render(
    <TicketEditor
      shopId="shop-1"
      role={role}
      ticket={openTicket}
      catalog={catalog}
      supplies={[]}
      onClose={() => {}}
      onChanged={() => {}}
    />,
  )
}

afterEach(() => {
  cleanup()
  pay.mockReset()
})

describe('note du salon', () => {
  it('la caisse ne change ni les prix ni les remises', () => {
    renderEditor('cashier')
    expect(screen.queryByText(/Prix final/)).toBeNull()
    expect(screen.queryByText('Remise')).toBeNull()
  })

  it('le propriétaire peut ajuster un prix et faire une remise', () => {
    renderEditor('owner')
    expect(screen.getByText(/Prix final/)).toBeTruthy()
    expect(screen.getByRole('group', { name: 'Remise' })).toBeTruthy()
  })

  it('refuse un encaissement dont les paiements ne font pas le total', () => {
    renderEditor('cashier')
    fireEvent.change(screen.getByLabelText('Montant (FCFA)'), { target: { value: '10000' } })
    const button = screen.getByRole('button', { name: /doit faire/ }) as HTMLButtonElement
    expect(button.disabled).toBe(true)
  })

  it('après une coupure réseau, le nouvel essai réutilise la même clé (jamais deux paiements)', async () => {
    pay.mockRejectedValueOnce(new Error('Failed to fetch')).mockResolvedValueOnce(paid)
    renderEditor('cashier')
    fireEvent.change(screen.getByLabelText('Moyen de paiement'), {
      target: { value: 'mobile_money' },
    })
    expect(screen.getByText(/COVI n’interroge pas l’opérateur/)).toBeTruthy()
    const encaisser = () => screen.getByRole('button', { name: /Encaisser 15/ })
    await act(async () => {
      fireEvent.click(encaisser())
    })
    expect(screen.getByText(/Pas de connexion/)).toBeTruthy()
    await act(async () => {
      fireEvent.click(encaisser())
    })
    expect(pay).toHaveBeenCalledTimes(2)
    expect(pay.mock.calls[0][3]).toBe(pay.mock.calls[1][3])
    expect(pay.mock.calls[1][2]).toEqual([
      { method: 'mobile_money', amount_xaf: 15000, reference: null },
    ])
    expect(screen.getByText('Paiement enregistré.')).toBeTruthy()
    expect(screen.getByText(/confirmé à la caisse/)).toBeTruthy()
  })
})
