import { describe, expect, it, vi } from 'vitest'

vi.mock('../../lib/supabase', () => ({ supabase: {} }))
const { copyDate, readShopDraft } = await import('./shopSettings')

describe('Ma boutique', () => {
  it('asks for the name and trims the fields', () => {
    expect(readShopDraft({ name: '  ', city: 'Brazzaville', country: 'Congo' })).toEqual({
      error: 'Indiquez le nom de la boutique.',
    })
    expect(readShopDraft({ name: ' Chez Mama Grâce ', city: ' Poto-Poto ', country: '' })).toEqual({
      values: { name: 'Chez Mama Grâce', city: 'Poto-Poto', country: '' },
    })
  })

  it('says when the stock was copied on this device', () => {
    const now = new Date(2026, 9, 8, 15, 0)
    expect(copyDate(new Date(2026, 9, 8, 14, 32).toISOString(), now)).toBe('aujourd’hui à 14 h 32')
    expect(copyDate(new Date(2026, 9, 7, 9, 5).toISOString(), now)).toBe('hier à 9 h 05')
    expect(copyDate(new Date(2026, 9, 2, 18, 0).toISOString(), now)).toBe(
      'vendredi 2 octobre à 18 h 00',
    )
    expect(copyDate(null, now)).toBeNull()
    expect(copyDate('pas une date', now)).toBeNull()
  })
})
