// @vitest-environment node
import { describe, expect, it, vi } from 'vitest'
import {
  createPublicCheckoutGateway,
  decodeReferenceJpeg,
  parseOrder,
} from '../supabase/functions/public-checkout/gateway.mjs'

const env = {
  COVI_GATEWAY_ENABLED: 'true',
  COVI_PUBLIC_ORIGIN: 'https://covi.example, https://preview.covi.example',
  SUPABASE_URL: 'https://example.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: 'sb_secret_test_backend_key_never_in_browser',
  COVI_GATEWAY_PEPPER: 'gateway-pepper-with-at-least-32-random-characters',
  COVI_TURNSTILE_SECRET: 'turnstile-secret-for-tests',
}
const token = 'dddddddd-0000-4000-8000-000000000001'
const productId = 'aaaaaaaa-0000-4000-8000-000000000001'
const orderId = 'bbbbbbbb-0000-4000-8000-000000000001'
const shopId = '11111111-1111-4111-8111-111111111111'
const trackingToken = 'eeeeeeee-0000-4000-8000-000000000001'
// Minimal 2x2 JPEG-like fixture with an actual SOF frame + SOS scan.
// This exercises header validation only: pixels are not decoded by the gateway.
const bytesForJpeg = () =>
  Uint8Array.from([
    0xff, 0xd8, 0xff, 0xe0, 0x00, 0x04, 0x00, 0x00, 0xff, 0xc0, 0x00, 0x0b, 0x08, 0x00, 0x02, 0x00,
    0x02, 0x01, 0x01, 0x11, 0x00, 0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3f, 0x00, 0x10,
    0x20, 0x30, 0x40, 0xff, 0xd9,
  ])
const jpegData = (bytes) => 'data:image/jpeg;base64,' + btoa(String.fromCharCode(...bytes))
const jpeg = jpegData(bytesForJpeg())

const origin = { Origin: 'https://covi.example' }
const order = {
  token,
  operationId: '77770000-0000-4000-8000-000000000001',
  channel: 'qr',
  customerName: 'Awa',
  phone: '+242 06 000 00 00',
  fulfillment: 'pickup',
  paymentMethod: 'mobile_money',
  lines: [
    { productId, quantity: 2, proposedUnitPriceXaf: 9000 },
    { description: 'ceinture', quantity: 1 },
  ],
  challenge: 'valid-turnstile-token',
}

function backend({
  quota = true,
  captcha = true,
  hostname = 'covi.example',
  action = 'covi_order',
  submitError = null,
  uploadStatus = 200,
} = {}) {
  const calls = []
  const transport = vi.fn(async (url, init) => {
    const address = String(url)
    calls.push({ address, init })
    if (address.includes('siteverify'))
      return Response.json({ success: captcha, hostname, ...(action === null ? {} : { action }) })
    if (address.endsWith('consume_public_order_quota')) return Response.json(quota)
    if (address.endsWith('get_public_order_catalog'))
      return Response.json({
        shopName: 'Boutique',
        showCatalog: true,
        products: [{ id: productId }],
      })
    if (address.endsWith('get_public_order_status'))
      return Response.json({ status: 'new', reference: 'C-ABC123' })
    if (address.endsWith('submit_public_order')) {
      if (submitError) return Response.json({ message: submitError }, { status: 400 })
      return Response.json({
        orderId,
        shopId,
        trackingToken,
        reference: 'C-ABC123',
        status: 'new',
        amountXaf: 19000,
      })
    }
    if (address.endsWith('attach_public_order_reference'))
      return Response.json(`${shopId}/${orderId}/reference.jpg`)
    if (address.includes('/storage/v1/object/covi-order-references/'))
      return Response.json({ Key: 'x' }, { status: uploadStatus })
    return Response.json({ message: 'unexpected' }, { status: 500 })
  })
  return { calls, transport }
}

const post = (body, headers = origin) =>
  new Request('https://fn.example/public-checkout', {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: JSON.stringify(body),
  })

describe('passerelle publique des commandes', () => {
  it('refuse une origine inconnue', async () => {
    const { transport } = backend()
    const res = await createPublicCheckoutGateway(
      env,
      transport,
    )(post(order, { Origin: 'https://evil.example' }))
    expect(res.status).toBe(403)
    expect(transport).not.toHaveBeenCalled()
  })

  it('reste fermée tant que la passerelle n’est pas activée', async () => {
    const { transport } = backend()
    const gateway = createPublicCheckoutGateway(
      { ...env, COVI_GATEWAY_ENABLED: 'false' },
      transport,
    )
    const res = await gateway(
      new Request(`https://fn.example/?token=${token}`, { headers: origin }),
    )
    expect(res.status).toBe(503)
  })

  it('sert le catalogue mais refuse les dépôts sans clé secrète Turnstile', async () => {
    const { transport, calls } = backend()
    const gateway = createPublicCheckoutGateway({ ...env, COVI_TURNSTILE_SECRET: '' }, transport)
    const catalog = await gateway(
      new Request(`https://fn.example/?token=${token}`, { headers: origin }),
    )
    expect(catalog.status).toBe(200)
    expect((await catalog.json()).ordersOpen).toBe(false)
    const res = await gateway(post(order))
    expect(res.status).toBe(503)
    expect(calls.some((c) => c.address.endsWith('submit_public_order'))).toBe(false)
  })

  it('dépose une demande après anti-robot et quotas, sans exposer la clé serveur', async () => {
    const { transport, calls } = backend()
    const res = await createPublicCheckoutGateway(
      env,
      transport,
    )(post({ ...order, referenceImage: jpeg }))
    expect(res.status).toBe(200)
    const data = await res.json()
    expect(data).toMatchObject({
      reference: 'C-ABC123',
      trackingToken,
      status: 'new',
      photoSaved: true,
    })
    expect(JSON.stringify(data)).not.toContain(env.SUPABASE_SERVICE_ROLE_KEY)
    const submit = calls.find((c) => c.address.endsWith('submit_public_order'))
    expect(JSON.parse(submit.init.body).p_lines).toEqual([
      { productId, quantity: 2, proposedUnitPriceXaf: 9000 },
      { description: 'ceinture', quantity: 1 },
    ])
    // Turnstile vérifié avant tout dépôt.
    expect(calls.findIndex((c) => c.address.includes('siteverify'))).toBeLessThan(
      calls.findIndex((c) => c.address.endsWith('submit_public_order')),
    )
  })

  it('n’annonce pas une photo sauvée quand le stockage renvoie une erreur HTTP 400', async () => {
    const { transport } = backend({ uploadStatus: 400 })
    const result = await createPublicCheckoutGateway(
      env,
      transport,
    )(post({ ...order, referenceImage: jpeg }))
    expect(result.status).toBe(200)
    expect((await result.json()).photoSaved).toBe(false)
  })

  it('refuse un anti-robot invalide ou émis pour un autre domaine', async () => {
    for (const options of [{ captcha: false }, { hostname: 'evil.example' }]) {
      const { transport, calls } = backend(options)
      const res = await createPublicCheckoutGateway(env, transport)(post(order))
      expect(res.status).toBe(403)
      expect(calls.some((c) => c.address.endsWith('submit_public_order'))).toBe(false)
    }
  })

  it('refuse un jeton Turnstile sans action ou émis pour une autre action', async () => {
    for (const action of [null, 'profile', 'another_action']) {
      const { transport, calls } = backend({ action })
      const response = await createPublicCheckoutGateway(env, transport)(post(order))
      expect(response.status).toBe(403)
      expect(calls.some((call) => call.address.endsWith('submit_public_order'))).toBe(false)
    }
  })

  it('applique les quotas', async () => {
    const { transport } = backend({ quota: false })
    const res = await createPublicCheckoutGateway(env, transport)(post(order))
    expect(res.status).toBe(429)
  })

  it('traduit les refus de stock sans détail technique', async () => {
    const { transport } = backend({ submitError: 'Insufficient stock' })
    const res = await createPublicCheckoutGateway(env, transport)(post(order))
    expect(res.status).toBe(409)
    expect((await res.json()).error).toMatch(/stock/)
  })

  it('suit une commande avec son jeton de suivi', async () => {
    const { transport } = backend()
    const res = await createPublicCheckoutGateway(
      env,
      transport,
    )(new Request(`https://fn.example/?tracking=${trackingToken}`, { headers: origin }))
    expect(res.status).toBe(200)
    expect((await res.json()).reference).toBe('C-ABC123')
  })
})

describe('validation des demandes', () => {
  it('rejette les champs invalides', () => {
    expect(parseOrder(order)).not.toBeNull()
    expect(parseOrder({ ...order, paymentMethod: 'bitcoin' })).toBeNull()
    expect(parseOrder({ ...order, phone: 'abc' })).toBeNull()
    expect(parseOrder({ ...order, customerName: '' })).toBeNull()
    expect(parseOrder({ ...order, fulfillment: 'delivery' })).toBeNull()
    expect(
      parseOrder({ ...order, fulfillment: 'delivery', deliveryAddress: 'Moungali' }),
    ).not.toBeNull()
    expect(parseOrder({ ...order, lines: [] })).toBeNull()
    expect(parseOrder({ ...order, lines: [{ productId, quantity: 21 }] })).toBeNull()
    expect(
      parseOrder({
        ...order,
        lines: [
          { productId, quantity: 1 },
          { productId, quantity: 1 },
        ],
      }),
    ).toBeNull()
    expect(parseOrder({ ...order, lines: [{ quantity: 1 }] })).toBeNull()
    expect(parseOrder({ ...order, referenceImage: 'data:image/png;base64,AAAA' })).toBeNull()
  })
})

describe('fichiers JPEG envoyés par un client', () => {
  it('accepte une trame JPEG avec dimensions bornées, sans métadonnées', () => {
    expect(decodeReferenceJpeg(jpeg)).not.toBeNull()
  })

  it('rejette un faux JPEG avec uniquement les octets de début et de fin', () => {
    const fake = jpegData(Uint8Array.from([255, 216, 255, 1, 2, 3, 255, 217]))
    expect(decodeReferenceJpeg(fake)).toBeNull()
    expect(parseOrder({ ...order, referenceImage: fake })).toBeNull()
  })

  it('rejette EXIF, IPTC et commentaires qui peuvent exposer des métadonnées', () => {
    for (const marker of [0xe1, 0xed, 0xfe]) {
      const source = bytesForJpeg()
      const malicious = Uint8Array.from([
        ...source.slice(0, 2),
        0xff,
        marker,
        0x00,
        0x04,
        0x00,
        0x00,
        ...source.slice(2),
      ])
      expect(decodeReferenceJpeg(jpegData(malicious))).toBeNull()
    }
  })

  it('rejette les dimensions excessives malgré un petit fichier compressé', () => {
    const huge = bytesForJpeg()
    // SOF width is at bytes 15-16; 4097 exceeds the configured dimension cap.
    huge[15] = 0x10
    huge[16] = 0x01
    expect(decodeReferenceJpeg(jpegData(huge))).toBeNull()
  })
})
