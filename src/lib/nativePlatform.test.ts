import { afterEach, describe, expect, it } from 'vitest'
import { isCoviIosApp } from './nativePlatform'

const bridge = (value: unknown) => {
  Object.defineProperty(window, 'Capacitor', {
    configurable: true,
    writable: true,
    value,
  })
}

afterEach(() => bridge(undefined))

describe('Capacitor iOS isolation', () => {
  it('does not change the Safari or Vercel website', () => {
    bridge(undefined)
    expect(isCoviIosApp()).toBe(false)
  })

  it('enables the native experience in the genuine iOS runtime', () => {
    bridge({ getPlatform: () => 'ios', isNativePlatform: () => true })
    expect(isCoviIosApp()).toBe(true)
  })

  it('does not activate on Android or a non-native web view', () => {
    bridge({ getPlatform: () => 'android', isNativePlatform: () => true })
    expect(isCoviIosApp()).toBe(false)
    bridge({ getPlatform: () => 'ios', isNativePlatform: () => false })
    expect(isCoviIosApp()).toBe(false)
  })
})
