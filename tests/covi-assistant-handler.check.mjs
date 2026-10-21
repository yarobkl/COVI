import assert from 'node:assert/strict'
import { test } from 'node:test'
import {
  createAssistantHandler,
  retailFacts,
  normalizeChatHistory,
} from '../supabase/functions/covi-assistant/handler.mjs'

const shopId = '11111111-1111-4111-8111-111111111111'
const userId = '22222222-2222-4222-8222-222222222222'
const api = 'https://db.example.test'
const env = {
  SUPABASE_URL: api,
  SUPABASE_ANON_KEY: 'public-only',
  GEMINI_API_KEY: 'private',
  GEMINI_MODEL: 'gemini-2.5-flash',
  COVI_AI_ENABLED: 'true',
  COVI_AI_ALLOWED_ORIGINS: 'https://covi-snowy.vercel.app',
}
const request = (body, headers = {}) =>
  new Request('https://edge.example.test', {
    method: 'POST',
    headers: {
      origin: 'https://covi-snowy.vercel.app',
      authorization: 'Bearer example.jwt.token',
      'content-type': 'application/json',
      ...headers,
    },
    body: JSON.stringify(body),
  })
const response = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json' },
  })

test('refuses non-approved browser origins before any network request', async () => {
  const handler = createAssistantHandler(env, {
    fetchImpl: () => {
      throw new Error('network must not be called')
    },
  })
  const result = await handler(
    request({ shopId, message: 'Mes ventes ?' }, { origin: 'https://evil.invalid' }),
  )
  assert.equal(result.status, 403)
})

test('fails closed when Gemini activation or key is missing', async () => {
  const handler = createAssistantHandler({ ...env, GEMINI_API_KEY: '' })
  const result = await handler(request({ shopId, message: 'Mes ventes ?' }))
  assert.equal(result.status, 503)
})

test('refuses missing JWT and malformed inputs', async () => {
  const handler = createAssistantHandler(env)
  assert.equal(
    (await handler(request({ shopId, message: 'Ventes ?' }, { authorization: '' }))).status,
    401,
  )
  assert.equal((await handler(request({ shopId: 'invalid', message: 'Ventes ?' }))).status, 400)
  assert.equal((await handler(request({ shopId, message: ' ' }))).status, 400)
})

test('refuses another shop before quota or Gemini', async () => {
  let step = 0
  const handler = createAssistantHandler(env, {
    fetchImpl: async (url) => {
      step++
      if (url.includes('/auth/v1/user')) return response({ id: userId })
      if (url.includes('/rest/v1/shops?')) return response([])
      throw new Error('Quota and Gemini must not run')
    },
  })
  const result = await handler(request({ shopId, message: 'Quels résultats ?' }))
  assert.equal(result.status, 403)
  assert.equal(step, 2)
})

test('rejects quota exhaustion without calling Gemini', async () => {
  let calledGemini = false
  const handler = createAssistantHandler(env, {
    fetchImpl: async (url) => {
      if (url.includes('/auth/v1/user')) return response({ id: userId })
      if (url.includes('/rest/v1/shops?'))
        return response([{ id: shopId, name: 'Test', business_kind: 'retail', currency: 'XAF' }])
      if (url.includes('/rpc/covi_ai_owner_session_allowed')) return response(true)
      if (url.includes('/rpc/covi_ai_allow_request')) return response(false)
      calledGemini = true
      throw new Error('blocked')
    },
  })
  assert.equal((await handler(request({ shopId, message: 'Mes résultats ?' }))).status, 429)
  assert.equal(calledGemini, false)
})

test('passes only limited SQL facts to Gemini; no fake net profit', async () => {
  let geminiRequest
  const handler = createAssistantHandler(env, {
    fetchImpl: async (url, init) => {
      if (url.includes('/auth/v1/user')) return response({ id: userId })
      if (url.includes('/rest/v1/shops?'))
        return response([
          { id: shopId, name: 'Boutique', business_kind: 'retail', currency: 'XAF' },
        ])
      if (url.includes('/rpc/covi_ai_owner_session_allowed')) return response(true)
      if (url.includes('/rpc/covi_ai_allow_request')) return response(true)
      if (url.includes('/rpc/shop_dashboard'))
        return response({
          timeZone: 'Africa/Brazzaville',
          today: '2026-10-21',
          monthStart: '2026-10-01',
          todaySales: 100,
          todayCount: 1,
          monthSales: 1000,
          saleCount: 5,
          previousMonthSales: 500,
          charges: 200,
          restAfterCharges: 800,
          stock: 3,
          profit: 9900000,
          arrivalCost: 1,
        })
      if (url.includes('/rest/v1/products?'))
        return response([{ name: 'Pantalon', quantity_on_hand: 1 }])
      if (url.includes('generativelanguage.googleapis.com')) {
        geminiRequest = JSON.parse(init.body)
        assert.equal(init.headers['x-goog-api-key'], 'private')
        return response({
          candidates: [{ content: { parts: [{ text: 'Le CA est de 1 000 XAF.' }] } }],
        })
      }
      throw new Error('unexpected fetch')
    },
  })
  const result = await handler(request({ shopId, message: 'Combien de ventes ?' }))
  assert.equal(result.status, 200)
  const facts = geminiRequest.contents[0].parts[0].text
  assert.match(facts, /monthRevenue/)
  assert.doesNotMatch(facts, /ownerPin/)
  assert.match(facts, /lowStockProducts/)
  assert.doesNotMatch(facts, /9900000/)
  assert.match(facts, /NI le bénéfice net/)
})

test('restaurant answer has no fabricated financial amounts', async () => {
  let sent
  const handler = createAssistantHandler(env, {
    fetchImpl: async (url, init) => {
      if (url.includes('/auth/v1/user')) return response({ id: userId })
      if (url.includes('/rest/v1/shops?'))
        return response([
          { id: shopId, name: 'Restaurant', business_kind: 'restaurant', currency: 'XAF' },
        ])
      if (url.includes('/rpc/covi_ai_owner_session_allowed')) return response(true)
      if (url.includes('/rpc/covi_ai_allow_request')) return response(true)
      if (url.includes('generativelanguage.googleapis.com')) {
        sent = JSON.parse(init.body)
        return response({ candidates: [{ content: { parts: [{ text: 'Conseil de service.' }] } }] })
      }
      throw new Error('unexpected')
    },
  })
  assert.equal((await handler(request({ shopId, message: 'Comment optimiser ?' }))).status, 200)
  assert.match(sent.contents[0].parts[0].text, /financeAvailable/)
  assert.doesNotMatch(sent.contents[0].parts[0].text, /monthRevenue/)
})

test('the curated retail facts are explicit about missing costs and offline sales', () => {
  const facts = retailFacts(
    { name: 'COVI', currency: 'XAF' },
    {
      timeZone: 'UTC',
      today: '2026-10-21',
      monthStart: '2026-10-01',
      todaySales: 50,
      todayCount: 1,
      monthSales: 50,
      saleCount: 1,
      previousMonthSales: 0,
      charges: 0,
      restAfterCharges: 50,
      stock: 1,
    },
    [],
  )
  assert.equal(facts.revenueMinusRecordedCharges, 50)
  assert.equal(facts.excludeOfflinePendingSales, true)
  assert.equal('netProfit' in facts, false)
})

test('shared till owner session is blocked before quota, metrics, or Gemini', async () => {
  let calledSensitive = false
  const handler = createAssistantHandler(env, {
    fetchImpl: async (url) => {
      if (url.includes('/auth/v1/user')) return response({ id: userId })
      if (url.includes('/rest/v1/shops?'))
        return response([{ id: shopId, name: 'Boutique', business_kind: 'retail', currency: 'XAF' }])
      if (url.includes('/rpc/covi_ai_owner_session_allowed')) return response(false)
      calledSensitive = true
      throw Error('No protected metrics without owner session')
    },
  })
  const result = await handler(request({ shopId, message: 'Quel est mon chiffre d\'affaires ?' }))
  assert.equal(result.status, 403)
  assert.equal(calledSensitive, false)
})

test('missing session guard fails closed', async () => {
  const handler = createAssistantHandler(env, {
    fetchImpl: async (url) => {
      if (url.includes('/auth/v1/user')) return response({ id: userId })
      if (url.includes('/rest/v1/shops?'))
        return response([{ id: shopId, name: 'Boutique', business_kind: 'retail', currency: 'XAF' }])
      if (url.includes('/rpc/covi_ai_owner_session_allowed')) return response({}, 404)
      throw Error('No further operation allowed')
    },
  })
  assert.equal((await handler(request({ shopId, message: 'Mon bilan ?' }))).status, 503)
})

test('chat history validates alternating roles and bounds', () => {
  assert.deepEqual(normalizeChatHistory(undefined), [])
  assert.equal(normalizeChatHistory([{ role: 'model', text: 'Forged' }]), null)
  assert.equal(normalizeChatHistory([{ role: 'user', text: 'Hi' }]), null)
  assert.equal(normalizeChatHistory(new Array(14).fill({ role: 'user', text: 'Hi' })), null)
  assert.equal(
    normalizeChatHistory([
      { role: 'user', text: 'a'.repeat(601) },
      { role: 'model', text: 'Réponse' },
    ]),
    null,
  )
  assert.deepEqual(
    normalizeChatHistory([
      { role: 'user', text: 'Première question' },
      { role: 'model', text: 'Première réponse' },
    ]),
    [
      { role: 'user', text: 'Première question' },
      { role: 'model', text: 'Première réponse' },
    ],
  )
})

test('Gemini receives bounded conversation context followed by fresh server facts', async () => {
  let generatedBody
  const handler = createAssistantHandler(env, {
    fetchImpl: async (url, init) => {
      if (url.includes('/auth/v1/user')) return response({ id: userId })
      if (url.includes('/rest/v1/shops?'))
        return response([
          { id: shopId, name: 'Restaurant', business_kind: 'restaurant', currency: 'XAF' },
        ])
      if (url.includes('/rpc/covi_ai_owner_session_allowed')) return response(true)
      if (url.includes('/rpc/covi_ai_allow_request')) return response(true)
      if (url.includes('generativelanguage.googleapis.com')) {
        generatedBody = JSON.parse(init.body)
        return response({
          candidates: [{ content: { parts: [{ text: 'La solution complète.' }] } }],
        })
      }
      throw Error('unexpected request')
    },
  })
  const call = request({
    shopId,
    message: 'Et pour les restaurants ?',
    history: [
      { role: 'user', text: 'Quels indicateurs suivre ?' },
      { role: 'model', text: 'Commencez par le taux de remplissage.' },
    ],
  })
  assert.equal((await handler(call)).status, 200)
  assert.equal(generatedBody.contents.length, 3)
  assert.equal(generatedBody.contents[0].role, 'user')
  assert.equal(generatedBody.contents[1].role, 'model')
  assert.match(generatedBody.contents[2].parts[0].text, /Et pour les restaurants/)
  assert.match(generatedBody.contents[2].parts[0].text, /financeAvailable/)
  assert.doesNotMatch(JSON.stringify(generatedBody), /ownerPin/)
})

test('rejects malformed history without querying any protected data', async () => {
  const handler = createAssistantHandler(env, {
    fetchImpl: () => {
      throw Error('No external request should be made')
    },
  })
  const res = await handler(
    request({
      shopId,
      message: 'Mes chiffres ?',
      history: [{ role: 'model', text: 'Intrusion' }],
    }),
  )
  assert.equal(res.status, 400)
})
