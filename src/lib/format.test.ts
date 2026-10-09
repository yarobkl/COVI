import { describe, expect, it } from 'vitest'
import {
  fcfa,
  money,
  parseAmount,
  paymentCode,
  paymentLabel,
  paymentLabels,
  percent,
  plural,
  pluralize,
} from './format'

// The app fonts have the no-break space (U+00A0) but not the narrow one (U+202F) of fr-FR.
const nbsp = '\u00a0'

describe('fcfa', () => {
  it('groups thousands with no-break spaces only', () => {
    expect(fcfa(0)).toBe('0')
    expect(fcfa(950)).toBe('950')
    expect(fcfa(126000)).toBe(`126${nbsp}000`)
    expect(fcfa(2334000)).toBe(`2${nbsp}334${nbsp}000`)
    expect(fcfa(2334000)).not.toMatch(/[\u202f ]/)
  })

  it('writes money going out with the true minus sign and rounds to whole francs', () => {
    expect(fcfa(-90000)).toBe(`\u2212${nbsp}90${nbsp}000`)
    expect(fcfa(1234.5)).toBe(`1${nbsp}235`)
    expect(fcfa(-0.2)).toBe('0')
  })
})

describe('money', () => {
  it('adds the currency after a no-break space', () => {
    expect(money(0)).toBe(`0${nbsp}FCFA`)
    expect(money(15000)).toBe(`15${nbsp}000${nbsp}FCFA`)
    expect(money(-314000)).toBe(`\u2212${nbsp}314${nbsp}000${nbsp}FCFA`)
  })
})

describe('percent and parseAmount', () => {
  it('formats a percentage the French way', () => {
    expect(percent(74.4)).toBe(`74${nbsp}%`)
  })

  it('reads the digits of a typed amount', () => {
    expect(parseAmount('13 000')).toBe(13000)
    expect(parseAmount(`13${nbsp}000 FCFA`)).toBe(13000)
    expect(parseAmount('')).toBeNull()
    expect(parseAmount('abc')).toBeNull()
  })
})

describe('payment methods', () => {
  it('lists the checkout labels in display order', () => {
    expect(paymentLabels).toEqual(['Espèces', 'Mobile Money', 'Carte', 'Virement', 'Autre'])
  })

  it('maps labels to stored codes and back', () => {
    for (const label of paymentLabels) expect(paymentLabel(paymentCode(label))).toBe(label)
    expect(paymentCode('Mobile Money')).toBe('mobile_money')
    expect(paymentLabel('bank_transfer')).toBe('Virement')
  })

  it('falls back to « other » / the raw code for unknown values', () => {
    expect(paymentCode('Bon d’achat')).toBe('other')
    expect(paymentLabel('voucher')).toBe('voucher')
  })
})

describe('plural', () => {
  it('uses the singular below 2, as in French', () => {
    expect(plural(0, 'vente')).toBe('0 vente')
    expect(plural(1, 'vente')).toBe('1 vente')
    expect(plural(2, 'vente')).toBe('2 ventes')
    expect(plural(143, 'article')).toBe('143 articles')
  })

  it('accepts an irregular plural form', () => {
    expect(plural(1, 'vente refusée', 'ventes refusées')).toBe('1 vente refusée')
    expect(plural(3, 'vente refusée', 'ventes refusées')).toBe('3 ventes refusées')
  })

  it('pluralize returns the word alone', () => {
    expect(pluralize(1, 'article')).toBe('article')
    expect(pluralize(12, 'article')).toBe('articles')
    expect(pluralize(-1, 'article')).toBe('article')
    expect(pluralize(-5, 'article')).toBe('articles')
  })
})
