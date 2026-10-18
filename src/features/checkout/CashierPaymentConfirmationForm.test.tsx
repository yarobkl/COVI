import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { CashierPaymentConfirmationForm } from './CashierPaymentConfirmationForm'

afterEach(cleanup)

describe('cashier confirmation form', () => {
  it('requires a payment method and first name before submitting', async () => {
    const onConfirm = vi.fn(async () => {})
    render(<CashierPaymentConfirmationForm amountXaf={12000} onConfirm={onConfirm} />)

    const submit = screen.getByRole('button', {
      name: 'Confirmer le paiement reçu',
    }) as HTMLButtonElement
    expect(submit.disabled).toBe(true)

    fireEvent.click(screen.getByLabelText('Mobile Money'))
    fireEvent.change(screen.getByLabelText('Prénom de la personne qui encaisse'), {
      target: { value: '  Marie   Lou  ' },
    })
    expect(submit.disabled).toBe(false)
    fireEvent.click(submit)

    await waitFor(() =>
      expect(onConfirm).toHaveBeenCalledWith({
        method: 'mobile_money',
        cashierFirstName: 'Marie Lou',
      }),
    )
  })

  it('blocks malformed cashier names even when the button is active', async () => {
    const onConfirm = vi.fn(async () => {})
    render(<CashierPaymentConfirmationForm amountXaf={7000} onConfirm={onConfirm} />)
    fireEvent.click(screen.getByLabelText('Espèces'))
    fireEvent.change(screen.getByLabelText('Prénom de la personne qui encaisse'), {
      target: { value: '1234' },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Confirmer le paiement reçu' }))
    await waitFor(() => expect(screen.getByRole('alert').textContent).toContain('prénom valide'))
    expect(onConfirm).not.toHaveBeenCalled()
  })

  it('keeps the notebook total visible and prevents double clicks while the server records the sale', async () => {
    let finish: (() => void) | undefined
    const saving = new Promise<void>((resolve) => {
      finish = resolve
    })
    const onConfirm = vi.fn(() => saving)

    const { container } = render(
      <CashierPaymentConfirmationForm amountXaf={12000} onConfirm={onConfirm} />,
    )
    expect(container.querySelector('form.checkout-confirmation.sheet')).toBeTruthy()
    expect(screen.getByText('On note le paiement.')).toBeTruthy()
    expect(screen.getByText('À encaisser')).toBeTruthy()
    expect(screen.getByText(/COVI n'encaisse pas l'argent/)).toBeTruthy()

    fireEvent.click(screen.getByLabelText('Espèces'))
    fireEvent.change(screen.getByLabelText('Prénom de la personne qui encaisse'), {
      target: { value: 'Amina' },
    })
    const button = screen.getByRole('button', { name: 'Confirmer le paiement reçu' })
    fireEvent.click(button)
    expect(button.getAttribute('aria-busy')).toBe('true')
    expect((button as HTMLButtonElement).disabled).toBe(true)
    expect(onConfirm).toHaveBeenCalledTimes(1)

    fireEvent.click(button)
    expect(onConfirm).toHaveBeenCalledTimes(1)
    finish?.()
    await waitFor(() => expect(button.getAttribute('aria-busy')).toBeNull())
  })
  it('requires a PIN from an employee account and preserves the verified first name', async () => {
    const onConfirm = vi.fn(async () => {})
    render(
      <CashierPaymentConfirmationForm
        amountXaf={5700}
        onConfirm={onConfirm}
        requirePin
        verifiedCashierFirstName="Aminata"
      />,
    )
    const name = screen.getByLabelText('Prénom de la personne qui encaisse') as HTMLInputElement
    expect(name.value).toBe('Aminata')
    expect(name.readOnly).toBe(true)
    fireEvent.click(screen.getByLabelText('Espèces'))
    const submit = screen.getByRole('button', {
      name: 'Confirmer le paiement reçu',
    }) as HTMLButtonElement
    expect(submit.disabled).toBe(true)
    fireEvent.change(screen.getByLabelText('Mon code personnel de caisse'), {
      target: { value: '654321' },
    })
    expect(submit.disabled).toBe(false)
    fireEvent.click(submit)
    await waitFor(() =>
      expect(onConfirm).toHaveBeenCalledWith({
        cashierFirstName: 'Aminata',
        method: 'cash',
        pin: '654321',
      }),
    )
  })
})
