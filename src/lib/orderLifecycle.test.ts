import { describe, expect, it } from 'vitest'
import {
  nextOrderStatus,
  releasesReservation,
  requiresStockDeduction,
  validateOrderChannel,
  validateManualPaymentConfirmation,
  prepareManualCashierAttestation,
} from './orderLifecycle'

describe('omnichannel order lifecycle', () => {
  it('records manual cashier confirmation without a payment API', () => {
    const confirmation = {
      method: 'mobile_money' as const,
      cashierFirstName: '  Marie   Lou  ',
      receivedByUserId: 'seller-123',
      confirmedAt: '2026-10-12T12:00:00Z',
      externalReference: 'SMS-987',
    }
    expect(validateManualPaymentConfirmation(confirmation)).toEqual({
      ...confirmation,
      cashierFirstName: 'Marie Lou',
    })
    expect(() =>
      validateManualPaymentConfirmation({ ...confirmation, receivedByUserId: ' ' }),
    ).toThrow()
    expect(() =>
      validateManualPaymentConfirmation({ ...confirmation, confirmedAt: 'invalid' }),
    ).toThrow()
    expect(() =>
      validateManualPaymentConfirmation({ ...confirmation, cashierFirstName: ' ' }),
    ).toThrow()
  })

  it('requires a typed first name for the person who receives the money', () => {
    const base = { method: 'cash' as const, cashierFirstName: ' Élodie ' }
    expect(prepareManualCashierAttestation(base)).toEqual({
      method: 'cash',
      cashierFirstName: 'Élodie',
    })
    for (const valid of ['Jean-Pierre', 'Marie Lou', 'N’Goma', 'Zoé']) {
      expect(
        prepareManualCashierAttestation({
          ...base,
          cashierFirstName: valid,
        }).cashierFirstName,
      ).toBe(valid)
    }
    for (const invalid of ['', '    ', 'Cashier123', '<script>', 'A'.repeat(61)]) {
      expect(() =>
        prepareManualCashierAttestation({
          ...base,
          cashierFirstName: invalid,
        }),
      ).toThrow()
    }
  })

  it('does not accept client-facing attestation without account identity', () => {
    expect(() =>
      validateManualPaymentConfirmation({
        method: 'mobile_money',
        cashierFirstName: 'Luc',
        receivedByUserId: '',
        confirmedAt: '2026-10-12T12:00:00Z',
      }),
    ).toThrow()
  })

  it('supports all three channels with one workflow', () => {
    expect(validateOrderChannel('qr')).toBe('qr')
    expect(validateOrderChannel('social')).toBe('social')
    expect(validateOrderChannel('manual')).toBe('manual')
    expect(() => validateOrderChannel('unknown')).toThrow()
  })

  it('requires merchant approval before payment', () => {
    expect(() => nextOrderStatus('submitted', 'confirm_payment')).toThrow()
    expect(nextOrderStatus('submitted', 'approve')).toBe('approved')
    expect(nextOrderStatus('approved', 'confirm_payment')).toBe('paid')
    expect(nextOrderStatus('approved', 'reserve')).toBe('reserved')
    expect(nextOrderStatus('reserved', 'confirm_payment')).toBe('paid')
  })

  it('makes paid orders terminal and never deducts stock twice', () => {
    for (const event of ['approve', 'reserve', 'confirm_payment', 'cancel', 'expire'] as const) {
      expect(() => nextOrderStatus('paid', event)).toThrow()
    }
    expect(requiresStockDeduction('reserved', 'paid')).toBe(true)
    expect(requiresStockDeduction('approved', 'paid')).toBe(true)
    expect(requiresStockDeduction('paid', 'paid')).toBe(false)
    expect(requiresStockDeduction('submitted', 'approved')).toBe(false)
  })

  it('releases a reserved quantity only on cancellation or expiration', () => {
    expect(releasesReservation('reserved', 'cancelled')).toBe(true)
    expect(releasesReservation('reserved', 'expired')).toBe(true)
    expect(releasesReservation('reserved', 'paid')).toBe(false)
    expect(releasesReservation('approved', 'cancelled')).toBe(false)
  })

  it('prevents cancelled or expired orders from being paid', () => {
    expect(() => nextOrderStatus('cancelled', 'confirm_payment')).toThrow()
    expect(() => nextOrderStatus('expired', 'confirm_payment')).toThrow()
  })
})
