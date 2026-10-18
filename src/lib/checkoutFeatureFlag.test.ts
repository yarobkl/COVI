import { describe, expect, it } from 'vitest'
import { checkoutFeatureConfigured } from './checkoutFeatureFlag'

const url = 'https://covi-test.supabase.co'
const publishable = 'sb_publishable_testing_only_public_key_123'

function jwt(role: string): string {
  const header = btoa(JSON.stringify({ alg: 'HS256', typ: 'JWT' }))
  const payload = btoa(JSON.stringify({ role }))
  return header + '.' + payload + '.synthetic_signature'
}

describe('experimental checkout deployment gate', () => {
  it('remains disabled by default or when either explicit target setting is missing', () => {
    expect(checkoutFeatureConfigured(undefined, undefined, undefined)).toBe(false)
    expect(checkoutFeatureConfigured('false', url, publishable)).toBe(false)
    expect(checkoutFeatureConfigured('true', undefined, publishable)).toBe(false)
    expect(checkoutFeatureConfigured('true', url, undefined)).toBe(false)
  })

  it('accepts only explicit secure endpoints and a public Supabase credential', () => {
    expect(checkoutFeatureConfigured('true', url, publishable)).toBe(true)
    expect(checkoutFeatureConfigured('true', 'http://localhost:54321/', publishable)).toBe(true)
    expect(checkoutFeatureConfigured('true', 'http://127.0.0.1:54321/', publishable)).toBe(true)
    expect(checkoutFeatureConfigured('true', url, jwt('anon'))).toBe(true)
  })

  it('rejects nonlocal HTTP, embedded credentials, paths and query parameters', () => {
    for (const invalidUrl of [
      'http://covi-test.supabase.co',
      'https://user:password@covi-test.supabase.co',
      'https://covi-test.supabase.co/rest/v1',
      'https://covi-test.supabase.co/?token=secret',
      'not-a-url',
    ]) {
      expect(checkoutFeatureConfigured('true', invalidUrl, publishable)).toBe(false)
    }
  })

  it('never enables experimental checkout with a secret or service_role JWT', () => {
    expect(checkoutFeatureConfigured('true', url, 'sb_secret_must_never_be_public_123456')).toBe(
      false,
    )
    expect(checkoutFeatureConfigured('true', url, jwt('service_role'))).toBe(false)
    expect(checkoutFeatureConfigured('true', url, 'short')).toBe(false)
    expect(checkoutFeatureConfigured('true', url, 'eyJ.invalid.not-json')).toBe(false)
  })
})
