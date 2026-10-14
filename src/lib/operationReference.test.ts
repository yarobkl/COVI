import { describe, expect, it } from 'vitest'
import { saleOperationReference } from './operationReference'

describe('COVI sale operation reference', () => {
  it('derives a full unique reference from the sale UUID', () => {
    expect(saleOperationReference('e3dd4791-36a0-432d-8bc9-92282d1d4213')).toBe(
      'COVI-E3DD479136A0432D8BC992282D1D4213',
    )
  })
  it('rejects absent or malformed IDs instead of inventing a reference', () => {
    expect(saleOperationReference(null)).toBeNull()
    expect(saleOperationReference('no-sale')).toBeNull()
  })
  it('does not conflate distinct UUIDs having the same prefix', () => {
    expect(saleOperationReference('e3dd4791-36a0-432d-8bc9-92282d1d4213')).not.toBe(
      saleOperationReference('e3dd4791-36a0-432d-8bc9-92282d1d4214'),
    )
  })
})
