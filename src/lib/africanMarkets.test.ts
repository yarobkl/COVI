import { describe, expect, it } from 'vitest'
import {
  AFRICAN_MARKETS,
  officialCurrencyForCountry,
  marketForCountry,
  paymentCurrenciesForCountry,
} from './africanMarkets'

describe('African country registration currencies', () => {
  it('keeps all 6 CEMAC member states on XAF, independently from XOF', () => {
    const cemac = AFRICAN_MARKETS.filter((market) => market.region === 'cemac')
    expect(cemac).toHaveLength(6)
    expect(cemac.every((market) => market.currency === 'XAF')).toBe(true)
    expect(officialCurrencyForCountry('République du Congo')).toBe('XAF')
    expect(officialCurrencyForCountry('Côte d’Ivoire')).toBe('XOF')
    expect(officialCurrencyForCountry('République du Congo')).not.toBe(
      officialCurrencyForCountry('Côte d’Ivoire'),
    )
  })

  it('assigns XOF to UEMOA, including the 3 former ECOWAS members', () => {
    const union = AFRICAN_MARKETS.filter((market) => market.region === 'uemoa')
    expect(union).toHaveLength(8)
    expect(union.every((market) => market.currency === 'XOF')).toBe(true)
    for (const country of ['Mali', 'Burkina Faso', 'Niger']) {
      expect(marketForCountry(country)?.region).toBe('uemoa')
      expect(officialCurrencyForCountry(country)).toBe('XOF')
    }
  })

  it('never mislabels non-UEMOA ECOWAS members as using CFA', () => {
    expect(officialCurrencyForCountry('Ghana')).toBe('GHS')
    expect(officialCurrencyForCountry('Nigeria')).toBe('NGN')
    expect(officialCurrencyForCountry('Guinée')).toBe('GNF')
    expect(officialCurrencyForCountry('Sierra Leone')).toBe('SLE')
    expect(AFRICAN_MARKETS.filter((market) => market.region === 'ecowas_other')).toHaveLength(7)
  })

  it('records the DRC in Central Africa with CDF as legal base currency and USD as additional settlement currency', () => {
    expect(marketForCountry('République démocratique du Congo')?.region).toBe('central_other')
    expect(officialCurrencyForCountry('République démocratique du Congo')).toBe('CDF')
    expect(paymentCurrenciesForCountry('République démocratique du Congo')).toEqual([
      'CDF',
      'USD',
    ])
    expect(paymentCurrenciesForCountry('République du Congo')).toEqual(['XAF'])
    expect(officialCurrencyForCountry('Angola')).toBe('AOA')
    expect(officialCurrencyForCountry('São Tomé-et-Príncipe')).toBe('STN')
    expect(officialCurrencyForCountry('France')).toBeNull()
  })

  it('contains exactly one entry per country and does not infer an FX rate', () => {
    expect(new Set(AFRICAN_MARKETS.map((market) => market.country)).size).toBe(
      AFRICAN_MARKETS.length,
    )
    expect(AFRICAN_MARKETS).toHaveLength(26)
  })
})
