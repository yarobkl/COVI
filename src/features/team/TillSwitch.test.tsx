import { act, cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { TillSwitch } from './TillSwitch'

let pending = 0
vi.mock('../sync/useSyncState', () => ({
  useSyncState: () => ({ online: true, pending, rejected: 0 }),
}))

beforeEach(() => {
  pending = 0
})
afterEach(() => {
  cleanup()
})

describe('Secure cashier handoff on a shared device', () => {
  it('requires owner logout and cashier personal login, without collecting a cashier PIN', async () => {
    const onHandoff = vi.fn().mockResolvedValue(undefined)
    render(<TillSwitch onHandoff={onHandoff} />)

    expect(screen.getByText('Vous (responsable)')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Passer la caisse' }))

    const dialog = within(screen.getByRole('dialog', { name: 'Passer la caisse à un employé' }))
    expect(dialog.getByText(/son propre compte COVI/)).toBeTruthy()
    expect(dialog.queryByText('Qui tient la caisse ?')).toBeNull()
    await act(async () => {
      fireEvent.click(dialog.getByRole('button', { name: 'Déconnecter le responsable' }))
    })
    expect(onHandoff).toHaveBeenCalledTimes(1)
  })

  it('blocks logout while offline sales are pending', () => {
    pending = 2
    const onHandoff = vi.fn().mockResolvedValue(undefined)
    render(<TillSwitch onHandoff={onHandoff} />)
    fireEvent.click(screen.getByRole('button', { name: 'Passer la caisse' }))
    expect(screen.getByText(/2 vente\(s\) en attente de synchronisation/)).toBeTruthy()
    const handoff = screen.getByRole('button', { name: 'Déconnecter le responsable' })
    expect((handoff as HTMLButtonElement).disabled).toBe(true)
    fireEvent.click(handoff)
    expect(onHandoff).not.toHaveBeenCalled()
  })

  it('keeps the dialog open if signing out fails, so no unsafe handoff is assumed', async () => {
    const onHandoff = vi.fn().mockRejectedValue(new Error('Network'))
    render(<TillSwitch onHandoff={onHandoff} />)
    fireEvent.click(screen.getByRole('button', { name: 'Passer la caisse' }))
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'Déconnecter le responsable' }))
    })
    expect(screen.getByText(/La déconnexion a échoué/)).toBeTruthy()
    expect(screen.getByRole('dialog', { name: 'Passer la caisse à un employé' })).toBeTruthy()
  })
})
