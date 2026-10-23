import { describe, expect, it } from 'vitest'
import {
  comparisonEmail,
  comparisonInternationalPhone,
  possibleDuplicate,
  prepareCrmIdentity,
} from './crmIdentity'

describe('CRM contact identity (shop-scoped comparison hints)', () => {
  it('normalises display name but preserves the entered contact details', () => {
    expect(
      prepareCrmIdentity({
        name: '  Marie   Louise ',
        email: ' Contact@Example.COM ',
        phone: ' +242 06 123 45 67 ',
      }),
    ).toEqual({
      name: 'Marie Louise',
      email: 'Contact@Example.COM',
      phone: '+242 06 123 45 67',
    })
  })

  it('rejects empty/oversized names and malformed emails', () => {
    expect(() => prepareCrmIdentity({ name: '   ' })).toThrow()
    expect(() => prepareCrmIdentity({ name: 'x'.repeat(161) })).toThrow()
    expect(() => prepareCrmIdentity({ name: 'Client', email: 'not-an-email' })).toThrow()
  })

  it('produces conservative international-only comparison hints', () => {
    expect(comparisonEmail(' CLIENT@Example.com ')).toBe('client@example.com')
    expect(comparisonEmail('wrong address@example.com')).toBeNull()
    expect(comparisonInternationalPhone('+242 (06) 123-4567')).toBe('+242061234567')
    expect(comparisonInternationalPhone('06 12 34 56 78')).toBeNull()
    expect(comparisonInternationalPhone('+0 612345678')).toBeNull()
  })

  it('flags duplicates as review candidates only', () => {
    const a = prepareCrmIdentity({ name: 'A', email: 'A@EXAMPLE.COM' })
    const b = prepareCrmIdentity({ name: 'B', email: 'a@example.com' })
    const c = prepareCrmIdentity({ name: 'C', phone: '0612345678' })
    const d = prepareCrmIdentity({ name: 'D', phone: '0612345678' })
    expect(possibleDuplicate(a, b)).toBe(true)
    expect(possibleDuplicate(c, d)).toBe(false)
    expect(possibleDuplicate(a, c)).toBe(false)
  })

  it('rejects very long telephone input', () => {
    expect(() => prepareCrmIdentity({ name: 'A', phone: '9'.repeat(41) })).toThrow()
  })
})
