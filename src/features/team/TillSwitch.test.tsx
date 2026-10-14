import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { supabase } from '../../lib/supabase'
import { clearTillSession, getTillSession } from '../../lib/tillSession'
import { TillSwitch } from './TillSwitch'

vi.mock('../../lib/supabase', () => ({ supabase: { rpc: vi.fn() } }))
const rpc = vi.mocked(supabase.rpc)
const TOKEN = 'b'.repeat(64)

const member = (over: Record<string, unknown>) => ({
  id: 'm-awa',
  user_id: 'u-awa',
  display_name: 'Awa',
  role: 'cashier',
  active: true,
  can_view_shop_sales: false,
  max_discount_pct: 10,
  created_at: '',
  updated_at: '',
  deactivated_at: null,
  pin_set: true,
  pin_must_change: false,
  pin_locked_until: null,
  ...over,
})

function serve(open: unknown) {
  rpc.mockImplementation(((name: string) => {
    if (name === 'list_shop_members')
      return Promise.resolve({
        data: [
          member({}),
          member({ id: 'm-bema', display_name: 'Bema', pin_set: false }),
          member({ id: 'm-off', display_name: 'Ancien', active: false }),
        ],
        error: null,
      })
    if (name === 'open_till_session') return Promise.resolve({ data: open, error: null })
    if (name === 'close_till_session') return Promise.resolve({ data: true, error: null })
    return Promise.resolve({ data: null, error: { message: 'unexpected ' + name } })
  }) as never)
}

async function pickAwaAndType(pin: string) {
  await act(async () => {
    fireEvent.click(screen.getByRole('button', { name: 'Changer' }))
  })
  fireEvent.click(await screen.findByRole('button', { name: 'Awa' }))
  for (const d of pin) fireEvent.click(screen.getByRole('button', { name: d }))
  await act(async () => {
    fireEvent.click(screen.getByRole('button', { name: 'Ouvrir sa caisse' }))
  })
}

beforeEach(() => {
  sessionStorage.clear()
  localStorage.clear()
  clearTillSession()
})
afterEach(() => {
  cleanup()
  rpc.mockReset()
})

describe('TillSwitch « Changer de caissier » (owner’s shared device)', () => {
  it('lists active cashiers; one without PIN cannot be picked', async () => {
    serve(null)
    render(<TillSwitch shopId="shop-1" />)
    expect(screen.getByText('Vous (responsable)')).toBeTruthy()
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'Changer' }))
    })
    expect(screen.getByRole('button', { name: 'Awa' })).toBeTruthy()
    expect(
      (screen.getByRole('button', { name: 'Bema (code PIN à choisir)' }) as HTMLButtonElement)
        .disabled,
    ).toBe(true)
    expect(screen.queryByText('Ancien')).toBeNull()
  })

  it('opens a till session with THEIR PIN, kept out of localStorage', async () => {
    serve({
      status: 'ok',
      token: TOKEN,
      session_id: 's-1',
      expires_at: new Date(Date.now() + 3600_000).toISOString(),
      member_id: 'm-awa',
      display_name: 'Awa',
      max_discount_pct: 10,
    })
    render(<TillSwitch shopId="shop-1" />)
    await pickAwaAndType('4826')
    expect(rpc).toHaveBeenCalledWith('open_till_session', {
      p_shop_id: 'shop-1',
      p_member_id: 'm-awa',
      p_pin: '4826',
    })
    expect(screen.getByText('Awa')).toBeTruthy()
    expect(getTillSession('shop-1')?.token).toBe(TOKEN)
    expect(JSON.stringify({ ...localStorage })).not.toContain(TOKEN)
  })

  it('refuses a wrong PIN and says how many tries are left', async () => {
    serve({ status: 'invalid', attempts_left: 4 })
    render(<TillSwitch shopId="shop-1" />)
    await pickAwaAndType('1111')
    expect(screen.getByText('Code PIN incorrect. Encore 4 essais.')).toBeTruthy()
    expect(getTillSession('shop-1')).toBeNull()
  })

  it('says when the cashier is locked out', async () => {
    serve({ status: 'locked', retry_after: '2026-10-14T10:15:00Z' })
    render(<TillSwitch shopId="shop-1" />)
    await pickAwaAndType('1111')
    expect(screen.getByText('Trop d’essais. Réessayez dans 15 minutes.')).toBeTruthy()
  })

  it('back to the owner closes the session on the server', async () => {
    serve({
      status: 'ok',
      token: TOKEN,
      session_id: 's-1',
      expires_at: new Date(Date.now() + 3600_000).toISOString(),
      member_id: 'm-awa',
      display_name: 'Awa',
      max_discount_pct: 10,
    })
    render(<TillSwitch shopId="shop-1" />)
    await pickAwaAndType('4826')
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'Changer' }))
    })
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'Vous (responsable)' }))
    })
    expect(rpc).toHaveBeenCalledWith('close_till_session', { p_shop_id: 'shop-1', p_token: TOKEN })
    expect(getTillSession('shop-1')).toBeNull()
    expect(sessionStorage.getItem('covi:till-session:v1')).toBeNull()
  })
})
