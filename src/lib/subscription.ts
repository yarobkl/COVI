// The owner's COVI subscription, as far as the shop screens need it: may the shop still write
// (sell, add stock…), and may a shop be added. The database decides (trigger
// `covi_subscription_write_guard`, migration 20261010180000, and `create_my_shop`): the screens
// read `covi_my_subscription_state()` (migration 20261010182000) to say it before an action fails.
// On a database without that function, the same rules are applied to the rows the owner may read
// (RLS of 20261010170000).
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
  /**
   * How many shops the account may hold for `create_my_shop` right now: V1 → 1; active within
   * its period → its quota; anything else (suspended, past, grace, unpaid) → 0. Null: unknown.
   */
  addLimit: number | null
  /** Server answer of `covi_my_subscription_state` (null: not asked or not available). */
  canAddShop: boolean | null
  /** Subscription status (« suspended »…); null for a V1 owner or when unknown. */
  status: string | null
  /**
   * `covi_my_subscription_state()` failed for another reason than its absence (network, server
   * error): the state is not known. Nothing is blocked nor announced as active or suspended; the
   * screens only say it was not verified, until a later check succeeds.
   */
  unverified?: boolean
}

export const OPEN_ACCESS: SubscriptionAccess = {
  readOnly: false,
  shopLimit: null,
  addLimit: null,
  canAddShop: null,
  status: null,
}

/** The check failed (not the function missing): open, as OPEN_ACCESS, but said unverified. */
export const UNVERIFIED_ACCESS: SubscriptionAccess = { ...OPEN_ACCESS, unverified: true }

const time = (value: string | null) => (value ? Date.parse(value) : NaN)

/**
 * Fallback when `covi_my_subscription_state` is missing. Same rule as
 * `covi_shop_subscription_writable` (migration 20261010180000), for one owner: no SaaS account
 * (V1 owner) → writable; first invoice never paid → writable; active within its period →
 * writable; grace before `grace_until` → writable; anything else → read only. Adding a shop
 * follows `create_my_shop`: V1 → 1 shop; otherwise an active subscription within its period.
 */
export function subscriptionAccess(
  hasAccount: boolean,
  rows: readonly SubscriptionRow[],
  now: Date = new Date(),
): SubscriptionAccess {
  if (!hasAccount)
    return { readOnly: false, shopLimit: 1, addLimit: 1, canAddShop: null, status: null }
  const at = now.getTime()
  const inPeriod = (s: SubscriptionRow) =>
    s.status === 'active' && time(s.period_start) <= at && time(s.period_end) > at
  const writable = rows.find(
    (s) =>
      (s.status === 'pending_payment' && !s.period_start) ||
      inPeriod(s) ||
      (s.status === 'grace' && time(s.grace_until) > at),
  )
  // The current subscription (one per owner): the writable one, else the most relevant one left.
  const current =
    writable ??
    rows.find((s) => ['active', 'grace', 'suspended', 'pending_payment'].includes(s.status)) ??
    rows[0]
  const active = rows.find(inPeriod)
  return {
    readOnly: !writable,
    shopLimit: current ? current.shop_limit : null,
    addLimit: active ? active.shop_limit : 0,
    canAddShop: null,
    status: current?.status ?? null,
  }
}

/** The jsonb returned by `covi_my_subscription_state()` (migration 20261010182000). */
export type SubscriptionState = {
  status: string | null
  writable: boolean
  shopLimit: number | null
  shopCount: number
  canAddShop: boolean
  periodEnd: string | null
  isLegacyV1: boolean
}

export function accessFromState(state: SubscriptionState): SubscriptionAccess {
  return {
    readOnly: !state.writable,
    shopLimit: state.shopLimit,
    // Same rule as create_my_shop: V1 → 1 shop; an active subscription within its period (the
    // only 'active' that is writable) → its quota; otherwise none.
    addLimit: state.isLegacyV1
      ? 1
      : state.status === 'active' && state.writable
        ? state.shopLimit
        : 0,
    canAddShop: state.canAddShop,
    status: state.status,
  }
}

/** The SQL function does not exist (yet): PostgREST PGRST202, Postgres 42883. */
const isMissingFunction = (error: { code?: unknown; message?: unknown }) =>
  error.code === 'PGRST202' ||
  error.code === '42883' ||
  String(error.message ?? '').includes('Could not find the function')

// The covi_* tables and functions are not in the generated types (they come with the SaaS
// migrations).
const untyped = supabase as unknown as SupabaseClient

async function loadFromTables(userId: string): Promise<SubscriptionAccess> {
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
}

/**
 * Reads the signed-in owner's subscription: `covi_my_subscription_state()`, or the same rules on
 * the readable tables when the function does not exist yet (PGRST202 / 42883). Never blocks the
 * shop on doubt: without the SaaS migrations, without network, or on any read error, the shop
 * stays open and the database still refuses what it must refuse (see `isSubscriptionInactive`).
 * When the function exists but its call fails, the answer is UNVERIFIED_ACCESS. The fallback on
 * the tables keeps its former behaviour (OPEN_ACCESS on error) during the move to the function.
 */
export async function loadSubscriptionAccess(userId: string): Promise<SubscriptionAccess> {
  let answer: { data: unknown; error: { code?: unknown; message?: unknown } | null }
  try {
    answer = await untyped.rpc('covi_my_subscription_state')
  } catch {
    return UNVERIFIED_ACCESS
  }
  const { data, error } = answer
  if (!error && data && typeof data === 'object') return accessFromState(data as SubscriptionState)
  if (error && isMissingFunction(error)) {
    try {
      return await loadFromTables(userId)
    } catch {
      return OPEN_ACCESS
    }
  }
  return UNVERIFIED_ACCESS
}

/**
 * Why « Ajouter une boutique » is not possible for an account holding `shopCount` shops, or null
 * when it is (or when it cannot be known: the server then decides, and its refusal is translated).
 */
export function addShopBlockedReason(access: SubscriptionAccess, shopCount: number): string | null {
  const blocked =
    access.canAddShop === false || (access.addLimit !== null && shopCount >= access.addLimit)
  if (!blocked) return null
  if (access.addLimit === 0 || access.readOnly)
    return access.status === 'suspended'
      ? 'Votre abonnement est suspendu. Contactez COVI pour le renouveler.'
      : 'Votre abonnement n’est pas actif. Contactez COVI pour le renouveler.'
  const n = access.shopLimit ?? shopCount
  return `Votre abonnement couvre ${n} boutique${n > 1 ? 's' : ''}. Pour en ajouter une, contactez COVI.`
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
