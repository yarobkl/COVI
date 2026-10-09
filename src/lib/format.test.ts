import { describe, expect, it } from 'vitest'
import { money, paymentCode, paymentLabel, paymentLabels, plural, pluralize } from './format'

// fr-FR groups thousands with a narrow no-break space (U+202F).
const nbsp = ' '

describe('money', () => {
  it('formats CFA franc amounts with French digit grouping', () => {
    expect(money(0)).toBe('0 FCFA')
    expect(money(950)).toBe('950 FCFA')
    expect(money(15000)).toBe(`15${nbsp}000 FCFA`)
    expect(money(2334000)).toBe(`2${nbsp}334${nbsp}000 FCFA`)
  })

  it('keeps the sign and decimals', () => {
    expect(money(-314000)).toBe(`-314${nbsp}000 FCFA`)
    expect(money(1234.5)).toBe(`1${nbsp}234,5 FCFA`)
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
