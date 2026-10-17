import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { supabase } from '../../lib/supabase'
import { PinLockScreen, PinSetupScreen } from './PinScreens'

vi.mock('../../lib/supabase', () => ({ supabase: { rpc: vi.fn() } }))
const rpc = vi.mocked(supabase.rpc)

afterEach(() => {
  cleanup()
  rpc.mockReset()
})

/** Types a PIN on the on-screen keypad, then the submit key. */
async function typePin(pin: string) {
  for (const d of pin) fireEvent.click(screen.getByRole('button', { name: d }))
  await act(async () => {
    fireEvent.click(screen.getByRole('button', { name: /Ouvrir la caisse|Continuer|Enregistrer/ }))
  })
}

const answer = (data: unknown) => ({ data, error: null }) as never

describe('PinLockScreen (personal device)', () => {
  const props = {
    shopId: 'shop-1',
    shopName: 'Chez Mama Grâce',
    cashierName: 'Awa',
    onUnlocked: vi.fn(),
    onNotSet: vi.fn(),
    onSignOut: vi.fn(),
  }

  it('never shows the digits, only dots, and has 44 px+ keys', () => {
    render(<PinLockScreen {...props} />)
    for (const d of '4826') fireEvent.click(screen.getByRole('button', { name: d }))
    expect(screen.getByRole('status').textContent).toContain('4 chiffres saisis')
    expect(document.body.textContent).not.toContain('4826')
    expect(screen.getByRole('button', { name: '5' }).className).toContain('pinpad__key')
  })

  it('checks the PIN on the server and opens the till', async () => {
    rpc.mockResolvedValue(answer({ status: 'ok' }))
    render(<PinLockScreen {...props} />)
    await typePin('4826')
    expect(rpc).toHaveBeenCalledWith('verify_my_pin', { p_shop_id: 'shop-1', p_pin: '4826' })
    expect(props.onUnlocked).toHaveBeenCalled()
  })

  it('says how many tries are left, then that the till is locked for 15 minutes', async () => {
    rpc.mockResolvedValueOnce(answer({ status: 'invalid', attempts_left: 2 }))
    render(<PinLockScreen {...props} />)
    await typePin('1111')
    expect(screen.getByText('Code PIN incorrect. Encore 2 essais.')).toBeTruthy()
    rpc.mockResolvedValueOnce(answer({ status: 'locked', retry_after: '2026-10-14T10:15:00Z' }))
    await typePin('2222')
    expect(screen.getByText('Trop d’essais. Réessayez dans 15 minutes.')).toBeTruthy()
  })

  it('asks for a new PIN when the owner reset it', async () => {
    rpc.mockResolvedValue(answer({ status: 'not_set' }))
    render(<PinLockScreen {...props} />)
    await typePin('4826')
    expect(props.onNotSet).toHaveBeenCalled()
  })
})

describe('PinSetupScreen « Choisissez votre code PIN »', () => {
  it('refuses a trivial PIN before calling the server', async () => {
    render(<PinSetupScreen shopId="shop-1" shopName="Boutique" onDone={vi.fn()} />)
    await typePin('1234')
    expect(screen.getByText(/trop facile/)).toBeTruthy()
    expect(rpc).not.toHaveBeenCalled()
  })

  it('asks twice and starts again when the two codes differ', async () => {
    render(<PinSetupScreen shopId="shop-1" shopName="Boutique" onDone={vi.fn()} />)
    await typePin('4826')
    expect(screen.getByRole('heading', { name: 'Tapez-le une deuxième fois' })).toBeTruthy()
    await typePin('4827')
    expect(screen.getByText('Les deux codes ne sont pas pareils. Recommencez.')).toBeTruthy()
    expect(screen.getByRole('heading', { name: 'Choisissez votre code PIN' })).toBeTruthy()
    expect(rpc).not.toHaveBeenCalled()
  })

  it('saves the PIN once confirmed (no current PIN after a reset)', async () => {
    rpc.mockResolvedValue(answer({ status: 'ok' }))
    const onDone = vi.fn()
    render(<PinSetupScreen shopId="shop-1" shopName="Boutique" reset onDone={onDone} />)
    expect(screen.getByText(/Le responsable a effacé votre ancien code/)).toBeTruthy()
    await typePin('4826')
    await typePin('4826')
    expect(rpc).toHaveBeenCalledWith('set_my_pin', { p_shop_id: 'shop-1', p_new_pin: '4826' })
    expect(onDone).toHaveBeenCalled()
  })

  it('asks for the current PIN to change it', async () => {
    rpc.mockResolvedValue(answer({ status: 'ok' }))
    render(<PinSetupScreen shopId="shop-1" shopName="Boutique" askCurrent onDone={vi.fn()} />)
    expect(screen.getByRole('heading', { name: 'Votre code PIN actuel' })).toBeTruthy()
    await typePin('4826')
    await typePin('7391')
    await typePin('7391')
    expect(rpc).toHaveBeenCalledWith('set_my_pin', {
      p_shop_id: 'shop-1',
      p_new_pin: '7391',
      p_current_pin: '4826',
    })
  })
})
