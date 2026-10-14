import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCounterMode, isCounterMode } from '../../lib/counterMode'
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

const opened = {
  status: 'ok',
  token: TOKEN,
  session_id: 's-1',
  expires_at: new Date(Date.now() + 3600_000).toISOString(),
  member_id: 'm-awa',
  user_id: 'u-awa',
  display_name: 'Awa',
  max_discount_pct: 10,
  can_view_shop_sales: false,
}

function serve(open: unknown, ownerPinSet = true) {
  rpc.mockImplementation(((name: string) => {
    if (name === 'owner_pin_status')
      return Promise.resolve({ data: { pin_set: ownerPinSet, locked_until: null }, error: null })
    if (name === 'set_owner_pin') return Promise.resolve({ data: { status: 'ok' }, error: null })
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
    return Promise.resolve({ data: null, error: { message: 'unexpected ' + name } })
  }) as never)
}

const type = (pin: string) => {
  for (const d of pin) fireEvent.click(screen.getByRole('button', { name: d }))
}

async function openDialog() {
  await act(async () => {
    fireEvent.click(screen.getByRole('button', { name: 'Changer' }))
  })
}

async function pickAwaAndType(pin: string) {
  await openDialog()
  fireEvent.click(await screen.findByRole('button', { name: 'Awa' }))
  type(pin)
  await act(async () => {
    fireEvent.click(screen.getByRole('button', { name: 'Ouvrir sa caisse' }))
  })
}

beforeEach(() => {
  sessionStorage.clear()
  localStorage.clear()
  clearTillSession()
  clearCounterMode()
})
afterEach(() => {
  cleanup()
  rpc.mockReset()
})

describe('TillSwitch « Changer de caissier » (owner’s shared device)', () => {
  it('lists active cashiers; one without PIN cannot be picked; no way back without a code', async () => {
    serve(null)
    render(<TillSwitch shopId="shop-1" />)
    expect(screen.getByText('Vous (responsable)')).toBeTruthy()
    await openDialog()
    expect(await screen.findByRole('button', { name: 'Awa' })).toBeTruthy()
    expect(
      (screen.getByRole('button', { name: 'Bema (code PIN à choisir)' }) as HTMLButtonElement)
        .disabled,
    ).toBe(true)
    expect(screen.queryByText('Ancien')).toBeNull()
    // The full app is the owner's: no « Vous (responsable) » shortcut in the list any more.
    expect(screen.queryByRole('button', { name: 'Vous (responsable)' })).toBeNull()
  })

  it('without an owner code yet, asks to choose one before the first change', async () => {
    serve(opened, false)
    render(<TillSwitch shopId="shop-1" />)
    await openDialog()
    expect(await screen.findByText('Choisissez votre code de responsable')).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Awa' })).toBeNull()
    // A trivial code is refused on the spot.
    type('1234')
    fireEvent.click(screen.getByRole('button', { name: 'Continuer' }))
    expect(
      screen.getByText('Ce code est trop facile à deviner. Choisissez-en un autre.'),
    ).toBeTruthy()
    type('7391')
    fireEvent.click(screen.getByRole('button', { name: 'Continuer' }))
    type('7391')
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'Enregistrer mon code' }))
    })
    expect(rpc).toHaveBeenCalledWith('set_owner_pin', { p_shop_id: 'shop-1', p_new_pin: '7391' })
    expect(await screen.findByRole('button', { name: 'Awa' })).toBeTruthy()
  })

  it('opens a till session with THEIR PIN and turns the counter mode on', async () => {
    serve(opened)
    render(<TillSwitch shopId="shop-1" />)
    await pickAwaAndType('4826')
    expect(rpc).toHaveBeenCalledWith('open_till_session', {
      p_shop_id: 'shop-1',
      p_member_id: 'm-awa',
      p_pin: '4826',
    })
    expect(getTillSession('shop-1')?.token).toBe(TOKEN)
    expect(getTillSession('shop-1')?.sellerId).toBe('u-awa')
    expect(isCounterMode('shop-1')).toBe(true)
    // The counter flag is in localStorage (survives a reload), the token is not.
    expect(JSON.stringify({ ...localStorage })).not.toContain(TOKEN)
  })

  it('refuses a wrong PIN and says how many tries are left', async () => {
    serve({ status: 'invalid', attempts_left: 4 })
    render(<TillSwitch shopId="shop-1" />)
    await pickAwaAndType('1111')
    expect(screen.getByText('Code PIN incorrect. Encore 4 essais.')).toBeTruthy()
    expect(getTillSession('shop-1')).toBeNull()
    expect(isCounterMode('shop-1')).toBe(false)
  })

  it('says when the cashier is locked out', async () => {
    serve({ status: 'locked', retry_after: '2026-10-14T10:15:00Z' })
    render(<TillSwitch shopId="shop-1" />)
    await pickAwaAndType('1111')
    expect(screen.getByText('Trop d’essais. Réessayez dans 15 minutes.')).toBeTruthy()
  })
})
