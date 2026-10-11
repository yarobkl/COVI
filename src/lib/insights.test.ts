import { beforeEach, describe, expect, it, vi } from 'vitest'

const mocks = vi.hoisted(() => ({
  rpc: vi.fn(),
  from: vi.fn(),
  dashboard: vi.fn(),
  arrivalProfitability: vi.fn(),
}))
vi.mock('./supabase', () => ({ supabase: { rpc: mocks.rpc, from: mocks.from } }))
vi.mock('./operations', () => ({
  dashboard: mocks.dashboard,
  arrivalProfitability: mocks.arrivalProfitability,
}))

import {
  fetchArrivalProfitability,
  fetchEstimatedProfit,
  fetchMonthlySales,
  fetchShopDashboard,
  isMissingFunctionError,
  resetInsightsAvailability,
} from './insights'

const missing = {
  code: 'PGRST202',
  message: 'Could not find the function public.shop_dashboard(p_shop_id) in the schema cache',
  details: null,
  hint: null,
}

/** Requête PostgREST simulée : chaque filtre renvoie la requête, `await` donne le résultat. */
function query(result: { data: unknown; error: unknown }) {
  const q: Record<string, unknown> = {}
  for (const m of ['select', 'eq', 'gte', 'lt', 'in', 'order', 'limit']) q[m] = () => q
  q.then = (resolve: (v: unknown) => unknown) => resolve(result)
  return q
}

beforeEach(() => {
  resetInsightsAvailability()
  vi.clearAllMocks()
})

describe('isMissingFunctionError', () => {
  it('reconnaît les erreurs de fonction absente', () => {
    expect(isMissingFunctionError(missing)).toBe(true)
    expect(isMissingFunctionError({ code: '42883', message: 'function x does not exist' })).toBe(
      true,
    )
    expect(isMissingFunctionError({ message: 'Could not find the function public.f' })).toBe(true)
  })
  it('ne confond pas les autres erreurs', () => {
    expect(isMissingFunctionError({ code: '42501', message: 'Shop not found' })).toBe(false)
    expect(isMissingFunctionError(new TypeError('Failed to fetch'))).toBe(false)
    expect(isMissingFunctionError(null)).toBe(false)
  })
})

describe('fetchShopDashboard', () => {
  const sql = {
    timeZone: 'Africa/Brazzaville',
    today: '2026-10-10',
    monthStart: '2026-10-01',
    todaySales: 5000,
    todayCount: 1,
    todayByPaymentMethod: [{ method: 'cash', amount: 5000 }],
    monthSales: 20000,
    saleCount: 4,
    previousMonthStart: '2026-09-01',
    previousMonthSales: 12000,
    charges: 3000,
    expensesByCategory: [{ category: 'Loyer', amount: 3000 }],
    restAfterCharges: 17000,
    arrivalCost: 8000,
    stock: 42,
    profitBeforeCharges: 12000,
    profit: 9000,
    arrivalsInProgress: 1,
    ordersInProgress: 1,
    balloonsInProgress: 0,
    inProgressByStatus: { draft: 0, ordered: 1, in_transit: 0 },
  }

  it('appelle la fonction SQL avec le fuseau de Brazzaville par défaut', async () => {
    mocks.rpc.mockResolvedValue({ data: sql, error: null })
    const d = await fetchShopDashboard('shop-1')
    expect(mocks.rpc).toHaveBeenCalledWith('shop_dashboard', {
      p_shop_id: 'shop-1',
      p_tz: 'Africa/Brazzaville',
      p_include_test: false,
    })
    expect(d).toEqual({ ...sql, source: 'database' })
    expect(mocks.dashboard).not.toHaveBeenCalled()
  })

  it('transmet le fuseau et includeTest demandés', async () => {
    mocks.rpc.mockResolvedValue({ data: sql, error: null })
    await fetchShopDashboard('shop-1', { timeZone: 'Europe/Paris', includeTest: true })
    expect(mocks.rpc).toHaveBeenCalledWith('shop_dashboard', {
      p_shop_id: 'shop-1',
      p_tz: 'Europe/Paris',
      p_include_test: true,
    })
  })

  it('bascule sur le calcul client si la fonction est absente, et le mémorise', async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: missing })
    mocks.dashboard.mockResolvedValue({
      today: { total: 5000, count: 1, byMethod: [{ method: 'cash', amount: 5000 }] },
      month: {
        total: 20000,
        count: 4,
        charges: 3000,
        expenses: [{ category: 'Loyer', amount: 3000 }],
        restAfterCharges: 17000,
      },
      previousMonth: { total: 12000, date: new Date(2026, 8, 1) },
      stock: 42,
      lowStock: [],
      arrivalsInProgress: [
        { id: 'a', kind: 'supplier_order', status: 'ordered' },
        { id: 'b', kind: 'balloon', status: 'in_transit' },
      ],
      recentSales: [],
    })
    mocks.from.mockImplementation(() =>
      query({
        data: [
          { global_cost: 0, merchandise_cost: 5000, transport_cost: 2000, customs_cost: 1000 },
        ],
        error: null,
      }),
    )

    const d = await fetchShopDashboard('shop-1')
    expect(d.source).toBe('client')
    expect(d.monthSales).toBe(20000)
    expect(d.arrivalCost).toBe(8000)
    expect(d.profit).toBe(9000)
    expect(d.previousMonthStart).toBe('2026-09-01')
    expect(d.arrivalsInProgress).toBe(2)
    expect(d.ordersInProgress).toBe(1)
    expect(d.balloonsInProgress).toBe(1)
    expect(d.inProgressByStatus).toEqual({ draft: 0, ordered: 1, in_transit: 1 })

    await fetchShopDashboard('shop-1')
    expect(mocks.rpc).toHaveBeenCalledTimes(1)
    expect(mocks.dashboard).toHaveBeenCalledTimes(2)
  })

  it('propage les vraies erreurs (42501) sans repli ni mémorisation', async () => {
    const denied = { code: '42501', message: 'Shop not found', details: null, hint: null }
    mocks.rpc.mockResolvedValue({ data: null, error: denied })
    await expect(fetchShopDashboard('other-shop')).rejects.toBe(denied)
    expect(mocks.dashboard).not.toHaveBeenCalled()

    mocks.rpc.mockResolvedValue({ data: sql, error: null })
    await expect(fetchShopDashboard('shop-1')).resolves.toMatchObject({ source: 'database' })
    expect(mocks.rpc).toHaveBeenCalledTimes(2)
  })

  it('propage une erreur réseau', async () => {
    mocks.rpc.mockRejectedValue(new TypeError('Failed to fetch'))
    await expect(fetchShopDashboard('shop-1')).rejects.toThrow('Failed to fetch')
    expect(mocks.dashboard).not.toHaveBeenCalled()
  })
})

describe('fetchMonthlySales', () => {
  it('appelle la fonction SQL', async () => {
    const data = {
      timeZone: 'Africa/Brazzaville',
      from: '2026-04-01',
      to: '2026-10-01',
      months: [],
      topCategories: [],
    }
    mocks.rpc.mockResolvedValue({ data, error: null })
    await expect(fetchMonthlySales('shop-1', 6)).resolves.toEqual({ ...data, source: 'database' })
    expect(mocks.rpc).toHaveBeenCalledWith('shop_monthly_sales', {
      p_shop_id: 'shop-1',
      p_months: 6,
      p_tz: 'Africa/Brazzaville',
      p_include_test: false,
    })
  })

  it('repli : agrège les ventes des mois complets précédents', async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: missing })
    const now = new Date(),
      lastMonth = new Date(now.getFullYear(), now.getMonth() - 1, 15, 12),
      thisMonth = new Date(now.getFullYear(), now.getMonth(), 1, 12)
    mocks.from.mockImplementation(() =>
      query({
        data: [
          {
            total_amount: 3000,
            sold_at: lastMonth.toISOString(),
            sale_items: [
              { quantity: 2, sold_unit_price: 1000, products: { category: 'Robes' } },
              { quantity: 1, sold_unit_price: 1000, products: { category: ' ' } },
            ],
          },
          // Hors période (mois en cours) : ignorée.
          { total_amount: 999, sold_at: thisMonth.toISOString(), sale_items: [] },
        ],
        error: null,
      }),
    )
    const m = await fetchMonthlySales('shop-1')
    expect(m.source).toBe('client')
    expect(m.months).toHaveLength(3)
    expect(m.months[2]).toMatchObject({
      amount: 3000,
      saleCount: 1,
      topCategories: [
        { category: 'Robes', quantity: 2, amount: 2000 },
        { category: 'Autre', quantity: 1, amount: 1000 },
      ],
    })
    expect(m.months[0]).toMatchObject({ amount: 0, saleCount: 0, topCategories: [] })
    expect(m.topCategories[0]).toEqual({ category: 'Robes', quantity: 2, amount: 2000 })
  })
})

describe('fetchArrivalProfitability', () => {
  it('convertit les lignes SQL en camelCase', async () => {
    mocks.rpc.mockResolvedValue({
      data: [
        {
          arrival_id: 'a1',
          code: 'B-01',
          kind: 'balloon',
          status: 'received',
          origin_country: 'FR',
          supplier_name: null,
          order_date: '2026-09-01',
          received_date: '2026-09-20',
          is_test: false,
          cost: 100000,
          revenue: 40000,
          profit: -60000,
          recovery_percent: 40,
          remaining_to_recover: 60000,
          sold_units: 8,
          remaining_units: 22,
          product_count: 30,
        },
      ],
      error: null,
    })
    const [r] = await fetchArrivalProfitability('shop-1')
    expect(r).toEqual({
      arrivalId: 'a1',
      code: 'B-01',
      kind: 'balloon',
      status: 'received',
      originCountry: 'FR',
      supplierName: null,
      orderDate: '2026-09-01',
      receivedDate: '2026-09-20',
      isTest: false,
      cost: 100000,
      revenue: 40000,
      profit: -60000,
      recoveryPercent: 40,
      remainingToRecover: 60000,
      soldUnits: 8,
      remainingUnits: 22,
      productCount: 30,
    })
  })

  it('repli : calcul client, exemples exclus', async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: { code: '42883', message: 'no function' } })
    const row = {
      id: 'a1',
      code: 'C-01',
      kind: 'supplier_order',
      origin: 'CN',
      supplier: 'X',
      status: 'received',
      cost: 1000,
      revenue: 1500,
      profit: 500,
      recovery: 150,
      sold: 3,
      remaining: 2,
      productCount: 1,
      products: [],
    }
    mocks.arrivalProfitability.mockResolvedValue([
      { ...row, is_test: false },
      { ...row, id: 'demo', is_test: true },
    ])
    const rows = await fetchArrivalProfitability('shop-1')
    expect(rows).toHaveLength(1)
    expect(rows[0]).toMatchObject({
      arrivalId: 'a1',
      recoveryPercent: 150,
      remainingToRecover: 0,
      orderDate: null,
    })
    await fetchArrivalProfitability('shop-1')
    expect(mocks.rpc).toHaveBeenCalledTimes(1)
  })
})

describe('fetchEstimatedProfit', () => {
  it('appelle la fonction SQL avec la période', async () => {
    const data = { revenue: 1, netProfit: 1 }
    mocks.rpc.mockResolvedValue({ data, error: null })
    await expect(
      fetchEstimatedProfit('shop-1', { from: '2026-10-01', to: '2026-11-01' }),
    ).resolves.toEqual(data)
    expect(mocks.rpc).toHaveBeenCalledWith('shop_estimated_profit', {
      p_shop_id: 'shop-1',
      p_from: '2026-10-01',
      p_to: '2026-11-01',
      p_tz: 'Africa/Brazzaville',
      p_include_test: false,
    })
  })

  it('renvoie null si la fonction est absente, sans rappeler la base ensuite', async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: missing })
    await expect(fetchEstimatedProfit('shop-1')).resolves.toBeNull()
    await expect(fetchEstimatedProfit('shop-1')).resolves.toBeNull()
    expect(mocks.rpc).toHaveBeenCalledTimes(1)
  })

  it('propage 42501', async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: { code: '42501', message: 'Shop not found' } })
    await expect(fetchEstimatedProfit('x')).rejects.toMatchObject({ code: '42501' })
  })
})
