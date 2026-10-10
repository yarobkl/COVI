// End-to-end test of the offline till on the production build, with Supabase simulated.
//
//   VITE_SUPABASE_URL=https://covi-e2e.supabase.co npm run build
//   npm run preview -- --port 4173 --strictPort &
//   PLAYWRIGHT_DIR=/path/to/a/folder/with/playwright node tests/e2e/offline-pwa.mjs
//
// Playwright is not a dependency of the project: install it elsewhere (npm i playwright, then
// npx playwright install chromium) and point PLAYWRIGHT_DIR at that folder. Every request to
// *.supabase.co is answered by the mock below; nothing reaches a real Supabase project.
import assert from 'node:assert/strict'
import { mkdirSync } from 'node:fs'
import { createRequire } from 'node:module'
import { join } from 'node:path'

const require = createRequire(join(process.env.PLAYWRIGHT_DIR ?? process.cwd(), 'noop.js'))
const { chromium } = require('playwright')
const BASE = process.env.BASE_URL ?? 'http://localhost:4173'
const CAPTURES = process.env.CAPTURES_DIR ?? 'captures'
const HOST = 'covi-e2e.supabase.co'
mkdirSync(CAPTURES, { recursive: true })

const USER = {
  id: '11111111-1111-4111-8111-111111111111',
  email: 'caisse@covi.test',
  aud: 'authenticated',
  role: 'authenticated',
}
const SHOP = {
  id: '22222222-2222-4222-8222-222222222222',
  name: 'Boutique Poto-Poto',
  city: 'Brazzaville',
  country: 'Congo',
  currency: 'XAF',
}
const PRODUCT = {
  id: '33333333-3333-4333-8333-333333333333',
  shop_id: SHOP.id,
  name: 'Robe wax',
  brand: null,
  category: 'Robes',
  size: 'M',
  initial_sale_price: 15000,
  quantity_on_hand: 3,
  status: 'active',
  is_unique_piece: false,
  is_test: false,
  image_path: null,
  arrival_id: null,
  created_at: '2026-10-01T10:00:00.000Z',
}
const b64 = (x) => Buffer.from(JSON.stringify(x)).toString('base64url')
let tokens = 0
function session() {
  const exp = Math.floor(Date.now() / 1000) + 3600
  tokens++
  return {
    access_token: `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ sub: USER.id, exp, role: 'authenticated', aud: 'authenticated' })}.sig${tokens}`,
    token_type: 'bearer',
    expires_in: 3600,
    expires_at: exp,
    refresh_token: 'refresh-' + tokens,
    user: USER,
  }
}

const rpcCalls = []
const log = []
async function supabaseMock(route) {
  const request = route.request(),
    url = new URL(request.url()),
    path = url.pathname,
    method = request.method()
  log.push(`${method} ${path}${url.search}`)
  const json = (body, status = 200, headers = {}) =>
    route.fulfill({
      status,
      contentType: 'application/json',
      headers: { 'access-control-allow-origin': '*', ...headers },
      body: JSON.stringify(body),
    })
  if (method === 'OPTIONS')
    return route.fulfill({
      status: 204,
      headers: {
        'access-control-allow-origin': '*',
        'access-control-allow-headers': '*',
        'access-control-allow-methods': 'GET,POST,PATCH,DELETE,OPTIONS',
      },
    })
  if (path === '/auth/v1/token') return json(session())
  if (path === '/auth/v1/user') return json(USER)
  if (path === '/auth/v1/logout') return route.fulfill({ status: 204 })
  if (path === '/rest/v1/rpc/record_sale') {
    rpcCalls.push(request.postDataJSON())
    return json('44444444-4444-4444-8444-' + String(rpcCalls.length).padStart(12, '0'))
  }
  if (path === '/rest/v1/shops') {
    const accept = request.headers()['accept'] ?? ''
    return json(accept.includes('vnd.pgrst.object') ? SHOP : [SHOP])
  }
  if (path === '/rest/v1/products') {
    const sold = rpcCalls.length
    return json([{ ...PRODUCT, quantity_on_hand: PRODUCT.quantity_on_hand - sold }])
  }
  if (path.startsWith('/rest/v1/')) return json([], 200, { 'content-range': '0-0/0' })
  return json({ message: 'not mocked: ' + path }, 404)
}

const browser = await chromium.launch()
const context = await browser.newContext({
  viewport: { width: 412, height: 915 },
  deviceScaleFactor: 1,
  locale: 'fr-FR',
  serviceWorkers: 'allow',
})
// Safety net (registered first: the last matching route wins): any other Supabase project is
// refused and fails the test.
const forbidden = []
await context.route('https://*.supabase.co/**', (route) => {
  forbidden.push(route.request().url())
  return route.abort()
})
// context.route also sees the requests made by the service worker (Supabase GETs go through it).
await context.route(`https://${HOST}/**`, supabaseMock)
const page = await context.newPage()
const consoleErrors = []
page.on('pageerror', (e) => consoleErrors.push(String(e)))
const shot = (name) => page.screenshot({ path: join(CAPTURES, name), fullPage: false })
const step = (text) => console.log('·', text)

step('online: sign in')
await page.goto(BASE)
await page.fill('input[name=email]', USER.email)
await page.fill('input[name=password]', 'motdepasse')
await page.click('button[type=submit]')
await page.getByText(SHOP.name).filter({ visible: true }).first().waitFor()
step('online: open the sale page (stock cached)')
await page.evaluate(() => (location.hash = '#/vendre'))
await page.getByText(PRODUCT.name).filter({ visible: true }).first().waitFor()
await page.evaluate(() => navigator.serviceWorker.ready)
// Make sure the page is controlled by the service worker before going offline.
await page.reload()
await page.getByText(SHOP.name).filter({ visible: true }).first().waitFor()
assert.ok(await page.evaluate(() => !!navigator.serviceWorker.controller), 'controlled by the SW')
await shot('01-en-ligne.png')

step('session expired (token older than 1 h), then offline reload')
await page.evaluate(() => {
  const key = Object.keys(localStorage).find(
    (k) => k.startsWith('sb-') && k.endsWith('-auth-token'),
  )
  const s = JSON.parse(localStorage.getItem(key))
  s.expires_at = Math.floor(Date.now() / 1000) - 3600
  localStorage.setItem(key, JSON.stringify(s))
})
await context.setOffline(true)
const started = Date.now()
await page.reload()
// Offline, the top strip shows the calm network notice in place of the shop name.
await page.getByText('Pas de réseau').filter({ visible: true }).first().waitFor({ timeout: 5000 })
const openedIn = Date.now() - started
assert.equal(
  await page.getByRole('heading', { name: 'Connexion' }).count(),
  0,
  'not the sign-in screen',
)
assert.equal(
  await page.getByRole('heading', { name: 'Comment s’appelle votre boutique ?' }).count(),
  0,
  'not the creation form',
)
await shot('02-hors-ligne-recharge.png')
step(`offline: app opened on the shop in ${openedIn} ms`)

step('offline: record a sale')
await page.evaluate(() => (location.hash = '#/vendre'))
const tile = page
  .getByRole('button', { name: new RegExp(PRODUCT.name) })
  .filter({ visible: true })
  .first()
await tile.waitFor({ timeout: 5000 })
await tile.click()
await page.getByText('Espèces', { exact: true }).filter({ visible: true }).first().click()
await page.getByRole('button', { name: /Valider la vente/ }).click()
await page.getByText('Vente gardée sur ce téléphone').first().waitFor()
const queued = await page.evaluate(
  () =>
    new Promise((resolve, reject) => {
      const open = indexedDB.open('covi-offline')
      open.onerror = () => reject(open.error)
      open.onsuccess = () => {
        const all = open.result.transaction('pending').objectStore('pending').getAll()
        all.onsuccess = () => resolve(all.result)
        all.onerror = () => reject(all.error)
      }
    }),
)
assert.equal(queued.length, 1, 'one sale in the IndexedDB queue')
assert.equal(rpcCalls.length, 0)
await shot('03-vente-en-file.png')
step(`offline: sale ${queued[0].id} queued in IndexedDB`)

step('back online: the queue is sent')
await context.setOffline(false)
const deadline = Date.now() + 45000
while (rpcCalls.length === 0 && Date.now() < deadline) await page.waitForTimeout(250)
assert.equal(rpcCalls.length, 1, 'record_sale called')
// Leave time for any duplicate (other triggers, timers, background sync).
await page.waitForTimeout(6000)
assert.equal(rpcCalls.length, 1, 'sent exactly once')
assert.equal(rpcCalls[0].p_client_operation_id, queued[0].id, 'stable operation id')
assert.equal(rpcCalls[0].p_product_id, PRODUCT.id)
assert.equal(rpcCalls[0].p_quantity, 1)
await page
  .getByText(/à envoyer/)
  .first()
  .waitFor({ state: 'detached', timeout: 15000 })
await shot('04-synchronise.png')
const left = await page.evaluate(
  () =>
    new Promise((resolve) => {
      const open = indexedDB.open('covi-offline')
      open.onsuccess = () => {
        const all = open.result.transaction('pending').objectStore('pending').count()
        all.onsuccess = () => resolve(all.result)
      }
    }),
)
assert.equal(left, 0, 'queue empty')
assert.ok(
  log.some((l) => l.includes('grant_type=refresh_token')),
  'session refreshed',
)
assert.deepEqual(forbidden, [], 'no request to a real Supabase project')
assert.deepEqual(consoleErrors, [])
console.log(
  `PASS offline E2E: app opened offline with an expired session in ${openedIn} ms, sale queued, sent once on reconnection (client_operation_id ${queued[0].id}).`,
)
await browser.close()
