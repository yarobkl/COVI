import { afterEach, describe, expect, it, vi } from 'vitest'
import type { Arrival } from '../../lib/types'
import { emptyProduct, productFromValues, productSaveError } from './productForm'

const arrivals = [
  { id: 'bal', kind: 'balloon', is_test: false },
  { id: 'chn', kind: 'supplier_order', is_test: true },
] as Pick<Arrival, 'id' | 'kind' | 'is_test'>[]

describe('productFromValues', () => {
  it('turns what was typed into the product to save', () => {
    const result = productFromValues(
      {
        ...emptyProduct(),
        name: '  Robe wax modèle A ',
        category: 'Robes',
        price: '18 000',
        quantity: 3,
        arrivalId: 'chn',
      },
      arrivals,
    )
    expect(result.errors).toBeNull()
    expect(result.input).toMatchObject({
      name: 'Robe wax modèle A',
      category: 'Robes',
      initial_sale_price: 18000,
      quantity_on_hand: 3,
      is_unique_piece: false,
      arrival_id: 'chn',
      is_test: true,
      image: null,
    })
  })

  it('a unique piece counts 1; a bale piece is always unique', () => {
    const unique = productFromValues(
      { ...emptyProduct(), name: 'Veste', price: '15000', unique: true, quantity: 7 },
      arrivals,
    )
    expect(unique.input).toMatchObject({ quantity_on_hand: 1, is_unique_piece: true })
    const bale = productFromValues(
      { ...emptyProduct(), name: 'Robe pagne', price: '10000', quantity: 4, arrivalId: 'bal' },
      arrivals,
    )
    expect(bale.input).toMatchObject({ quantity_on_hand: 1, is_unique_piece: true })
    expect(emptyProduct({ id: 'bal', kind: 'balloon' })).toMatchObject({
      unique: true,
      arrivalId: 'bal',
    })
  })

  it('says what to fix, in French', () => {
    const result = productFromValues({ ...emptyProduct(), quantity: 0 }, arrivals)
    expect(result.errors).toEqual({
      name: 'Indiquez le nom de l’article.',
      price: 'Indiquez le prix affiché, en FCFA.',
      quantity: 'Indiquez au moins 1 pièce.',
    })
    expect(
      productFromValues({ ...emptyProduct(), name: 'A', price: '1000', quantity: 5000 }, arrivals)
        .errors?.quantity,
    ).toMatch(/999 pièces au plus/)
  })
})

describe('productSaveError', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('rewrites the photo messages and never shows the raw error', () => {
    expect(
      productSaveError(new Error('Choisissez une image JPG, PNG ou WebP de 5 Mo maximum.')),
    ).toBe('Cette photo ne passe pas. Prenez une photo JPG ou PNG de moins de 5 Mo.')
    expect(
      productSaveError(
        new Error('La photo n’a pas pu être enregistrée. Vérifiez votre connexion puis réessayez.'),
      ),
    ).toMatch(/enregistrez l’article sans photo/)
    expect(productSaveError({ message: 'new row violates row-level security policy' })).toBe(
      'Ça n’a pas marché. Vérifiez le réseau puis réessayez.',
    )
    expect(productSaveError(new TypeError('Failed to fetch'))).toMatch(/^Pas de réseau/)
  })
})
