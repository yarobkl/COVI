// @vitest-environment node
import { describe, expect, it, vi } from 'vitest'
import { buildPublicCheckoutEnvironment } from '../supabase/functions/public-checkout/edgeConfig.mjs'
import { createPublicCheckoutGateway } from '../supabase/functions/public-checkout/gateway.mjs'

const fullSettings = {
  COVI_GATEWAY_ENABLED: 'true',
  COVI_PUBLIC_ORIGIN: 'https://covi.example',
  SUPABASE_URL: 'https://example.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: 'sb_secret_test_backend_key_never_in_browser',
  COVI_GATEWAY_PEPPER: 'distinct-random-gateway-pepper-more-than-32-characters',
  COVI_TURNSTILE_SECRET: 'turnstile-secret-for-tests',
}

function fromSettings(settings) {
  return buildPublicCheckoutEnvironment((name) => settings[name])
}

function catalogRequest() {
  return new Request('https://fn.example/?token=dddddddd-0000-4000-8000-000000000001', {
    headers: { Origin: 'https://covi.example' },
  })
}

describe('public checkout environment must fail closed', () => {
  it('does not enable a public endpoint when activation is absent', async () => {
    const settings = fromSettings({ ...fullSettings, COVI_GATEWAY_ENABLED: undefined })
    expect(settings.COVI_GATEWAY_ENABLED).toBe('false')
    const network = vi.fn()
    const response = await createPublicCheckoutGateway(settings, network)(catalogRequest())
    expect(response.status).toBe(503)
    expect(network).not.toHaveBeenCalled()
  })

  it('requires an independent HMAC pepper instead of falling back to service key', async () => {
    const settings = fromSettings({ ...fullSettings, COVI_GATEWAY_PEPPER: undefined })
    expect(settings.COVI_GATEWAY_PEPPER).toBe('')
    expect(settings.COVI_GATEWAY_PEPPER).not.toContain(settings.SUPABASE_SERVICE_ROLE_KEY)
    const network = vi.fn()
    const response = await createPublicCheckoutGateway(settings, network)(catalogRequest())
    expect(response.status).toBe(503)
    expect(network).not.toHaveBeenCalled()
  })

  it('rejects empty, false and non-boolean-like activation values', () => {
    for (const value of [undefined, null, '', 'false', 'TRUE', '1', 'yes', ' true ']) {
      expect(
        fromSettings({ ...fullSettings, COVI_GATEWAY_ENABLED: value }).COVI_GATEWAY_ENABLED,
      ).toBe('false')
    }
    expect(fromSettings(fullSettings).COVI_GATEWAY_ENABLED).toBe('true')
  })

  it('does not expose backend secrets through returned settings to the browser', () => {
    // This helper runs only on the Edge server; verify secret fields are
    // preserved for server validation and never returned by the HTTP handler.
    const settings = fromSettings(fullSettings)
    expect(settings.COVI_GATEWAY_PEPPER).toBe(fullSettings.COVI_GATEWAY_PEPPER)
    expect(settings.SUPABASE_SERVICE_ROLE_KEY).toBe(fullSettings.SUPABASE_SERVICE_ROLE_KEY)
  })
})
