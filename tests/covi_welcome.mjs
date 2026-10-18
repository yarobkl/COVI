import assert from 'node:assert/strict'
import test from 'node:test'
import { dispatchWelcome, welcomeEligibility, welcomeMail } from '../supabase/functions/covi-welcome/handler.mjs'

const now = Date.UTC(2026, 9, 18, 12, 0, 0)
const user = {
  id: '0b569bf4-8811-42fb-95c7-39d314c97c16',
  email: 'owner@example.com',
  email_confirmed_at: new Date(now - 2_000).toISOString(),
  created_at: new Date(now - 60_000).toISOString(),
  app_metadata: { provider: 'google' },
  user_metadata: { first_name: 'Marie' },
}

test('sends a welcome receipt once for a newly verified Google or Facebook account', async () => {
  const sent = []
  const marked = []
  const result = await dispatchWelcome({
    now,
    token: 'valid-session-jwt',
    getUser: async () => user,
    sendMail: async (mail, key) => {
      sent.push({ mail, key })
      return { id: 'receipt-1' }
    },
    markSent: async (owner, at) => marked.push({ owner, at }),
  })
  assert.deepEqual(result, { status: 200, reason: 'sent' })
  assert.equal(sent.length, 1)
  assert.equal(sent[0].mail.to[0], user.email)
  assert.equal(sent[0].mail.subject, 'Bienvenue sur COVI — votre compte a été créé')
  assert.match(sent[0].mail.text, /Google/)
  assert.equal(sent[0].key, `covi-welcome/${user.id}`)
  assert.equal(marked.length, 1)
  assert.deepEqual(welcomeEligibility({ ...user, app_metadata: { provider: 'facebook' } }, now), {
    allowed: true,
    reason: 'new-oauth-account',
  })
  assert.match(welcomeMail({ ...user, app_metadata: { provider: 'facebook' } }).text, /Facebook/)
})

test('never sends a welcome email for old, unverified, password-only or already notified accounts', async () => {
  const cases = [
    { ...user, created_at: new Date(now - 2 * 86_400_000).toISOString() },
    { ...user, email_confirmed_at: null },
    { ...user, app_metadata: { provider: 'email' } },
    { ...user, app_metadata: { provider: 'google', covi_welcome_email_sent_at: '2026-10-18' } },
  ]
  for (const candidate of cases) {
    let sent = 0
    const result = await dispatchWelcome({
      token: 'jwt',
      now,
      getUser: async () => candidate,
      sendMail: async () => {
        sent++
        return { id: 'should-not-send' }
      },
      markSent: async () => { throw Error('must not be called') },
    })
    assert.equal(result.status, 200)
    assert.equal(sent, 0)
  }
})

test('refuses forged or missing JWTs and does not mark accounts when provider rejected email', async () => {
  let marked = false
  const noAuth = await dispatchWelcome({
    token: '',
    now,
    getUser: async () => user,
    sendMail: async () => ({ id: 'bad' }),
    markSent: async () => { marked = true },
  })
  assert.equal(noAuth.status, 401)
  const badAuth = await dispatchWelcome({
    token: 'fake-jwt',
    now,
    getUser: async () => null,
    sendMail: async () => ({ id: 'bad' }),
    markSent: async () => { marked = true },
  })
  assert.equal(badAuth.status, 401)
  const rejected = await dispatchWelcome({
    token: 'jwt',
    now,
    getUser: async () => user,
    sendMail: async () => null,
    markSent: async () => { marked = true },
  })
  assert.deepEqual(rejected, { status: 503, reason: 'mail-not-accepted' })
  assert.equal(marked, false)
})
