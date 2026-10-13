import { describe, expect, it } from 'vitest'
import { countrySuggestions } from './countrySuggestions'
import { typedAmount } from '../stock/productForm'

describe('countrySuggestions', () => {
  it('offers the usual countries before anything is typed', () => {
    expect(countrySuggestions('', 'order')).toContain('Chine')
    expect(countrySuggestions('', 'balloon')).toContain('Belgique')
  })

  it('searches without accents, the usual countries first', () => {
    const tur = countrySuggestions('tur', 'order')
    expect(tur[0]).toBe('Turquie')
    expect(countrySuggestions('ETATS', 'order')).toContain('États-Unis')
  })

  it('stays quiet once a country is written in full', () => {
    expect(countrySuggestions('Inde', 'order')).toEqual([])
  })
})

describe('typedAmount', () => {
  it('groups the thousands as they are typed', () => {
    const nbsp = String.fromCharCode(0xa0)
    expect(typedAmount('19000')).toBe(`19${nbsp}000`)
    expect(typedAmount('1 250 000 F')).toBe(`1${nbsp}250${nbsp}000`)
    expect(typedAmount('abc')).toBe('')
  })
})
