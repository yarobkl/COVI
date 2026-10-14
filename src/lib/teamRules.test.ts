import { describe, expect, it } from 'vitest'
import {
  belowMinimumMessage,
  inviteMessage,
  minUnitPrice,
  minutesUntil,
  pinProblem,
  pinResultMessage,
  teamErrorMessage,
} from './teamRules'

describe('minUnitPrice (same rule as min_unit_price in SQL)', () => {
  it('has no minimum for the owner', () => {
    expect(minUnitPrice(10000, null)).toBeNull()
    expect(minUnitPrice(10000, undefined)).toBeNull()
  })
  it('is the displayed price at 0 %, and round(price × (1 − pct)) otherwise', () => {
    expect(minUnitPrice(10000, 0)).toBe(10000)
    expect(minUnitPrice(10000, 10)).toBe(9000)
    expect(minUnitPrice(15000, 10)).toBe(13500)
    expect(minUnitPrice(7500, 15)).toBe(6375)
    expect(minUnitPrice(15, 10)).toBe(14) // 13.5 rounds half up, as PostgreSQL round()
    expect(minUnitPrice(10000, 100)).toBe(0)
  })
  it('never goes above the displayed price (prices with cents)', () => {
    expect(minUnitPrice(999.6, 0)).toBe(999.6)
  })
})

describe('pinProblem (same refusals as member_pin_assert_strength)', () => {
  it.each([
    '0000',
    '1111',
    '1234',
    '123456',
    '4321',
    '987654',
    '012345',
    '1212',
    '121212',
    '123123',
  ])('refuses the trivial PIN %s', (pin) => expect(pinProblem(pin)).toMatch(/trop facile/))
  it.each(['123', '1234567', '12a4', '', ' 4826'])('refuses the malformed PIN "%s"', (pin) =>
    expect(pinProblem(pin)).toMatch(/4 à 6 chiffres/),
  )
  it.each(['4826', '7391', '590263'])('accepts %s', (pin) => expect(pinProblem(pin)).toBeNull())
})

describe('messages', () => {
  it('explains the minimum price with the amount', () => {
    expect(belowMinimumMessage(9000)).toMatch(
      /^Ce prix est en dessous du minimum autorisé \(9.000 FCFA\)\. Demandez au responsable\.$/,
    )
  })
  it('says what a refused PIN means', () => {
    expect(pinResultMessage({ status: 'invalid', attempts_left: 3 })).toBe(
      'Code PIN incorrect. Encore 3 essais.',
    )
    expect(pinResultMessage({ status: 'invalid', attempts_left: 1 })).toMatch(/Dernier essai/)
    expect(pinResultMessage({ status: 'locked', retry_after: '2026-10-14T10:15:00Z' })).toBe(
      'Trop d’essais. Réessayez dans 15 minutes.',
    )
    expect(pinResultMessage({ status: 'not_set' })).toMatch(/pas encore choisi son code PIN/)
  })
  it('translates the team errors of the server', () => {
    expect(teamErrorMessage({ message: 'PIN too simple' })).toMatch(/trop facile/)
    expect(teamErrorMessage({ message: 'Invalid PIN format' })).toMatch(/4 à 6 chiffres/)
    expect(teamErrorMessage({ message: 'Owner cannot join own shop' })).toMatch(/responsable/)
    expect(teamErrorMessage({ message: 'Member not found' })).toMatch(/pas accès/)
    expect(teamErrorMessage({ message: 'Invalid discount' })).toMatch(/0 à 100/)
    expect(teamErrorMessage({ message: 'Too many pending invites' })).toMatch(/Annulez-en une/)
    expect(teamErrorMessage({ message: 'boom' })).toMatch(/Vérifiez le réseau/)
  })
  it('counts the minutes before a new try', () => {
    const now = Date.parse('2026-10-14T10:00:00Z')
    expect(minutesUntil('2026-10-14T10:15:00Z', now)).toBe(15)
    expect(minutesUntil('2026-10-14T10:00:10Z', now)).toBe(1)
    expect(minutesUntil('2026-10-14T09:00:00Z', now)).toBe(1)
  })
  it('writes a WhatsApp-friendly invitation that never asks for the PIN', () => {
    const text = inviteMessage('Chez Mama Grâce', {
      code: 'ABCD-EFGH-JKMN',
      expires_at: '2026-10-16T10:00:00Z',
    })
    expect(text).toContain('ABCD-EFGH-JKMN')
    expect(text).toContain('Chez Mama Grâce')
    expect(text).toContain('J’ai un code de caissier')
    expect(text).toMatch(/ne le donnez à personne/)
    expect(text).not.toMatch(/https?:/)
  })
})
