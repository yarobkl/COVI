import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { cancelAccountDeletion, requestAccountDeletion } from '../../lib/account'
import { AccountDeletionPanel } from './AccountDeletionPanel'
import { DeletionPendingScreen } from './DeletionPendingScreen'

vi.mock('../../lib/account', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../lib/account')>()),
  requestAccountDeletion: vi.fn(),
  cancelAccountDeletion: vi.fn().mockResolvedValue({}),
}))
vi.mock('../../lib/team', () => ({
  ownerPinStatus: vi.fn().mockResolvedValue({ pin_set: true, locked_until: null }),
}))

afterEach(() => {
  cleanup()
  vi.clearAllMocks()
})

describe('AccountDeletionPanel', () => {
  it('needs the word SUPPRIMER and the owner code, and says when the code is wrong', async () => {
    const onScheduled = vi.fn()
    vi.mocked(requestAccountDeletion)
      .mockResolvedValueOnce({ status: 'invalid', attemptsLeft: 4 })
      .mockResolvedValueOnce({ status: 'ok', purgeAfter: '2026-11-14T10:00:00Z' })
    render(<AccountDeletionPanel shopId="s1" shopName="Yaro Boutique" onScheduled={onScheduled} />)
    fireEvent.click(screen.getByRole('button', { name: 'Supprimer mon compte…' }))
    const go = () =>
      screen.getByRole('button', { name: 'Programmer la suppression' }) as HTMLButtonElement
    expect(go().disabled).toBe(true)
    fireEvent.change(screen.getByLabelText('Tapez SUPPRIMER pour confirmer'), {
      target: { value: 'supprimer' },
    })
    expect(go().disabled).toBe(true) // le code du responsable manque
    fireEvent.change(await screen.findByLabelText('Code du responsable'), {
      target: { value: '0000' },
    })
    fireEvent.click(go())
    expect(
      await screen.findByText('Code du responsable incorrect. Encore 4 essai(s).'),
    ).toBeTruthy()
    expect(onScheduled).not.toHaveBeenCalled()
    fireEvent.change(screen.getByLabelText('Code du responsable'), { target: { value: '4876' } })
    fireEvent.click(go())
    await waitFor(() => expect(onScheduled).toHaveBeenCalled())
    expect(requestAccountDeletion).toHaveBeenLastCalledWith('supprimer', '4876')
  })
})

describe('DeletionPendingScreen', () => {
  it('shows the purge day and lets the owner cancel', async () => {
    const onCancelled = vi.fn()
    render(
      <DeletionPendingScreen
        purgeAfter="2026-11-14T10:00:00Z"
        onCancelled={onCancelled}
        onSignOut={() => {}}
      />,
    )
    expect(screen.getByText('14 novembre 2026')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Annuler la suppression' }))
    await waitFor(() => expect(onCancelled).toHaveBeenCalled())
    expect(cancelAccountDeletion).toHaveBeenCalled()
  })
})
