import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { resilientSale } from '../../lib/offline'
import { supabase } from '../../lib/supabase'
import type { Product } from '../../lib/types'
import { addToCart, setPrice, setQuantity, type Cart } from './cart'
import {
  CART_UNCERTAIN_TEXT,
  CART_WAITING_TEXT,
  NO_SESSION_TEXT,
  TILL_OFFLINE_TEXT,
  operationFor,
  submitCart,
  type CartOperation,
} from './cartSubmit'

vi.mock('../../lib/supabase', () => ({
  supabase: { auth: { getSession: vi.fn() }, rpc: vi.fn() },
}))
vi.mock('../../lib/offline', () => ({ resilientSale: vi.fn() }))

const product = (id: string, name: string, extra: Partial<Product> = {}): Product => ({
  id,
  shop_id: 'shop-1',
  arrival_id: null,
  name,
  category: null,
  brand: null,
  size: null,
  initial_sale_price: 10000,
  quantity_on_hand: 3,
  is_unique_piece: false,
  status: 'active',
  is_test: false,
  image_path: null,
  created_at: '2026-10-01T00:00:00Z',
  updated_at: '2026-10-01T00:00:00Z',
  ...extra,
})

const robe = product('11111111-1111-4111-8111-111111111111', 'Robe wax')
const jean = product('22222222-2222-4222-8222-222222222222', 'Jean slim', {
  initial_sale_price: 15000,
})

const twoLines = (): Cart => {
  let cart = addToCart(addToCart([], robe).cart, jean).cart
  cart = setQuantity(cart, robe.id, 2)
  return setPrice(cart, jean.id, 14000)
}
const oneLine = (): Cart => addToCart([], robe).cart

const rpc = vi.mocked(supabase.rpc) as unknown as ReturnType<typeof vi.fn>
let online = true

beforeEach(() => {
  online = true
  Object.defineProperty(navigator, 'onLine', { configurable: true, get: () => online })
  vi.mocked(supabase.auth.getSession).mockResolvedValue({
    data: { session: { access_token: 't' } },
    error: null,
  } as never)
  rpc.mockResolvedValue({ data: 'sale-1', error: null })
  vi.mocked(resilientSale).mockResolvedValue({ offline: false })
})
afterEach(() => {
  vi.clearAllMocks()
})

/** What the seller does: press « Valider », keeping the operation between tries. */
async function press(previous: CartOperation | null, lines: Cart, payment = 'Mobile Money') {
  const op = operationFor(previous, lines, payment)
  const result = await submitCart({
    userId: 'u1',
    shopId: 'shop-1',
    lines,
    paymentLabel: payment,
    operationId: op.id,
  })
  return { op, result }
}

describe('submitCart: several articles', () => {
  it('calls record_cart_sale with the shop, the exact lines, the payment code and the key', async () => {
    const { op, result } = await press(null, twoLines())
    expect(result).toEqual({ status: 'sold', offline: false })
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('record_cart_sale', {
      p_shop_id: 'shop-1',
      p_items: [
        { product_id: robe.id, quantity: 2, sold_unit_price: 10000 },
        { product_id: jean.id, quantity: 1, sold_unit_price: 14000 },
      ],
      p_payment_method: 'mobile_money',
      p_client_operation_id: op.id,
    })
    expect(op.id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
    expect(resilientSale).not.toHaveBeenCalled()
  })

  it('reuses the same operation id on a retry after a network failure', async () => {
    rpc.mockResolvedValueOnce({
      data: null,
      error: { message: 'TypeError: Failed to fetch', code: '' },
    })
    const lines = twoLines()
    const first = await press(null, lines)
    // Sent, no answer: the outcome is unknown (the cart will be frozen by the screen).
    expect(first.result).toEqual({ status: 'uncertain', message: CART_UNCERTAIN_TEXT })
    const second = await press(first.op, lines)
    expect(second.result.status).toBe('sold')
    expect(second.op.id).toBe(first.op.id)
    const ids = rpc.mock.calls.map(
      (c) => (c[1] as { p_client_operation_id: string }).p_client_operation_id,
    )
    expect(ids).toEqual([first.op.id, first.op.id])
  })

  it('takes a new id after a success, and when the cart changed', async () => {
    const lines = twoLines()
    const sold = await press(null, lines)
    // After a success the screen forgets the operation: the next cart gets a new key.
    const next = await press(null, lines)
    expect(next.op.id).not.toBe(sold.op.id)
    // Same cart retried: same key; a changed cart (or payment): a new key.
    expect(operationFor(next.op, lines, 'Mobile Money').id).toBe(next.op.id)
    expect(operationFor(next.op, setQuantity(lines, robe.id, 1), 'Mobile Money').id).not.toBe(
      next.op.id,
    )
    expect(operationFor(next.op, lines, 'Espèces').id).not.toBe(next.op.id)
  })

  it('without network, sends nothing and keeps the cart (never split)', async () => {
    online = false
    const lines = twoLines()
    const { result } = await press(null, lines)
    expect(result).toEqual({ status: 'offline', message: CART_WAITING_TEXT })
    expect(rpc).not.toHaveBeenCalled()
    expect(resilientSale).not.toHaveBeenCalled()
    expect(lines).toHaveLength(2)
  })

  it('an answer without SQLSTATE is uncertain; an answer with one is a definitive refusal', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { message: 'Bad gateway', code: '' } })
    expect((await press(null, twoLines())).result.status).toBe('uncertain')
    rpc.mockResolvedValueOnce({
      data: null,
      error: { message: 'Insufficient stock', code: 'P0001' },
    })
    expect((await press(null, twoLines())).result.status).toBe('refused')
  })

  it('a gateway page (502/503/504, no code) or PostgREST without database: uncertain', async () => {
    for (const error of [
      { message: '<html>502 Bad Gateway</html>' },
      { message: 'upstream request timeout', code: undefined },
      { message: 'Could not connect with the database', code: 'PGRST001' },
      { name: 'AbortError', message: 'The operation was aborted' },
    ]) {
      rpc.mockResolvedValueOnce({ data: null, error })
      expect((await press(null, twoLines())).result.status).toBe('uncertain')
    }
  })

  it('a PostgREST request error or a missing session: nothing was sent, a refusal', async () => {
    rpc.mockResolvedValueOnce({
      data: null,
      error: { message: 'Could not find the function', code: 'PGRST202' },
    })
    expect((await press(null, twoLines())).result.status).toBe('refused')
    vi.mocked(supabase.auth.getSession).mockResolvedValueOnce({
      data: { session: null },
      error: null,
    } as never)
    expect((await press(null, twoLines())).result.status).toBe('refused')
  })

  it('an expired session (PGRST303, « JWT expired »): refusal, same key on the next press', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { message: 'JWT expired', code: 'PGRST303' } })
    const lines = twoLines()
    const first = await press(null, lines)
    expect(first.result).toEqual({ status: 'refused', message: NO_SESSION_TEXT })
    const second = await press(first.op, lines)
    expect(second.op.id).toBe(first.op.id)
    expect(second.result).toEqual({ status: 'sold', offline: false })
  })

  it('no signed-in account: nothing is sent', async () => {
    const result = await submitCart({
      userId: '',
      shopId: 'shop-1',
      lines: twoLines(),
      paymentLabel: 'Espèces',
      operationId: crypto.randomUUID(),
    })
    expect(result).toEqual({ status: 'refused', message: NO_SESSION_TEXT })
    expect(rpc).not.toHaveBeenCalled()
    expect(resilientSale).not.toHaveBeenCalled()
  })

  it('says the refusals in French and names the article in cause', async () => {
    rpc.mockResolvedValueOnce({
      data: null,
      error: {
        message: 'Insufficient stock',
        code: 'P0001',
        details: `item 0: product_id ${robe.id}, requested 2, available 1`,
      },
    })
    expect((await press(null, twoLines())).result).toEqual({
      status: 'refused',
      productId: robe.id,
      message: 'Robe wax : il n’en reste que 1. Baissez la quantité.',
    })

    rpc.mockResolvedValueOnce({
      data: null,
      error: { message: 'Product unavailable', code: 'P0001', details: 'item 1: product_id …' },
    })
    expect((await press(null, twoLines())).result).toMatchObject({
      status: 'refused',
      productId: jean.id,
      message: 'Jean slim : cet article n’est plus en stock. Il a peut-être déjà été vendu.',
    })

    rpc.mockResolvedValueOnce({
      data: null,
      error: { message: 'Cannot mix test and real products', code: 'P0001' },
    })
    expect((await press(null, twoLines())).result).toEqual({
      status: 'refused',
      message:
        'Les articles d’exemple ne se vendent pas avec les vrais. Faites deux ventes séparées.',
    })
  })

  it('without a session, does not call the server and asks to sign in again', async () => {
    vi.mocked(supabase.auth.getSession).mockResolvedValueOnce({
      data: { session: null },
      error: null,
    } as never)
    const { result } = await press(null, twoLines())
    expect(rpc).not.toHaveBeenCalled()
    expect(result).toEqual({
      status: 'refused',
      message: 'Votre session a pris fin. Reconnectez-vous, puis validez la vente à nouveau.',
    })
  })
})

describe('submitCart: one article', () => {
  it('goes through resilientSale as before (record_sale online)', async () => {
    const { result } = await press(null, oneLine(), 'Espèces')
    expect(result).toEqual({ status: 'sold', offline: false })
    expect(resilientSale).toHaveBeenCalledWith({
      shopId: 'shop-1',
      productId: robe.id,
      quantity: 1,
      soldUnitPrice: 10000,
      paymentLabel: 'Espèces',
    })
    expect(rpc).not.toHaveBeenCalled()
  })

  it('without network, is kept on the device by resilientSale', async () => {
    online = false
    vi.mocked(resilientSale).mockResolvedValueOnce({ offline: true })
    const { result } = await press(null, oneLine())
    expect(result).toEqual({ status: 'sold', offline: true })
    expect(resilientSale).toHaveBeenCalledTimes(1)
    expect(rpc).not.toHaveBeenCalled()
  })

  it('translates its refusals', async () => {
    vi.mocked(resilientSale).mockRejectedValueOnce(new Error('Insufficient stock'))
    expect((await press(null, oneLine())).result).toEqual({
      status: 'refused',
      message: 'Il n’en reste que 3. Baissez la quantité.',
    })
  })
})

const TOKEN = 'd'.repeat(64)

/** « Valider » on the owner's shared device, in the name of the till-session cashier. */
async function pressTill(previous: CartOperation | null, lines: Cart, payment = 'Espèces') {
  const op = operationFor(previous, lines, payment)
  const result = await submitCart({
    userId: 'u-owner',
    shopId: 'shop-1',
    lines,
    paymentLabel: payment,
    operationId: op.id,
    tillSession: TOKEN,
  })
  return { op, result }
}

describe('submitCart: in the name of a till-session cashier (counter mode)', () => {
  it('several articles: record_cart_sale with p_till_session and the cart key', async () => {
    const { op, result } = await pressTill(null, twoLines())
    expect(result).toEqual({ status: 'sold', offline: false })
    expect(rpc).toHaveBeenCalledWith('record_cart_sale', {
      p_shop_id: 'shop-1',
      p_items: [
        { product_id: robe.id, quantity: 2, sold_unit_price: 10000 },
        { product_id: jean.id, quantity: 1, sold_unit_price: 14000 },
      ],
      p_payment_method: 'cash',
      p_client_operation_id: op.id,
      p_till_session: TOKEN,
    })
    expect(resilientSale).not.toHaveBeenCalled()
  })

  it('one article: record_sale with p_till_session, never the offline queue', async () => {
    const { op, result } = await pressTill(null, oneLine())
    expect(result).toEqual({ status: 'sold', offline: false })
    expect(rpc).toHaveBeenCalledWith('record_sale', {
      p_shop_id: 'shop-1',
      p_product_id: robe.id,
      p_quantity: 1,
      p_sold_unit_price: 10000,
      p_payment_method: 'cash',
      p_client_operation_id: op.id,
      p_till_session: TOKEN,
    })
    expect(resilientSale).not.toHaveBeenCalled()
  })

  it('without network: nothing sent, nothing queued (the sale would lose its cashier)', async () => {
    online = false
    for (const lines of [oneLine(), twoLines()]) {
      const { result } = await pressTill(null, lines)
      expect(result).toEqual({ status: 'offline', message: TILL_OFFLINE_TEXT })
    }
    expect(rpc).not.toHaveBeenCalled()
    expect(resilientSale).not.toHaveBeenCalled()
  })

  it('one article cut during the call: uncertain, retried with the same key and token', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { message: 'Failed to fetch', code: '' } })
    const lines = oneLine()
    const first = await pressTill(null, lines)
    expect(first.result).toEqual({ status: 'uncertain', message: CART_UNCERTAIN_TEXT })
    const second = await pressTill(first.op, lines)
    expect(second.result.status).toBe('sold')
    expect(rpc.mock.calls[1]).toEqual(rpc.mock.calls[0])
  })

  it('a closed or expired till session is a refusal in the shop’s words', async () => {
    rpc.mockResolvedValueOnce({
      data: null,
      error: { message: 'Till session invalid', code: '42501' },
    })
    expect((await pressTill(null, twoLines())).result).toEqual({
      status: 'refused',
      message:
        'La caisse de ce caissier est fermée ou a expiré. Touchez « Changer de caissier » et entrez à nouveau son code PIN.',
    })
  })
})

describe('submitCart: price under the cashier’s minimum', () => {
  it('names the line and gives the minimum from the server DETAIL', async () => {
    rpc.mockResolvedValueOnce({
      data: null,
      error: {
        message: 'Price below allowed minimum',
        code: 'P0001',
        details: `item 1: product_id ${jean.id}, minimum_price=13500`,
      },
    })
    const { result } = await pressTill(null, twoLines())
    expect(result.status).toBe('refused')
    if (result.status !== 'refused') return
    expect(result.productId).toBe(jean.id)
    expect(result.message).toMatch(
      /^Jean slim : ce prix est en dessous du minimum autorisé \(13.500 FCFA\)\. Demandez au responsable\.$/,
    )
  })

  it('one article on the cashier’s own account: the same message, without a line name', async () => {
    vi.mocked(resilientSale).mockRejectedValueOnce({
      message: 'Price below allowed minimum',
      code: 'P0001',
      details: `item 0: product_id ${robe.id}, minimum_price=9000`,
    })
    const { result } = await press(null, oneLine())
    expect(result.status).toBe('refused')
    if (result.status !== 'refused') return
    expect(result.message).toMatch(
      /^Ce prix est en dessous du minimum autorisé \(9.000 FCFA\)\. Demandez au responsable\.$/,
    )
  })
})
