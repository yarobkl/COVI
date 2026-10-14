import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import { ChoiceField } from './ChoiceField'

afterEach(cleanup)

describe('ChoiceField — choisir sans retaper', () => {
  it('submits a selected saved value', () => {
    const view = render(
      <form aria-label="Article">
        <label>
          Produit
          <ChoiceField name="name" choices={['Jean', 'Robe']} required />
        </label>
      </form>,
    )
    fireEvent.change(screen.getByRole('combobox', { name: 'Produit' }), {
      target: { value: 'Robe' },
    })
    expect(new FormData(view.container.querySelector('form')!).get('name')).toBe('Robe')
    expect(screen.queryByPlaceholderText('Saisir une nouvelle valeur')).toBeNull()
  })

  it('keeps the saved choice when editing an existing record', () => {
    const view = render(
      <form aria-label="Modification">
        <label>
          Taille
          <ChoiceField name="size" choices={['S', 'M', 'L']} defaultValue="M" />
        </label>
      </form>,
    )
    const select = screen.getByRole('combobox', { name: 'Taille' }) as HTMLSelectElement
    expect(select.value).toBe('M')
    expect(new FormData(view.container.querySelector('form')!).get('size')).toBe('M')
  })

  it('preserves an older custom value when editing', () => {
    const view = render(
      <form aria-label="Modification">
        <label>
          Libellé
          <ChoiceField name="label" choices={['Loyer']} defaultValue="Entretien vitrine" />
        </label>
      </form>,
    )
    const custom = screen.getByPlaceholderText('Saisir une nouvelle valeur') as HTMLInputElement
    expect(custom.value).toBe('Entretien vitrine')
    expect(new FormData(view.container.querySelector('form')!).getAll('label')).toEqual([
      'Entretien vitrine',
    ])
  })

  it('offers a new value only when choosing Autre', () => {
    const view = render(
      <form aria-label="Marque">
        <label>
          Marque
          <ChoiceField name="brand" choices={['Levi’s']} />
        </label>
      </form>,
    )
    const select = screen.getByRole('combobox', { name: 'Marque' }) as HTMLSelectElement
    const other = Array.from(select.options).find((item) => item.text.includes('Autre'))
    expect(other).toBeTruthy()
    fireEvent.change(select, { target: { value: other!.value } })
    fireEvent.change(screen.getByPlaceholderText('Saisir une nouvelle valeur'), {
      target: { value: 'Ma marque' },
    })
    const values = new FormData(view.container.querySelector('form')!).getAll('brand')
    expect(values).toEqual(['Ma marque'])
  })
})
