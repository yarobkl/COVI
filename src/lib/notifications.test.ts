import { describe, expect, it } from 'vitest'
import { buildNotifications, type NotificationSources } from './notifications'

const now = new Date('2026-10-15T12:00:00Z').getTime()
const hoursAgo = (h: number) => new Date(now - h * 3600_000).toISOString()

const product = (over: Partial<NotificationSources['products'][number]>) => ({
  id: 'p',
  name: 'Robe',
  status: 'active',
  quantity_on_hand: 5,
  is_unique_piece: false,
  is_test: false,
  updated_at: hoursAgo(1),
  ...over,
})

const empty: NotificationSources = { orders: [], products: [], testSales: [], audit: [] }

describe('buildNotifications', () => {
  it('is empty when nothing needs attention', () => {
    expect(buildNotifications({ ...empty, products: [product({})] }, now)).toEqual([])
  })

  it('lists new orders and orders accepted but unpaid for more than a day', () => {
    const list = buildNotifications(
      {
        ...empty,
        orders: [
          {
            id: 'a',
            reference: 'C-A',
            status: 'new',
            createdAt: hoursAgo(1),
            customerName: 'Awa',
            requestedTotalXaf: 5000,
          },
          {
            id: 'b',
            reference: 'C-B',
            status: 'accepted',
            createdAt: hoursAgo(30),
            customerName: 'Ben',
            requestedTotalXaf: 2500,
          },
          {
            id: 'c',
            reference: 'C-C',
            status: 'accepted',
            createdAt: hoursAgo(2),
            customerName: 'Cé',
            requestedTotalXaf: 100,
          },
        ],
      },
      now,
    )
    expect(list.map((n) => [n.kind, n.title])).toEqual([
      ['order', 'Nouvelle commande C-A'],
      ['anomaly', 'Commande C-B pas encore encaissée'],
    ])
    expect(list[0].page).toBe('commandes')
  })

  it('flags low and sold-out stock, but not unique pieces', () => {
    const list = buildNotifications(
      {
        ...empty,
        products: [
          product({ id: 'low', name: 'Jean', quantity_on_hand: 2 }),
          product({ id: 'out', name: 'Pagne', status: 'sold', quantity_on_hand: 0 }),
          product({
            id: 'old',
            name: 'Vieux',
            status: 'sold',
            quantity_on_hand: 0,
            updated_at: hoursAgo(24 * 10),
          }),
          product({ id: 'uniq', name: 'Veste', quantity_on_hand: 1, is_unique_piece: true }),
        ],
      },
      now,
    )
    expect(list.map((n) => n.title).sort()).toEqual(['Stock bas : Jean', 'Épuisé : Pagne'])
  })

  it('warns about TEST articles left in stock and recent test sales', () => {
    const list = buildNotifications(
      {
        ...empty,
        products: [product({ id: 't1', is_test: true }), product({ id: 't2', is_test: true })],
        testSales: [{ id: 's', sold_at: hoursAgo(1), total_amount: '5000.00' }],
      },
      now,
    )
    expect(list.map((n) => n.kind).sort()).toEqual(['anomaly', 'test'])
    expect(list.find((n) => n.kind === 'anomaly')?.title).toBe('2 articles TEST dans le stock')
  })

  it('groups failed PIN attempts by day and ignores other audit entries', () => {
    const list = buildNotifications(
      {
        ...empty,
        audit: [
          { id: 3, action: 'shared_cashier_pin_failed', at: '2026-10-15T10:00:00Z' },
          { id: 2, action: 'till_session_pin_failed', at: '2026-10-15T09:00:00Z' },
          { id: 1, action: 'public_order_paid', at: '2026-10-15T08:00:00Z' },
        ],
      },
      now,
    )
    expect(list).toHaveLength(1)
    expect(list[0]).toMatchObject({
      kind: 'pin',
      title: '2 codes PIN ratés',
      id: 'pin-2026-10-15-2-2',
    })
  })
})
