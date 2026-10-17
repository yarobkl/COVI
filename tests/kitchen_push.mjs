import assert from 'node:assert/strict'
import { test } from 'node:test'
import {
  createKitchenPushDispatcher,
  trustedPushEndpoint,
} from '../supabase/functions/restaurant-kitchen-push/dispatcher.mjs'

const uuid = '00000000-0000-0000-0000-000000000001'
const task = {
  id: uuid,
  lease: uuid,
  through: '9007199254740993',
  count: 2,
  endpoint: 'https://fcm.googleapis.com/fcm/send/' + 'a'.repeat(60),
  p256dh: 'A'.repeat(87),
  auth: 'A'.repeat(22),
}
const config = {
  enabled: 'true',
  secret: 'a'.repeat(48),
  publicKey: 'public',
  privateKey: 'private',
  subject: 'mailto:admin@example.com',
  serviceKey: 'service',
}
const req = (token = config.secret, method = 'POST') =>
  new Request('https://supabase.example.test/functions/v1/restaurant-kitchen-push', {
    method,
    headers: { authorization: 'Bearer ' + token },
  })

test('fail closed without secret, config or valid bearer', async () => {
  let calls = 0
  const deps = {
    rpc: async () => {
      calls++
      return []
    },
    sendPush: async () => calls++,
  }
  const enabled = createKitchenPushDispatcher(config, deps)
  assert.equal((await enabled(req('wrong'))).status, 401)
  assert.equal((await enabled(req(undefined, 'GET'))).status, 405)
  assert.equal(
    (await createKitchenPushDispatcher({ ...config, enabled: 'false' }, deps)(req())).status,
    503,
  )
  assert.equal(
    (await createKitchenPushDispatcher({ ...config, privateKey: '' }, deps)(req())).status,
    503,
  )
  assert.equal(calls, 0)
})
test('strict allowlist blocks SSRF, credentials, unsafe urls and lookalike hostnames', () => {
  assert.equal(trustedPushEndpoint(task.endpoint), true)
  assert.equal(trustedPushEndpoint('https://web.push.apple.com/aaa' + 'a'.repeat(60)), true)
  for (const endpoint of [
    'https://fcm.googleapis.com.attacker.com/' + 'a'.repeat(60),
    'http://fcm.googleapis.com/' + 'a'.repeat(60),
    'https://127.0.0.1/' + 'a'.repeat(60),
    'https://user:pass@fcm.googleapis.com/' + 'a'.repeat(60),
    'https://fcm.googleapis.com:8888/' + 'a'.repeat(60),
    'https://fcm.googleapis.com/' + 'a'.repeat(60) + '#fragment',
  ])
    assert.equal(trustedPushEndpoint(endpoint), false)
})
test('sends generic payload, sends no customer data, and finishes claimed event', async () => {
  const calls = [],
    sends = []
  const handler = createKitchenPushDispatcher(config, {
    rpc: async (name, args) => {
      calls.push([name, args])
      return name.endsWith('_claim') ? [task] : true
    },
    sendPush: async (sub, payload) => {
      sends.push([sub, payload])
    },
  })
  const res = await handler(req())
  assert.equal(res.status, 200)
  assert.deepEqual(await res.json(), { claimed: 1, sent: 1, gone: 0, retry: 0, failedAcks: 0 })
  assert.equal(sends.length, 1)
  assert.equal(JSON.parse(sends[0][1]).title, 'COVI — Nouvelle préparation')
  assert.equal(calls[1][1].p_through, '9007199254740993')
  assert.equal(calls[1][1].p_outcome, 'sent')
  assert.equal(sends[0][1].includes('restaurant'), false)
})
test('treats expired endpoints as gone and transient outages as retry, never as sent', async () => {
  const finish = []
  const handler = createKitchenPushDispatcher(config, {
    rpc: async (name, args) =>
      name.endsWith('_claim')
        ? [
            { ...task, id: uuid },
            { ...task, id: '00000000-0000-0000-0000-000000000002' },
          ]
        : (finish.push(args.p_outcome), true),
    sendPush: async (_s, _p) => {
      if (finish.length === 0) throw Object.assign(Error('expired'), { statusCode: 410 })
      throw Error('network')
    },
  })
  const response = await handler(req())
  assert.equal(response.status, 200)
  assert.deepEqual(finish, ['gone', 'retry'])
})
test('invalid destination is never fetched, and a failed DB acknowledgement is not success', async () => {
  let sent = 0
  const handler = createKitchenPushDispatcher(config, {
    rpc: async (name) => {
      if (name.endsWith('_claim'))
        return [{ ...task, endpoint: 'https://127.0.0.1/private'.padEnd(90, 'a') }]
      throw Error('database unavailable')
    },
    sendPush: async () => sent++,
  })
  const res = await handler(req())
  assert.equal(res.status, 503)
  assert.equal(sent, 0)
  assert.equal((await res.json()).failedAcks, 1)
})
