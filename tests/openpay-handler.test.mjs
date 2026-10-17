// @vitest-environment node
import { describe, expect, it } from 'vitest'
import {
  coviStatus,
  createOpenPayHandler,
  normalizeCongoPhone,
} from '../supabase/functions/openpay/handler.mjs'

const env = {
  COVI_OPENPAY_ENABLED: 'true',
  COVI_PUBLIC_ORIGIN: 'https://covi.example',
  SUPABASE_URL: 'https://example.supabase.co',
  SUPABASE_ANON_KEY: 'anon-key',
  SUPABASE_SERVICE_ROLE_KEY: 'sb_secret_service_key_never_in_browser',
  OPENPAY_API_BASE: 'https://api.openpay.test',
}
const orderId = 'bbbbbbbb-0000-4000-8000-000000000001'
const paymentId = 'cccccccc-0000-4000-8000-000000000001'
const jwt = 'aaa.bbb.ccc'
const ctx = {
  paymentId,
  status: 'requested',
  reference: null,
  provider: 'MTN',
  phone: '242066000000',
  amount: 10000,
  orderId,
  orderReference: 'C-ABC123',
  customerName: 'Awa',
  apiKey: 'opk_shop_key',
}

/** Faux Supabase + faux OpenPay ; enregistre chaque appel. */
function backend({
  openpayStatus = 'success',
  openpayAmount = '10000',
  initiate = 200,
  context = ctx,
} = {}) {
  const calls = []
  let current = { ...context }
  const fetchImpl = async (input, init = {}) => {
    const url = String(input)
    const body = init.body ? JSON.parse(init.body) : null
    calls.push({ url, init, body })
    const ok = (data, status = 200) => new Response(JSON.stringify(data), { status })
    if (url.endsWith('/rpc/request_order_mobile_payment')) return ok(paymentId)
    if (url.endsWith('/rpc/assert_order_payment_owner')) return ok(true)
    if (url.endsWith('/rpc/openpay_payment_context')) return ok(current)
    if (url.endsWith('/rpc/openpay_payment_by_reference'))
      return ok(body.p_reference === 'OP-1' ? paymentId : null)
    if (url.endsWith('/rpc/record_openpay_status')) {
      current = {
        ...current,
        status: body.p_status,
        reference: body.p_reference ?? current.reference,
      }
      return ok(body.p_status)
    }
    if (url === 'https://api.openpay.test/v1/transaction/payment') {
      return ok(
        initiate === 200 ? { reference: 'OP-1', status: 'success' } : { message: 'refus' },
        initiate,
      )
    }
    if (url === 'https://api.openpay.test/v1/transaction/status/OP-1') {
      return ok({ reference: 'OP-1', status: openpayStatus, amount: openpayAmount })
    }
    return ok({ message: 'unexpected ' + url }, 500)
  }
  return { calls, fetchImpl }
}

const post = (action, body, headers = {}) =>
  new Request('https://example.supabase.co/functions/v1/openpay?action=' + action, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: JSON.stringify(body),
  })
const shop = { Origin: 'https://covi.example', Authorization: 'Bearer ' + jwt }

describe('OpenPay — numéros et statuts', () => {
  it('normalise les numéros congolais', () => {
    expect(normalizeCongoPhone('+242 06 600 00 00')).toBe('242066000000')
    expect(normalizeCongoPhone('06 600 00 00')).toBe('242066000000')
    expect(normalizeCongoPhone('12345')).toBeNull()
  })
  it('« success » seulement pour le montant demandé', () => {
    expect(coviStatus({ status: 'SUCCESS', amount: '10000' }, 10000).status).toBe('success')
    expect(coviStatus({ status: 'success', amount: '1' }, 10000).status).toBe('error')
    expect(coviStatus({ status: 'bizarre' }, 10000).status).toBe('pending')
  })
})

describe('OpenPay — demande de paiement par la boutique', () => {
  it('crée la demande avec la session de la boutique puis appelle OpenPay avec la clé de la boutique', async () => {
    const { calls, fetchImpl } = backend()
    const res = await createOpenPayHandler(
      env,
      fetchImpl,
    )(post('request', { orderId, provider: 'mtn', phone: '06 600 00 00', amount: 10000 }, shop))
    expect(res.status).toBe(200)
    expect(await res.json()).toEqual({ paymentId, status: 'pending', reference: 'OP-1' })
    const first = calls[0]
    expect(first.url).toMatch(/request_order_mobile_payment$/)
    expect(first.init.headers.Authorization).toBe('Bearer ' + jwt)
    expect(first.body).toEqual({
      p_order_id: orderId,
      p_provider: 'MTN',
      p_phone: '242066000000',
      p_amount: 10000,
    })
    const openpay = calls.find((c) => c.url.endsWith('/v1/transaction/payment'))
    expect(openpay.init.headers['XO-API-KEY']).toBe('opk_shop_key')
    expect(openpay.body).toMatchObject({
      amount: 10000,
      payment_phone_number: '242066000000',
      provider: 'MTN',
    })
    // La réponse immédiate « success » d'OpenPay n'est JAMAIS prise pour un paiement reçu.
    const recorded = calls.filter((c) => c.url.endsWith('/rpc/record_openpay_status'))
    expect(recorded.map((c) => c.body.p_status)).toEqual(['pending'])
  })

  it('refuse une autre origine et une requête sans session', async () => {
    const { fetchImpl } = backend()
    const handle = createOpenPayHandler(env, fetchImpl)
    expect(
      (
        await handle(
          post('request', {}, { Origin: 'https://evil.example', Authorization: 'Bearer ' + jwt }),
        )
      ).status,
    ).toBe(403)
    expect((await handle(post('request', {}, { Origin: 'https://covi.example' }))).status).toBe(401)
  })

  it('refuse un numéro invalide sans rien créer', async () => {
    const { calls, fetchImpl } = backend()
    const res = await createOpenPayHandler(
      env,
      fetchImpl,
    )(post('request', { orderId, provider: 'MTN', phone: '123', amount: 10000 }, shop))
    expect(res.status).toBe(400)
    expect(calls).toHaveLength(0)
  })

  it('OpenPay refuse : paiement noté en erreur', async () => {
    const { calls, fetchImpl } = backend({ initiate: 400 })
    const res = await createOpenPayHandler(
      env,
      fetchImpl,
    )(post('request', { orderId, provider: 'AIRTEL', phone: '242056000000', amount: 10000 }, shop))
    expect(res.status).toBe(502)
    const recorded = calls.filter((c) => c.url.endsWith('/rpc/record_openpay_status'))
    expect(recorded.map((c) => c.body.p_status)).toEqual(['error'])
  })

  it('arrêt d’urgence : COVI_OPENPAY_ENABLED=false', async () => {
    const { calls, fetchImpl } = backend()
    const res = await createOpenPayHandler(
      { ...env, COVI_OPENPAY_ENABLED: 'false' },
      fetchImpl,
    )(post('request', { orderId, provider: 'MTN', phone: '066000000', amount: 10000 }, shop))
    expect(res.status).toBe(503)
    expect(calls).toHaveLength(0)
  })
})

describe('OpenPay — callback', () => {
  it('ne croit pas le contenu du callback : relit le statut chez OpenPay', async () => {
    const { calls, fetchImpl } = backend({
      context: { ...ctx, status: 'pending', reference: 'OP-1' },
    })
    const res = await createOpenPayHandler(
      env,
      fetchImpl,
    )(post('callback', { reference: 'OP-1', status: 'success', amount: '10000' }))
    expect(res.status).toBe(200)
    expect(calls.some((c) => c.url.endsWith('/v1/transaction/status/OP-1'))).toBe(true)
    const recorded = calls.filter((c) => c.url.endsWith('/rpc/record_openpay_status'))
    expect(recorded.map((c) => c.body.p_status)).toEqual(['success'])
  })

  it('callback « success » mais OpenPay dit « pending » : reste en attente', async () => {
    const { calls, fetchImpl } = backend({
      openpayStatus: 'pending',
      context: { ...ctx, status: 'pending', reference: 'OP-1' },
    })
    await createOpenPayHandler(
      env,
      fetchImpl,
    )(post('callback', { reference: 'OP-1', status: 'success' }))
    const recorded = calls.filter((c) => c.url.endsWith('/rpc/record_openpay_status'))
    expect(recorded.map((c) => c.body.p_status)).toEqual(['pending'])
  })

  it('montant différent : jamais « success »', async () => {
    const { calls, fetchImpl } = backend({
      openpayAmount: '100',
      context: { ...ctx, status: 'pending', reference: 'OP-1' },
    })
    await createOpenPayHandler(env, fetchImpl)(post('callback', { reference: 'OP-1' }))
    const recorded = calls.filter((c) => c.url.endsWith('/rpc/record_openpay_status'))
    expect(recorded.map((c) => c.body.p_status)).toEqual(['error'])
  })

  it('référence inconnue : ignorée sans appel à OpenPay', async () => {
    const { calls, fetchImpl } = backend()
    const res = await createOpenPayHandler(
      env,
      fetchImpl,
    )(post('callback', { reference: 'INCONNUE' }))
    expect(res.status).toBe(200)
    expect(calls.some((c) => c.url.includes('openpay.test'))).toBe(false)
  })
})
