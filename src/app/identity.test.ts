import { describe, expect, it } from 'vitest'
import { initials, ownerName, shortName } from './identity'

describe('initials', () => {
  it('takes the first letters of the meaningful words', () => {
    expect(initials('Chez Mama Grâce')).toBe('MG')
    expect(initials('Grâce Mabiala')).toBe('GM')
    expect(initials('Boutique Élégance')).toBe('É')
    expect(initials('La Belle d’Afrique')).toBe('BA')
    expect(initials('  jean-pierre  ')).toBe('JP')
  })

  it('falls back to the small words, then to a question mark', () => {
    expect(initials('Chez')).toBe('C')
    expect(initials('')).toBe('?')
    expect(initials(null)).toBe('?')
  })
})

describe('ownerName / shortName', () => {
  it('reads the full name given by Google, if any', () => {
    expect(ownerName({ full_name: 'Grâce Mabiala' })).toBe('Grâce Mabiala')
    expect(ownerName({ name: ' Rose ' })).toBe('Rose')
    expect(ownerName({ email: 'a@b.cg' })).toBeNull()
    expect(ownerName(null)).toBeNull()
  })

  it('shortens to the first name and the initial of the last one', () => {
    expect(shortName('Grâce Mabiala')).toBe('Grâce M.')
    expect(shortName('Grâce Ngoma Mabiala')).toBe('Grâce M.')
    expect(shortName('Rose')).toBe('Rose')
  })
})
