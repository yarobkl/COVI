import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { Amount } from './Amount'
import { Button } from './Button'
import { Dialog } from './Dialog'
import { Field, Input } from './Field'
import { Segmented } from './Segmented'

afterEach(cleanup)

describe('Field', () => {
  it('ties the label, hint and error to the control', () => {
    render(
      <Field label="Marque" optional hint="Comme sur l’étiquette" error="Trop long">
        {(control) => <Input {...control} />}
      </Field>,
    )
    const input = screen.getByLabelText('Marque (facultatif)')
    expect(input.getAttribute('aria-invalid')).toBe('true')
    const described = (input.getAttribute('aria-describedby') ?? '').split(' ')
    expect(described.map((id) => document.getElementById(id)?.textContent)).toEqual([
      'Comme sur l’étiquette',
      'Trop long',
    ])
  })
})

describe('Segmented', () => {
  it('is a group of real radio buttons', () => {
    const onChange = vi.fn()
    render(
      <Segmented
        legend="Payé en"
        options={[
          { value: 'cash', label: 'Espèces' },
          { value: 'card', label: 'Carte' },
        ]}
        value="cash"
        onChange={onChange}
      />,
    )
    expect(screen.getByRole('group', { name: 'Payé en' })).toBeTruthy()
    expect(screen.getByRole('radio', { name: 'Espèces' })).toHaveProperty('checked', true)
    fireEvent.click(screen.getByRole('radio', { name: 'Carte' }))
    expect(onChange).toHaveBeenCalledWith('card')
  })
})

describe('Button', () => {
  it('ignores clicks and says so while busy', () => {
    const onClick = vi.fn()
    render(
      <Button busy onClick={onClick}>
        Se connecter
      </Button>,
    )
    const button = screen.getByRole('button', { name: 'Un instant…' })
    expect(button.getAttribute('aria-busy')).toBe('true')
    fireEvent.click(button)
    expect(onClick).not.toHaveBeenCalled()
  })
})

describe('Amount', () => {
  it('writes money going out with the true minus sign', () => {
    const { container } = render(<Amount value={-90000} tone="out" unit />)
    const [minus, nbsp] = [String.fromCharCode(0x2212), String.fromCharCode(0xa0)]
    expect(container.textContent).toBe(`${minus}${nbsp}90${nbsp}000FCFA`)
    expect(container.firstElementChild?.className).toBe('amount amount--md amount--out')
  })
})

describe('Dialog', () => {
  it('renders its content only while open and closes on Escape', () => {
    const onClose = vi.fn()
    const { rerender } = render(
      <Dialog open={false} onClose={onClose} labelledBy="t">
        <h2 id="t">Se déconnecter ?</h2>
      </Dialog>,
    )
    expect(screen.queryByText('Se déconnecter ?')).toBeNull()
    rerender(
      <Dialog open onClose={onClose} labelledBy="t">
        <h2 id="t">Se déconnecter ?</h2>
      </Dialog>,
    )
    expect(screen.getByText('Se déconnecter ?')).toBeTruthy()
    fireEvent(document.querySelector('dialog')!, new Event('cancel', { cancelable: true }))
    expect(onClose).toHaveBeenCalledTimes(1)
  })
})
