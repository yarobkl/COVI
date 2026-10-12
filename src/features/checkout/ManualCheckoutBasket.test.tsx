import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { ManualCheckoutBasket } from './ManualCheckoutBasket'
import type { CheckoutStockCategory } from '../../lib/checkoutCategoryStock'

const robesId = 'aaaaaaaa-0000-4000-8000-000000000001'
const chemisesId = 'aaaaaaaa-0000-4000-8000-000000000002'
const shopId = '11111111-1111-4111-8111-111111111111'

const categories: CheckoutStockCategory[] = [
  { id: robesId, shopId, label: 'Robes', available: 3, isTest: false },
  { id: chemisesId, shopId, label: 'Chemises', available: 2, isTest: false },
]

function choose(categoryId: string, price: string) {
  fireEvent.change(screen.getByLabelText('Catégorie'), { target: { value: categoryId } })
  fireEvent.change(screen.getByLabelText('Prix négocié par pièce'), {
    target: { value: price },
  })
}
function add() {
  fireEvent.click(screen.getByRole('button', { name: 'Ajouter au panier' }))
}

afterEach(cleanup)

describe('notebook category checkout basket', () => {
  it('keeps ledger visuals while calculating a negotiated multi-category order', async () => {
    const onPrepare = vi.fn(async () => {})
    const { container } = render(
      <ManualCheckoutBasket categories={categories} onPrepare={onPrepare} />,
    )
    expect(container.querySelector('.checkout-basket.sheet')).toBeTruthy()
    expect(screen.getByText('Une ligne, un prix convenu.')).toBeTruthy()
    expect(screen.getByText(/ne retire rien du stock/)).toBeTruthy()

    choose(robesId, '3 500')
    fireEvent.click(screen.getByRole('button', { name: 'Une pièce de plus : Robes' }))
    add()
    choose(chemisesId, '2 000')
    add()

    expect(screen.getByText('Total · 3 pièces')).toBeTruthy()
    expect(screen.getAllByText(/9\s*000/).length).toBeGreaterThan(0)
    fireEvent.click(screen.getByRole('button', { name: /Préparer la commande/ }))
    await waitFor(() => expect(onPrepare).toHaveBeenCalledWith([
      { categoryId: robesId, quantity: 2, negotiatedUnitPriceXaf: 3500 },
      { categoryId: chemisesId, quantity: 1, negotiatedUnitPriceXaf: 2000 },
    ]))
  })

  it('allows distinct prices for the same category, and caps quantities at remaining stock', async () => {
    const onPrepare = vi.fn(async () => {})
    render(<ManualCheckoutBasket categories={categories} onPrepare={onPrepare} />)
    choose(robesId, '3500')
    fireEvent.click(screen.getByRole('button', { name: 'Une pièce de plus : Robes' }))
    add()
    choose(robesId, '4000')
    add()
    expect(screen.getByRole('option', { name: /Robes/ }).getAttribute('disabled')).not.toBeNull()

    fireEvent.click(screen.getByRole('button', { name: /Préparer la commande/ }))
    await waitFor(() => expect(onPrepare).toHaveBeenCalledWith([
      { categoryId: robesId, quantity: 2, negotiatedUnitPriceXaf: 3500 },
      { categoryId: robesId, quantity: 1, negotiatedUnitPriceXaf: 4000 },
    ]))
  })

  it('does not prepare an empty order and can remove an item', () => {
    const onPrepare = vi.fn(async () => {})
    render(<ManualCheckoutBasket categories={categories} onPrepare={onPrepare} />)
    expect((screen.getByRole('button', { name: /Préparer la commande/ }) as HTMLButtonElement).disabled)
      .toBe(true)
    choose(robesId, '3000')
    add()
    fireEvent.click(screen.getByRole('button', { name: 'Retirer Robes du panier' }))
    expect(screen.getByText(/Le panier est vide/)).toBeTruthy()
    expect(onPrepare).not.toHaveBeenCalled()
  })

  it('prevents duplicate submissions while waiting for server approval', async () => {
    let resolve!: () => void
    const save = new Promise<void>((r) => { resolve = r })
    const onPrepare = vi.fn(() => save)
    render(<ManualCheckoutBasket categories={categories} onPrepare={onPrepare} />)
    choose(robesId, '3500')
    add()
    const submit = screen.getByRole('button', { name: /Préparer la commande/ }) as HTMLButtonElement
    fireEvent.click(submit)
    expect(submit.disabled).toBe(true)
    fireEvent.click(submit)
    expect(onPrepare).toHaveBeenCalledTimes(1)
    resolve()
    await waitFor(() => expect(submit.disabled).toBe(false))
  })
})
