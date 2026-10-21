import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { AssistantPage } from './AssistantPage'
import { askCoviAssistant } from '../../lib/assistant'

vi.mock('../../lib/assistant', () => ({ askCoviAssistant: vi.fn() }))

const shop = {
  id: '11111111-1111-4111-8111-111111111111',
  name: 'Boutique test',
  city: 'Brazzaville',
  country: 'Congo',
  currency: 'XAF',
  business_kind: 'retail',
}

describe('AssistantPage', () => {
  beforeEach(() => vi.clearAllMocks())
  afterEach(cleanup)

  it('requires explicit consent before sending a question to Gemini', async () => {
    vi.mocked(askCoviAssistant).mockResolvedValue('Ce montant ne représente pas le bénéfice net.')
    render(<AssistantPage shop={shop} />)
    fireEvent.change(screen.getByLabelText('Votre message'), { target: { value: 'Mes ventes ?' } })
    const send = screen.getByRole('button', { name: 'Envoyer' })
    expect((send as HTMLButtonElement).disabled).toBe(true)
    expect(askCoviAssistant).not.toHaveBeenCalled()
    fireEvent.click(screen.getByRole('checkbox'))
    fireEvent.change(screen.getByLabelText('Code PIN responsable'), { target: { value: '1379' } })
    expect((send as HTMLButtonElement).disabled).toBe(false)
    fireEvent.click(send)
    await waitFor(() =>
      expect(askCoviAssistant).toHaveBeenCalledWith(shop.id, 'Mes ventes ?', '1379', []),
    )
    expect(await screen.findByText('Ce montant ne représente pas le bénéfice net.')).toBeTruthy()
    expect(screen.getByLabelText('Code PIN responsable')).toHaveProperty('value', '1379')
  })

  it('retains six previous exchanges for follow-up questions, without restarting the chat', async () => {
    vi.mocked(askCoviAssistant)
      .mockResolvedValueOnce('Vos ventes sont de 1 000 XAF.')
      .mockResolvedValueOnce('Le chiffre est celui de ce mois, pas un bénéfice net.')
    render(<AssistantPage shop={shop} />)
    fireEvent.click(screen.getByRole('checkbox'))
    fireEvent.change(screen.getByLabelText('Code PIN responsable'), { target: { value: '1379' } })
    fireEvent.change(screen.getByLabelText('Votre message'), { target: { value: 'Mes ventes ?' } })
    fireEvent.click(screen.getByRole('button', { name: 'Envoyer' }))
    expect(await screen.findByText('Vos ventes sont de 1 000 XAF.')).toBeTruthy()

    fireEvent.change(screen.getByLabelText('Votre message'), {
      target: { value: 'Et par rapport au mois dernier ?' },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Envoyer' }))
    await waitFor(() => expect(askCoviAssistant).toHaveBeenCalledTimes(2))
    expect(askCoviAssistant).toHaveBeenNthCalledWith(
      2,
      shop.id,
      'Et par rapport au mois dernier ?',
      '1379',
      [
        { role: 'user', text: 'Mes ventes ?' },
        { role: 'model', text: 'Vos ventes sont de 1 000 XAF.' },
      ],
    )
    expect(
      await screen.findByText('Le chiffre est celui de ce mois, pas un bénéfice net.'),
    ).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Nouvelle conversation' }))
    expect(screen.queryByText('Vos ventes sont de 1 000 XAF.')).toBeNull()
  })

  it('does not promise real financial data for the restaurant', () => {
    render(<AssistantPage shop={{ ...shop, business_kind: 'restaurant' }} />)
    expect(screen.getByText(/chiffres financiers de ce métier/i)).toBeTruthy()
    expect(
      screen.getByRole('button', { name: 'Comment réduire le gaspillage alimentaire ?' }),
    ).toBeTruthy()
  })
})
