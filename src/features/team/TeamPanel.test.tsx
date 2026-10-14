import { act, cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { supabase } from '../../lib/supabase'
import { TeamPanel } from './TeamPanel'

vi.mock('../../lib/supabase', () => ({ supabase: { rpc: vi.fn() } }))
const rpc = vi.mocked(supabase.rpc)

const awa = {
  id: 'm-awa',
  user_id: 'u-awa',
  display_name: 'Awa',
  role: 'cashier',
  active: true,
  can_view_shop_sales: false,
  max_discount_pct: 10,
  created_at: '',
  updated_at: 'v1',
  deactivated_at: null,
  pin_set: true,
  pin_must_change: false,
  pin_locked_until: null,
}

function serve(extra: Record<string, unknown> = {}) {
  rpc.mockImplementation(((name: string) => {
    const table: Record<string, unknown> = {
      list_shop_members: [awa],
      list_member_invites: [],
      create_member_invite: {
        invite_id: 'i-1',
        code: 'ABCD-EFGH-JKMN',
        display_name: 'Bema',
        expires_at: '2026-10-16T10:00:00Z',
        can_view_shop_sales: false,
        max_discount_pct: 5,
      },
      owner_reset_member_pin: { id: 'm-awa', pin_set: false, pin_must_change: true },
      set_member_active: { id: 'm-awa', active: false },
      set_member_permissions: {},
      ...extra,
    }
    return Promise.resolve({ data: table[name] ?? null, error: null })
  }) as never)
}

afterEach(() => {
  cleanup()
  rpc.mockReset()
})

describe('TeamPanel « Équipe » (owner)', () => {
  it('lists the cashiers with their PIN state, never the PIN', async () => {
    serve()
    await act(async () => {
      render(<TeamPanel shopId="shop-1" shopName="Chez Mama Grâce" />)
    })
    const list = screen.getByRole('list', { name: 'Caissiers' })
    expect(within(list).getByText('Awa')).toBeTruthy()
    expect(within(list).getByText(/Actif · Code PIN choisi/)).toBeTruthy()
  })

  it('creates an invite: the code is shown once, with copy and WhatsApp', async () => {
    serve()
    await act(async () => {
      render(<TeamPanel shopId="shop-1" shopName="Chez Mama Grâce" />)
    })
    fireEvent.change(screen.getByLabelText('Prénom du caissier'), { target: { value: 'Bema' } })
    fireEvent.change(screen.getByLabelText(/Remise maximale autorisée/), {
      target: { value: '5' },
    })
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'Créer un code d’invitation' }))
    })
    expect(rpc).toHaveBeenCalledWith('create_member_invite', {
      p_shop_id: 'shop-1',
      p_display_name: 'Bema',
      p_can_view_shop_sales: false,
      p_max_discount_pct: 5,
    })
    expect(screen.getByText('ABCD-EFGH-JKMN')).toBeTruthy()
    const whatsapp = screen.getByRole('link', { name: 'Envoyer par WhatsApp' })
    expect(whatsapp.getAttribute('href')).toMatch(/^https:\/\/wa\.me\/\?text=.*ABCD-EFGH-JKMN/)
    expect(screen.getByRole('button', { name: 'Copier le message' })).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'J’ai noté le code' }))
    expect(screen.queryByText('ABCD-EFGH-JKMN')).toBeNull()
  })

  it('offers a discount dropdown limited to 0 through 100 %', async () => {
    serve()
    await act(async () => {
      render(<TeamPanel shopId="shop-1" shopName="Boutique" />)
    })
    const discount = screen.getByLabelText(/Remise maximale autorisée/) as HTMLSelectElement
    expect(discount.tagName).toBe('SELECT')
    const values = Array.from(discount.options).map((option) => option.value)
    expect(values).toContain('0')
    expect(values).toContain('100')
    expect(values).not.toContain('150')
    fireEvent.change(screen.getByLabelText('Prénom du caissier'), { target: { value: 'Bema' } })
    fireEvent.change(discount, { target: { value: '100' } })
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'Créer un code d’invitation' }))
    })
    expect(rpc).toHaveBeenCalledWith(
      'create_member_invite',
      expect.objectContaining({ p_max_discount_pct: 100 }),
    )
  })

  it('resets a PIN after confirmation', async () => {
    serve()
    await act(async () => {
      render(<TeamPanel shopId="shop-1" shopName="Boutique" />)
    })
    fireEvent.click(screen.getByRole('button', { name: 'Réinitialiser le code PIN' }))
    expect(screen.getByText(/Vous ne le verrez pas/)).toBeTruthy()
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'Réinitialiser' }))
    })
    expect(rpc).toHaveBeenCalledWith('owner_reset_member_pin', { p_member_id: 'm-awa' })
  })

  it('changes the discount and the « voit toutes les ventes » right, and deactivates', async () => {
    serve()
    await act(async () => {
      render(<TeamPanel shopId="shop-1" shopName="Boutique" />)
    })
    fireEvent.change(screen.getByLabelText('Remise maximale (%)'), { target: { value: '15' } })
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'Enregistrer la remise' }))
    })
    expect(rpc).toHaveBeenCalledWith('set_member_permissions', {
      p_member_id: 'm-awa',
      p_can_view_shop_sales: false,
      p_max_discount_pct: 15,
    })
    await act(async () => {
      fireEvent.click(screen.getByLabelText('Voit toutes les ventes'))
    })
    expect(rpc).toHaveBeenCalledWith('set_member_permissions', {
      p_member_id: 'm-awa',
      p_can_view_shop_sales: true,
      p_max_discount_pct: 10,
    })
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'Désactiver' }))
    })
    expect(rpc).toHaveBeenCalledWith('set_member_active', { p_member_id: 'm-awa', p_active: false })
  })
})
