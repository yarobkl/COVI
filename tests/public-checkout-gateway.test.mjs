// @vitest-environment node
import { describe, expect, it, vi } from 'vitest'
import { createPublicCheckoutGateway } from '../supabase/functions/public-checkout/gateway.mjs'

const env = {
  COVI_GATEWAY_ENABLED: 'true',
  COVI_PUBLIC_ORIGIN: 'https://covi.example',
  SUPABASE_URL: 'https://example.supabase.co',
  COVI_SUPABASE_SECRET_KEY: 'sb_secret_test_backend_never_in_browser',
  COVI_GATEWAY_PEPPER: 'gateway-pepper-with-at-least-32-random-characters',
  COVI_TURNSTILE_SECRET: 'turnstile-secret-key-for-the-test-only',
}
const token = 'dddddddd-0000-4000-8000-000000000001'
const operationId = '77770000-0000-4000-8000-000000000001'
const categoryId = 'aaaaaaaa-0000-4000-8000-000000000001'
const orderId = 'bbbbbbbb-0000-4000-8000-000000000001'
const shopId = '11111111-1111-4111-8111-111111111111'
// Actual 2×2 canvas-like JPEG, without EXIF. Its SOF/SOS segments are valid.
const validImage =
  'data:image/jpeg;base64,' +
  [
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHR',
    'ofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgy',
    'IRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMj',
    'L/wAARCAACAAIDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL',
    '/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0f',
    'AkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1',
    'dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1N',
    'XW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQF',
    'BgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRob',
    'HBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVm',
    'Z2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExc',
    'bHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD3+iiigD//',
    '2Q==',
  ].join('')
const trackingToken = 'eeeeeeee-0000-4000-8000-000000000001'
const origin = { Origin: 'https://covi.example' }
const order = {
  token,
  channel: 'qr',
  operationId,
  fulfillment: 'pickup',
  lines: [{ categoryId, quantity: 2, unitPriceXaf: 3500 }],
  challenge: 'valid-turnstile-token-for-test',
}

function fakeBackend({
  quota = true,
  captcha = true,
  hostname = 'covi.example',
  action = 'covi_checkout',
  orderStatus = 'submitted',
} = {}) {
  const calls = []
  const transport = vi.fn(async (url, init) => {
    const address = String(url)
    calls.push({ address, init })
    if (address.includes('siteverify')) {
      return Response.json({
        success: captcha,
        hostname,
        action,
      })
    }
    if (address.endsWith('consume_checkout_gateway_quota')) return Response.json(quota)
    if (address.endsWith('get_checkout_public_catalog')) {
      return Response.json({
        shopName: 'La boutique',
        categories: [{ id: categoryId, label: 'Robes' }],
      })
    }
    if (address.endsWith('submit_checkout_public_order')) {
      return Response.json({ orderId, shopId, trackingToken, status: orderStatus, amountXaf: 7000 })
    }
    if (address.includes('/storage/v1/object/covi-order-references/')) {
      return Response.json({ Key: 'private-image' })
    }
    if (address.endsWith('attach_checkout_public_reference')) return Response.json(true)
    if (address.endsWith('get_checkout_guest_status')) {
      return Response.json({
        shopName: 'La boutique',
        orderId,
        status: 'submitted',
        amountXaf: 7000,
      })
    }
    throw new Error('Unexpected endpoint')
  })
  return { transport, calls }
}

function guestPost(input = order, extraHeaders = {}) {
  return new Request('https://example.supabase.co/functions/v1/public-checkout', {
    method: 'POST',
    headers: { ...origin, 'Content-Type': 'application/json', ...extraHeaders },
    body: JSON.stringify(input),
  })
}

describe('isolated QR/social gateway', () => {
  it('fails closed when disabled or missing secrets, and never accesses Supabase', async () => {
    const { transport } = fakeBackend()
    const disabled = createPublicCheckoutGateway(
      { ...env, COVI_GATEWAY_ENABLED: 'false' },
      transport,
    )
    expect((await disabled(guestPost())).status).toBe(503)
    const missing = createPublicCheckoutGateway({ ...env, COVI_TURNSTILE_SECRET: '' }, transport)
    expect((await missing(guestPost())).status).toBe(503)
    expect(transport).not.toHaveBeenCalled()
  })

  it('sets a deadline on every privileged external request, including uploads and Turnstile', async () => {
    const { transport, calls } = fakeBackend()
    const gateway = createPublicCheckoutGateway(env, transport)
    const result = await gateway(guestPost({ ...order, referenceImage: validImage }))
    expect(result.status).toBe(200)

    const privileged = calls.filter(
      (call) =>
        call.address.includes('/rest/v1/rpc/') ||
        call.address.includes('/storage/v1/object/') ||
        call.address.includes('siteverify'),
    )
    expect(privileged.length).toBeGreaterThan(4)
    expect(privileged.every((call) => call.init.signal instanceof AbortSignal)).toBe(true)
    expect(privileged.every((call) => !call.init.signal.aborted)).toBe(true)
  })

  it('fails closed when the privileged database waits indefinitely', async () => {
    // Reduce the timeout only inside this isolated test; production deadlines
    // remain bounded by the gateway's fixed code constants.
    const original = AbortSignal.timeout.bind(AbortSignal)
    const spy = vi.spyOn(AbortSignal, 'timeout').mockImplementation(() => original(20))
    try {
      const neverResponds = vi.fn(
        (_url, init) =>
          new Promise((_resolve, reject) => {
            init.signal.addEventListener('abort', () => reject(new Error('upstream aborted')), {
              once: true,
            })
          }),
      )
      const gateway = createPublicCheckoutGateway(env, neverResponds)
      const result = await gateway(guestPost())
      expect(result.status).toBe(503)
      expect(await result.json()).toEqual({
        error: 'Service temporairement indisponible.',
      })
      expect(neverResponds).toHaveBeenCalledTimes(1)
      expect(neverResponds.mock.calls[0][1].signal.aborted).toBe(true)
    } finally {
      spy.mockRestore()
    }
  })

  it('rejects foreign origins without reflecting permissive CORS', async () => {
    const { transport } = fakeBackend()
    const request = guestPost(order, { Origin: 'https://attacker.example' })
    const result = await createPublicCheckoutGateway(env, transport)(request)
    expect(result.status).toBe(403)
    expect(result.headers.get('access-control-allow-origin')).toBeNull()
    expect(transport).not.toHaveBeenCalled()
  })

  it('serves only public categories with global and scoped quotas; no client secret', async () => {
    const { transport, calls } = fakeBackend()
    const request = new Request(
      'https://example.supabase.co/functions/v1/public-checkout?token=' + token,
      { headers: origin },
    )
    const result = await createPublicCheckoutGateway(env, transport)(request)
    expect(result.status).toBe(200)
    const catalog = await result.json()
    expect(catalog.categories).toEqual([{ id: categoryId, label: 'Robes' }])
    expect(result.headers.get('cache-control')).toBe('no-store')
    expect(calls.filter((call) => call.address.includes('gateway_quota'))).toHaveLength(3)
    expect(JSON.stringify(catalog)).not.toContain(env.COVI_SUPABASE_SECRET_KEY)
  })

  it('shares global and source ceilings across different guessed tokens', async () => {
    const { transport, calls } = fakeBackend()
    const gateway = createPublicCheckoutGateway(env, transport)
    const guestUrl = (t, ip) =>
      new Request('https://example.supabase.co/functions/v1/public-checkout?token=' + t, {
        headers: { ...origin, 'x-forwarded-for': ip },
      })
    const secondToken = 'ffffffff-0000-4000-8000-000000000002'
    expect((await gateway(guestUrl(token, '192.0.2.10'))).status).toBe(200)
    expect((await gateway(guestUrl(secondToken, '192.0.2.10'))).status).toBe(200)
    expect((await gateway(guestUrl(secondToken, '192.0.2.11'))).status).toBe(200)

    const quotas = calls
      .filter((call) => call.address.endsWith('consume_checkout_gateway_quota'))
      .map((call) => JSON.parse(call.init.body))
    const global = quotas.filter((call) => call.p_kind === 'catalog_global_minute')
    const source = quotas.filter((call) => call.p_kind === 'catalog_source_minute')
    const links = quotas.filter((call) => call.p_kind === 'catalog_link_minute')
    expect(global).toHaveLength(3)
    expect(new Set(global.map((call) => call.p_digest)).size).toBe(1)
    expect(source).toHaveLength(3)
    expect(source[0].p_digest).toBe(source[1].p_digest)
    expect(source[0].p_digest).not.toBe(source[2].p_digest)
    expect(links[0].p_digest).not.toBe(links[1].p_digest)
    expect(links[1].p_digest).toBe(links[2].p_digest)
  })

  it('applies one global ceiling even when forged proxy IP headers change', async () => {
    const { transport, calls } = fakeBackend()
    const gateway = createPublicCheckoutGateway(env, transport)
    for (const ip of ['198.51.100.4', '203.0.113.88']) {
      expect(
        (
          await gateway(
            guestPost(order, {
              'x-forwarded-for': ip,
            }),
          )
        ).status,
      ).toBe(200)
    }
    const quotas = calls
      .filter((call) => call.address.endsWith('consume_checkout_gateway_quota'))
      .map((call) => JSON.parse(call.init.body))
    const globals = quotas.filter((call) => call.p_kind === 'order_global_minute')
    expect(globals).toHaveLength(2)
    expect(globals[0].p_digest).toBe(globals[1].p_digest)
  })

  it('uses legacy service-role bearer headers only for JWT keys', async () => {
    const legacy = 'eyJ' + 'legacy-test-service-role-token-example'
    const { transport, calls } = fakeBackend()
    const request = new Request(
      'https://example.supabase.co/functions/v1/public-checkout?token=' + token,
      { headers: origin },
    )
    const response = await createPublicCheckoutGateway(
      { ...env, COVI_SUPABASE_SECRET_KEY: legacy },
      transport,
    )(request)
    expect(response.status).toBe(200)
    const backendCalls = calls.filter((c) => c.address.includes('/rest/v1/rpc/'))
    expect(backendCalls.length).toBeGreaterThan(0)
    expect(backendCalls.every((c) => c.init.headers.Authorization === 'Bearer ' + legacy)).toBe(
      true,
    )
    const other = fakeBackend()
    const opaqueResponse = await createPublicCheckoutGateway(env, other.transport)(request)
    expect(opaqueResponse.status).toBe(200)
    expect(other.calls.every((c) => !c.init.headers?.Authorization)).toBe(true)
  })

  it('checks a single-use anti-robot challenge before saving an order', async () => {
    const { transport, calls } = fakeBackend()
    const result = await createPublicCheckoutGateway(env, transport)(guestPost())
    expect(result.status).toBe(200)
    expect(await result.json()).toEqual({
      orderId,
      trackingToken,
      status: 'submitted',
      amountXaf: 7000,
    })
    const rpc = calls.find((c) => c.address.includes('submit_checkout_public_order'))
    expect(rpc).toBeTruthy()
    const payload = JSON.parse(rpc.init.body)
    expect(payload.p_lines).toEqual(order.lines)
    expect(payload.p_channel).toBe('qr')
    expect(payload.p_customer_phone).toBeNull()
    expect(calls.filter((c) => c.address.includes('gateway_quota'))).toHaveLength(4)
    expect(calls.some((c) => c.address.includes('siteverify'))).toBe(true)
  })

  it('does not save when challenge failed or wrong hostname/action', async () => {
    const { transport, calls } = fakeBackend({ captcha: false })
    const result = await createPublicCheckoutGateway(env, transport)(guestPost())
    expect(result.status).toBe(403)
    expect(calls.some((c) => c.address.includes('submit_checkout_public_order'))).toBe(false)
  })

  it('rejects a challenge for the wrong hostname or action, before link-wide quota', async () => {
    for (const settings of [{ hostname: 'attacker.example' }, { action: 'other_action' }]) {
      const { transport, calls } = fakeBackend(settings)
      const result = await createPublicCheckoutGateway(env, transport)(guestPost())
      expect(result.status).toBe(403)
      expect(calls.some((c) => c.address.includes('submit_checkout_public_order'))).toBe(false)
      expect(
        calls.some(
          (c) =>
            c.address.includes('gateway_quota') &&
            JSON.parse(c.init.body).p_kind === 'order_link_minute',
        ),
      ).toBe(false)
    }
  })

  it('returns the existing request status after a legitimate network retry', async () => {
    const { transport } = fakeBackend({ orderStatus: 'approved' })
    const result = await createPublicCheckoutGateway(env, transport)(guestPost())
    expect(result.status).toBe(200)
    expect((await result.json()).status).toBe('approved')
  })

  it('stops source flooding before expensive external verification', async () => {
    const { transport, calls } = fakeBackend({ quota: false })
    const result = await createPublicCheckoutGateway(env, transport)(guestPost())
    expect(result.status).toBe(429)
    expect(calls.some((c) => c.address.includes('siteverify'))).toBe(false)
  })

  it('rejects price manipulation, bad quantities and delivery without phone', async () => {
    const { transport } = fakeBackend()
    const gateway = createPublicCheckoutGateway(env, transport)
    expect(
      (await gateway(guestPost({ ...order, lines: [{ ...order.lines[0], quantity: 21 }] }))).status,
    ).toBe(400)
    expect(
      (await gateway(guestPost({ ...order, lines: [{ ...order.lines[0], unitPriceXaf: -1 }] })))
        .status,
    ).toBe(400)
    expect((await gateway(guestPost({ ...order, fulfillment: 'delivery' }))).status).toBe(400)
    expect(transport).not.toHaveBeenCalled()
  })

  it('enforces JSON-only input and never accepts payment or staff actions', async () => {
    const { transport } = fakeBackend()
    const gateway = createPublicCheckoutGateway(env, transport)
    const bad = new Request('https://example.supabase.co/functions/v1/public-checkout', {
      method: 'POST',
      headers: { ...origin, 'Content-Type': 'text/plain' },
      body: 'anything',
    })
    expect((await gateway(bad)).status).toBe(415)
    const forged = { ...order, action: 'confirm_payment', status: 'paid' }
    const res = await gateway(guestPost(forged))
    expect(res.status).toBe(200)
    const calls = transport.mock.calls
    expect(calls.some(([url]) => String(url).includes('confirm_manual_checkout_payment'))).toBe(
      false,
    )
  })
  it('uses a separate random tracking capability and rate-limited GET, never a payment RPC', async () => {
    const { transport, calls } = fakeBackend()
    const request = new Request(
      'https://example.supabase.co/functions/v1/public-checkout?tracking=' + trackingToken,
      { headers: origin },
    )
    const response = await createPublicCheckoutGateway(env, transport)(request)
    expect(response.status).toBe(200)
    expect(await response.json()).toEqual({
      shopName: 'La boutique',
      orderId,
      status: 'submitted',
      amountXaf: 7000,
    })
    const kinds = calls
      .filter((c) => c.address.includes('consume_checkout_gateway_quota'))
      .map((c) => JSON.parse(c.init.body).p_kind)
    expect(kinds).toEqual(['status_global_minute', 'status_source_minute', 'status_token_minute'])
    expect(calls.some((c) => c.address.includes('get_checkout_guest_status'))).toBe(true)
    expect(calls.some((c) => c.address.includes('confirm_manual_checkout_payment'))).toBe(false)
    expect(calls.some((c) => c.address.includes('siteverify'))).toBe(false)
  })

  it('rejects malformed tracking IDs before any backend access', async () => {
    const { transport } = fakeBackend()
    const response = await createPublicCheckoutGateway(
      env,
      transport,
    )(
      new Request('https://example.supabase.co/functions/v1/public-checkout?tracking=guess', {
        headers: origin,
      }),
    )
    expect(response.status).toBe(400)
    expect(transport).not.toHaveBeenCalled()
  })
  it('uploads an optional social screenshot privately after a valid Turnstile order', async () => {
    const { transport, calls } = fakeBackend()
    const response = await createPublicCheckoutGateway(
      env,
      transport,
    )(guestPost({ ...order, channel: 'social', referenceImage: validImage }))
    expect(response.status).toBe(200)
    const body = await response.json()
    expect(body.trackingToken).toBe(trackingToken)
    expect(body).not.toHaveProperty('shopId')
    expect(body).not.toHaveProperty('referenceImage')
    const upload = calls.find((call) => call.address.includes('/storage/v1/object/'))
    expect(upload.address).toContain(shopId + '/' + orderId + '/reference.jpg')
    expect(upload.init.headers['Content-Type']).toBe('image/jpeg')
    expect(upload.init.headers['x-upsert']).toBe('false')
    expect(upload.init.body).toBeInstanceOf(Uint8Array)
    const attach = calls.find((call) => call.address.endsWith('attach_checkout_public_reference'))
    expect(JSON.parse(attach.init.body)).toEqual({
      p_token: token,
      p_order_id: orderId,
      p_operation_id: operationId,
      p_image_path: shopId + '/' + orderId + '/reference.jpg',
    })
    expect(calls.findIndex((call) => call.address.includes('siteverify'))).toBeLessThan(
      calls.findIndex((call) => call.address.includes('/storage/v1/object/')),
    )
  })

  it('rejects fake, oversized, and remote reference images before any network operation', async () => {
    const { transport } = fakeBackend()
    const gateway = createPublicCheckoutGateway(env, transport)
    for (const referenceImage of [
      'https://example.com/photo.jpg',
      'data:image/jpeg;base64,AAAA',
      'data:text/html;base64,PHNjcmlwdD4=',
      'data:image/jpeg;base64,' + 'A'.repeat(460000),
    ]) {
      const response = await gateway(guestPost({ ...order, referenceImage }))
      expect(response.status).toBe(400)
    }
    expect(transport).not.toHaveBeenCalled()
  })

  it('refuses JPEG impostors, oversized image dimensions and metadata-bearing files', async () => {
    const { transport } = fakeBackend()
    const gateway = createPublicCheckoutGateway(env, transport)
    const original = Uint8Array.from(atob(validImage.split(',')[1]), (x) => x.charCodeAt(0))
    const asUri = (bytes) => 'data:image/jpeg;base64,' + btoa(String.fromCharCode(...bytes))

    const sof = original.findIndex((v, i) => v === 0xff && original[i + 1] === 0xc0)
    expect(sof).toBeGreaterThan(0)
    const giant = original.slice()
    // SOF0 width: 4097px, beyond server display limits.
    giant[sof + 7] = 0x10
    giant[sof + 8] = 0x01

    const exif = new Uint8Array(original.length + 10)
    exif.set(original.slice(0, 2))
    exif.set([0xff, 0xe1, 0, 8, 69, 120, 105, 102, 0, 0], 2)
    exif.set(original.slice(2), 12)

    for (const referenceImage of [
      'data:image/jpeg;base64,' + btoa(String.fromCharCode(255, 216, 255, 1, 2, 3, 255, 217)),
      asUri(giant),
      asUri(exif),
    ]) {
      const response = await gateway(guestPost({ ...order, referenceImage }))
      expect(response.status).toBe(400)
    }
    expect(transport).not.toHaveBeenCalled()
  })

  it('never uploads a screenshot if bot verification fails', async () => {
    const { transport, calls } = fakeBackend({ captcha: false })
    const result = await createPublicCheckoutGateway(
      env,
      transport,
    )(guestPost({ ...order, referenceImage: validImage }))
    expect(result.status).toBe(403)
    expect(calls.some((call) => call.address.includes('/storage/v1/object/'))).toBe(false)
  })
})
