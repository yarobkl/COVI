import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { useState, type ReactNode } from 'react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { Shop } from '../lib/types'

// The shell is replaced by a stub that keeps « loaded data » in its state, as the pages do
// (products, stock, sales, figures): it must never survive a change of shop.
vi.mock('./App', () => ({
  App: ({ shop }: { shop: Shop }) => {
    const [loadedFor] = useState(shop.id)
    const [touched, setTouched] = useState(0)
    return (
      <div>
        <p>{`affichée:${shop.id} données:${loadedFor} touches:${touched}`}</p>
        <button type="button" onClick={() => setTouched((n) => n + 1)}>
          toucher
        </button>
      </div>
    )
  },
}))

const A: Shop = { id: 'shop-a', name: 'A', city: null, country: 'Congo', currency: 'XAF' }
const B: Shop = { id: 'shop-b', name: 'B', city: null, country: 'Congo', currency: 'XAF' }

// AuthGate is replaced by a gate whose open shop can be changed from the test.
vi.mock('../features/auth/AuthGate', () => ({
  AuthGate: ({
    children,
  }: {
    children: (shop: Shop, s: () => Promise<void>, u: () => void, a: object) => ReactNode
  }) => {
    const [shop, setShop] = useState(A)
    return (
      <>
        <button type="button" onClick={() => setShop(shop.id === A.id ? B : A)}>
          changer
        </button>
        {children(
          shop,
          async () => {},
          () => {},
          { shopCount: 2, readOnly: false },
        )}
      </>
    )
  },
}))

const { Root } = await import('./Root')
afterEach(cleanup)

describe('Root: changing shop', () => {
  it('unmounts the whole app: no state of shop A is shown in shop B', () => {
    render(<Root />)
    expect(screen.getByText('affichée:shop-a données:shop-a touches:0')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'toucher' }))
    expect(screen.getByText('affichée:shop-a données:shop-a touches:1')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'changer' }))
    // Without key={shop.id} the stub would still show « données:shop-a touches:1 » under B.
    expect(screen.getByText('affichée:shop-b données:shop-b touches:0')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'changer' }))
    expect(screen.getByText('affichée:shop-a données:shop-a touches:0')).toBeTruthy()
  })
})
