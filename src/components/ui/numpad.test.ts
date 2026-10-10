import { describe, expect, it } from 'vitest'
import { keyFromKeyboard, lowerBy, MAX_DIGITS, pressKey } from './pricePadLogic'

describe('pressKey', () => {
  it('types digits from nothing and drops leading zeros', () => {
    expect(pressKey(null, '1')).toBe(1)
    expect(pressKey(1, '3')).toBe(13)
    expect(pressKey(null, '0')).toBe(0)
    expect(pressKey(0, '5')).toBe(5)
    expect(pressKey(0, '0')).toBe(0)
  })

  it('adds three zeros at once, but not to an empty price', () => {
    expect(pressKey(13, '000')).toBe(13000)
    expect(pressKey(null, '000')).toBeNull()
    expect(pressKey(0, '000')).toBe(0)
  })

  it('erases the last digit, down to nothing', () => {
    expect(pressKey(13000, 'back')).toBe(1300)
    expect(pressKey(1, 'back')).toBeNull()
    expect(pressKey(null, 'back')).toBeNull()
  })

  it('ignores keys beyond the longest price', () => {
    const longest = Number('9'.repeat(MAX_DIGITS))
    expect(pressKey(longest, '1')).toBe(longest)
    expect(pressKey(1234567, '000')).toBe(1234567)
    expect(pressKey(12345, '000')).toBe(12345000)
  })
})

describe('lowerBy', () => {
  it('lowers the price without going under zero', () => {
    expect(lowerBy(15000, 500)).toBe(14500)
    expect(lowerBy(15000, 1000)).toBe(14000)
    expect(lowerBy(300, 500)).toBe(0)
    expect(lowerBy(null, 1000)).toBe(0)
  })
})

describe('keyFromKeyboard', () => {
  it('maps digits, erasing keys and Enter', () => {
    expect(keyFromKeyboard('7')).toBe('7')
    expect(keyFromKeyboard('Backspace')).toBe('back')
    expect(keyFromKeyboard('Delete')).toBe('back')
    expect(keyFromKeyboard('Enter')).toBe('confirm')
    expect(keyFromKeyboard('a')).toBeNull()
    expect(keyFromKeyboard('F5')).toBeNull()
  })
})
