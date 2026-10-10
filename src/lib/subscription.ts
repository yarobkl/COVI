// The owner's COVI subscription, as far as the shop screens need it: may the shop still write
// (sell, add stock…), and how many shops does it cover. The database decides (trigger
// `covi_subscription_write_guard`, migration 20261010180000): this only reads the same rows the
// owner may read (RLS of 20261010170000) so that the screens can say it before an action fails.
import type { SupabaseClient } from '@supabase/supabase-js'
import { supabase } from './supabase'

export type SubscriptionRow = {
  status: string
  shop_limit: number
  period_start: string | null
  period_end: string | null
  grace_until: string | null
}

export type SubscriptionAccess = {
  /** Suspended, cancelled or past its period: data can be read, nothing can be written. */
  readOnly: boolean
  /** Shops covered by the subscription; null when unknown. A V1 owner without account: 1. */
  shopLimit: number | null
}

export const OPEN_ACCESS: SubscriptionAccess = { readOnly: false, shopLimit: null }

const time = (value: string | null) => (value ? Date.parse(value) : NaN)

/**
 * Same rule as `covi_shop_subscription_writable` (migration 20261010180000), for one owner:
 * no SaaS account (V1 owner) → writable; first invoice never paid → writable; active within its
 * period → writable; grace before `grace_until` → writable; anything else → read only.
 */
export function subscriptionAccess(
  hasAccount: boolean,
  rows: readonly SubscriptionRow[],
  now: Date = new Date(),
): SubscriptionAccess {
  if (!hasAccount) return { readOnly: false, shopLimit: 1 }
  const at = now.getTime()
  const writable = rows.find(
    (s) =>
      (s.status === 'pending_payment' && !s.period_start) ||
      (s.status === 'active' && time(s.period_start) <= at && time(s.period_end) > at) ||
      (s.status === 'grace' && time(s.grace_until) > at),
  )
  // The current subscription (one per owner): the writable one, else the most relevant one left.
  const current =
    writable ??
    rows.find((s) => ['active', 'grace', 'suspended', 'pending_payment'].includes(s.status)) ??
    rows[0]
  return { readOnly: !writable, shopLimit: current ? current.shop_limit : null }
}

// The covi_* tables are not in the generated types (they come with the SaaS migrations).
const untyped = supabase as unknown as SupabaseClient

/**
 * Reads the signed-in owner's subscription. Never blocks the shop on doubt: without the SaaS
 * tables (database not migrated), without network, or on any read error, the shop stays open and
 * the database still refuses what it must refuse (see `isSubscriptionInactive`).
 */
export async function loadSubscriptionAccess(userId: string): Promise<SubscriptionAccess> {
  try {
    const account = await untyped
      .from('covi_owner_accounts')
      .select('id')
      .eq('user_id', userId)
      .maybeSingle()
    if (account.error) return OPEN_ACCESS
    if (!account.data) return subscriptionAccess(false, [])
    const subs = await untyped
      .from('covi_subscriptions')
      .select('status,shop_limit,period_start,period_end,grace_until')
      .eq('owner_account_id', (account.data as { id: string }).id)
    if (subs.error) return OPEN_ACCESS
    return subscriptionAccess(true, (subs.data ?? []) as SubscriptionRow[])
  } catch {
    return OPEN_ACCESS
  }
}

const messageOf = (error: unknown) =>
  String(
    (error as { message?: unknown } | null | undefined)?.message ??
      (typeof error === 'string' ? error : ''),
  ).toLowerCase()

/** The database refused a write because the subscription is suspended or over (P0001). */
export const isSubscriptionInactive = (error: unknown) =>
  messageOf(error).includes('subscription inactive')

// When a write is refused for that reason anywhere in the app, the shell switches to read only
// (in case the subscription could not be read beforehand, or was suspended meanwhile).
type Listener = () => void
const listeners = new Set<Listener>()

export function onSubscriptionInactive(listener: Listener) {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

/** Called by the error translations: deferred, as they may run while a component renders. */
export function reportSubscriptionInactive() {
  queueMicrotask(() => listeners.forEach((l) => l()))
}
