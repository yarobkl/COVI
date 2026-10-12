import { describe, expect, it } from 'vitest'
import type { ArrivalProfit } from '../../lib/operations'
import type { Arrival } from '../../lib/types'
import { groupArrivals, nextArrivalCode, nextStepOf, recoveryOf, stampOf } from './arrivalMath'

describe('recoveryOf', () => {
  it('a bale on its way back: 186 000 of 250 000, 64 000 still to recover', () => {
    expect(recoveryOf(250000, 186000)).toEqual({
      cost: 250000,
      revenue: 186000,
      percent: 74,
      toRecover: 64000,
      gained: 0,
      done: false,
    })
  })
  it('paid back: what it brought on top', () => {
    expect(recoveryOf(360000, 700000)).toMatchObject({ percent: 194, gained: 340000, done: true })
    expect(recoveryOf(100000, 100000)).toMatchObject({ toRecover: 0, gained: 0, done: true })
  })
  it('nothing paid: never « rentabilisé », no division by zero', () => {
    expect(recoveryOf(0, 5000)).toMatchObject({ percent: 0, done: false })
  })
})

describe('stampOf', () => {
  const a = (status: string, kind: Arrival['kind'] = 'supplier_order') => ({ status, kind })
  it('says each step in shop words, never « brouillon »', () => {
    expect(stampOf(a('draft')).label).toBe('À commander')
    expect(stampOf(a('ordered')).label).toBe('Commandé')
    expect(stampOf(a('in_transit'))).toEqual({ label: 'En route', tone: 'transit' })
    expect(stampOf(a('received'))).toEqual({ label: 'Reçu', tone: 'received' })
    expect(stampOf(a('received', 'balloon')).label).toBe('Ouvert')
    expect(stampOf(a('received', 'balloon'), { done: true })).toEqual({
      label: 'Rentabilisé',
      tone: 'done',
    })
  })
})

describe('nextStepOf', () => {
  const arrival = (status: string) => ({
    status,
    code: 'CMD-0412',
    kind: 'supplier_order' as const,
  })
  it('goes draft → ordered → in transit → received, each with its confirmation', () => {
    expect(nextStepOf(arrival('draft'))).toMatchObject({
      status: 'ordered',
      action: 'C’est commandé',
      confirm: 'Marquer commandé',
    })
    expect(nextStepOf(arrival('ordered'))).toMatchObject({
      status: 'in_transit',
      action: 'C’est en route',
      confirm: 'Marquer en route',
    })
    const receive = nextStepOf(arrival('in_transit'), new Date(2026, 9, 8))
    expect(receive).toMatchObject({ status: 'received', confirm: 'Confirmer la réception' })
    expect(receive?.text).toContain('jeudi 8 octobre')
    expect(nextStepOf(arrival('received'))).toBeNull()
  })
})

describe('nextArrivalCode', () => {
  it('follows the readable codes and ignores the old random ones', () => {
    expect(nextArrivalCode('balloon', ['BAL-003', 'CHN-001', 'BAL-001'])).toBe('BAL-004')
    expect(nextArrivalCode('supplier_order', ['CMD-3F9A2C', 'CMD-0412'])).toBe('CMD-413')
    expect(nextArrivalCode('supplier_order', [])).toBe('CMD-001')
    expect(nextArrivalCode('balloon', ['BAL-003'], 2)).toBe('BAL-006')
  })
})

describe('groupArrivals', () => {
  const arrival = (id: string, status: string) => ({ id, status }) as Arrival
  const profit = (id: string, cost: number, revenue: number) =>
    ({ id, cost, revenue }) as ArrivalProfit
  it('arrivals to receive first, then received ones not paid back, then paid back', () => {
    const groups = groupArrivals(
      [
        arrival('ind', 'received'),
        arrival('cmd', 'in_transit'),
        arrival('bal', 'received'),
        arrival('new', 'draft'),
      ],
      [profit('ind', 360000, 700000), profit('bal', 250000, 186000)],
    )
    expect(groups.waiting.map((l) => l.arrival.id)).toEqual(['cmd', 'new'])
    expect(groups.received.map((l) => l.arrival.id)).toEqual(['bal', 'ind'])
  })
})
