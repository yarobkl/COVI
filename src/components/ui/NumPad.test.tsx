import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { useState } from 'react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { NumPad } from './NumPad'

afterEach(cleanup)

const nbsp = String.fromCharCode(0xa0)

function Harness({ onConfirm, keyboard = false }: { onConfirm: () => void; keyboard?: boolean }) {
  const [value, setValue] = useState<number | null>(15000)
  return (
    <NumPad
      value={value}
      onChange={setValue}
      reference={15000}
      onConfirm={onConfirm}
      keyboard={keyboard}
    />
  )
}

const display = () => screen.getByRole('status').textContent

describe('NumPad', () => {
  it('lowers the displayed price and spells out the discount', () => {
    render(<Harness onConfirm={vi.fn()} />)
    expect(display()).toContain(`15${nbsp}000`)
    fireEvent.click(screen.getByRole('button', { name: 'Baisser de 1 000 FCFA' }))
    fireEvent.click(screen.getByRole('button', { name: 'Baisser de 500 FCFA' }))
    expect(display()).toContain(`13${nbsp}500`)
    expect(display()).toContain(`1${nbsp}500${nbsp}FCFA de remise`)
    fireEvent.click(screen.getByRole('button', { name: 'Prix affiché' }))
    expect(display()).not.toContain('remise')
  })

  it('types a new price with the keys, then keeps it', () => {
    const onConfirm = vi.fn()
    render(<Harness onConfirm={onConfirm} />)
    for (let i = 0; i < 5; i++)
      fireEvent.click(screen.getByRole('button', { name: 'Effacer un chiffre' }))
    expect(screen.getByRole('button', { name: 'Indiquez le prix' })).toHaveProperty(
      'disabled',
      true,
    )
    fireEvent.click(screen.getByRole('button', { name: '1' }))
    fireEvent.click(screen.getByRole('button', { name: '2' }))
    fireEvent.click(screen.getByRole('button', { name: 'Trois zéros' }))
    expect(display()).toContain(`12${nbsp}000`)
    fireEvent.click(screen.getByRole('button', { name: 'Garder ce prix' }))
    expect(onConfirm).toHaveBeenCalledTimes(1)
  })

  it('accepts a physical keyboard when asked to', () => {
    const onConfirm = vi.fn()
    render(<Harness onConfirm={onConfirm} keyboard />)
    fireEvent.keyDown(window, { key: 'Backspace' })
    fireEvent.keyDown(window, { key: 'Backspace' })
    fireEvent.keyDown(window, { key: '8' })
    expect(display()).toContain(`1${nbsp}508`)
    expect(screen.getByRole('button', { name: '8' }).className).toContain('is-tapped')
    fireEvent.keyDown(window, { key: 'Enter' })
    expect(onConfirm).toHaveBeenCalledTimes(1)
  })
})
