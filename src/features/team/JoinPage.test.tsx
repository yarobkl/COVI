import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { supabase } from '../../lib/supabase'
import { JoinPage } from './JoinPage'

vi.mock('../../lib/supabase', () => ({ supabase: { rpc: vi.fn() } }))
const rpc = vi.mocked(supabase.rpc)

afterEach(() => {
  cleanup()
  rpc.mockReset()
})

async function join(code: string, answer: unknown) {
  rpc.mockResolvedValue({ data: answer, error: null } as never)
  const onJoined = vi.fn()
  render(<JoinPage onJoined={onJoined} onBack={vi.fn()} />)
  fireEvent.change(screen.getByLabelText('Code d’invitation'), { target: { value: code } })
  await act(async () => {
    fireEvent.click(screen.getByRole('button', { name: 'Rejoindre la boutique' }))
  })
  return onJoined
}

describe('JoinPage « Rejoindre une boutique »', () => {
  it('sends the code and opens the shop', async () => {
    const joined = {
      status: 'joined',
      member_id: 'm-1',
      shop_id: 'shop-1',
      shop_name: 'Chez Mama Grâce',
      display_name: 'Awa',
    }
    const onJoined = await join('abcd-efgh-jkmn', joined)
    expect(rpc).toHaveBeenCalledWith('redeem_member_invite', { p_code: 'ABCD-EFGH-JKMN' })
    expect(onJoined).toHaveBeenCalledWith(joined)
  })

  it('never says why a code is refused', async () => {
    await join('ABCD-EFGH-JKMN', { status: 'invalid' })
    expect(screen.getByText(/Ce code ne marche pas/)).toBeTruthy()
  })

  it('says to wait after too many tries', async () => {
    await join('ABCD-EFGH-JKMN', { status: 'locked', retry_after: '2026-10-14T10:15:00Z' })
    expect(screen.getByText('Trop d’essais. Réessayez dans 15 minutes.')).toBeTruthy()
  })

  it('checks the length before calling the server', async () => {
    await join('ABCD', { status: 'invalid' })
    expect(rpc).not.toHaveBeenCalled()
    expect(screen.getByText(/12 lettres et chiffres/)).toBeTruthy()
  })
})
