import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  chooseShop,
  forgetActiveShop,
  readActiveShop,
  readActiveShopCopy,
  rememberActiveShop,
} from './activeShop'

const A = { id: 'shop-a', name: 'Boutique A' }
const B = { id: 'shop-b', name: 'Boutique B' }

beforeEach(() => localStorage.clear())
afterEach(() => vi.restoreAllMocks())

describe('chooseShop', () => {
  it('0 shop: creation', () => {
    expect(chooseShop([], 'shop-a')).toEqual({ kind: 'create' })
  })
  it('1 shop: opened directly, whatever is remembered', () => {
    expect(chooseShop([A], null)).toEqual({ kind: 'open', shop: A })
    expect(chooseShop([A], 'shop-zzz')).toEqual({ kind: 'open', shop: A })
  })
  it('2+ shops: asks when nothing is remembered', () => {
    expect(chooseShop([A, B], null)).toEqual({ kind: 'choose' })
  })
  it('2+ shops: reopens the remembered shop', () => {
    expect(chooseShop([A, B], 'shop-b')).toEqual({ kind: 'open', shop: B })
  })
  it('2+ shops: a remembered shop that no longer exists is never opened: asks', () => {
    expect(chooseShop([A, B], 'shop-deleted')).toEqual({ kind: 'choose' })
  })
})

describe('remembered active shop', () => {
  it('is kept per user under covi:active-shop:<userId>', () => {
    rememberActiveShop('u1', A)
    rememberActiveShop('u2', B)
    expect(readActiveShop('u1')).toBe('shop-a')
    expect(readActiveShop('u2')).toBe('shop-b')
    expect(JSON.parse(localStorage.getItem('covi:active-shop:u1')!)).toEqual(A)
    expect(readActiveShopCopy('u1')).toEqual(A)
    expect(readActiveShop('u3')).toBeNull()
  })
  it('reads a bare id (no copy) and forgets', () => {
    localStorage.setItem('covi:active-shop:u1', 'shop-a')
    expect(readActiveShop('u1')).toBe('shop-a')
    expect(readActiveShopCopy('u1')).toBeNull()
    forgetActiveShop('u1')
    expect(readActiveShop('u1')).toBeNull()
  })
  it('ignores a damaged value', () => {
    localStorage.setItem('covi:active-shop:u1', '{pas du json')
    expect(readActiveShop('u1')).toBeNull()
  })
  it('never throws when storage is blocked', () => {
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('SecurityError')
    })
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('QuotaExceededError')
    })
    vi.spyOn(Storage.prototype, 'removeItem').mockImplementation(() => {
      throw new Error('SecurityError')
    })
    expect(() => rememberActiveShop('u1', A)).not.toThrow()
    expect(readActiveShop('u1')).toBeNull()
    expect(() => forgetActiveShop('u1')).not.toThrow()
  })
})
