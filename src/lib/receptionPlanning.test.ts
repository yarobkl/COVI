import { describe, expect, it } from 'vitest'
import { prepareReceptionLines, validateReceptionCost } from './receptionPlanning'

describe('ballon and supplier reception planning', () => {
  it('merges the same category without changing the input', () => {
    const input = Object.freeze([
      Object.freeze({ category: 'Robes', quantity: 12 }),
      Object.freeze({ category: ' robes ', quantity: 8 }),
      Object.freeze({ category: 'Chemises', quantity: 5 }),
    ])
    expect(prepareReceptionLines(input)).toEqual([
      { categoryKey: 'robes', quantity: 20 },
      { categoryKey: 'chemises', quantity: 5 },
    ])
  })

  it('rejects empty or malformed receptions', () => {
    expect(() => prepareReceptionLines([])).toThrow()
    expect(() => prepareReceptionLines([{ category: ' ', quantity: 2 }])).toThrow()
    expect(() => prepareReceptionLines([{ category: 'Sacs', quantity: 0 }])).toThrow()
    expect(() => prepareReceptionLines([{ category: 'Sacs', quantity: -3 }])).toThrow()
    expect(() => prepareReceptionLines([{ category: 'Sacs', quantity: 1.5 }])).toThrow()
    expect(() => prepareReceptionLines([{ category: 'Sacs', quantity: NaN }])).toThrow()
  })

  it('rejects quantities beyond PostgreSQL integer capacity', () => {
    expect(() => prepareReceptionLines([
      { category: 'Robes', quantity: 2147483647 },
      { category: 'Robes', quantity: 1 },
    ])).toThrow()
  })

  it('allows a global balloon cost but never derives per-piece purchase cost', () => {
    expect(validateReceptionCost(150000)).toBe(150000)
    expect(validateReceptionCost(0)).toBe(0)
    for (const invalid of [-1, 1.25, Infinity, NaN]) {
      expect(() => validateReceptionCost(invalid)).toThrow()
    }
  })
})
