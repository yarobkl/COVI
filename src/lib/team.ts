// Caisse multi-caissiers : appels aux fonctions SQL de l'équipe (migrations 20261014*), règles
// partagées avec la base (prix minimal, format du PIN) et messages dans les mots de la boutique.
// Contrat complet : docs/caisse-multi-caissiers.md.
import { supabase } from './supabase'
import type { PinResult } from './teamRules'

export {
  belowMinimumMessage,
  ownerPinResultMessage,
  minUnitPrice,
  minutesUntil,
  pinProblem,
  pinResultMessage,
  teamErrorMessage,
  type PinResult,
} from './teamRules'

/** A shop where the signed-in user is an active cashier (my_member_shops). */
export type MemberShop = {
  member_id: string
  shop_id: string
  shop_name: string
  shop_city: string | null
  shop_country: string | null
  shop_currency: string
  display_name: string
  role: string
  can_view_shop_sales: boolean
  max_discount_pct: number
  pin_set: boolean
  pin_must_change: boolean
}

/** A member of the owner's team (list_shop_members): never the PIN, only whether it is set. */
export type TeamMember = {
  id: string
  user_id: string
  display_name: string
  role: string
  active: boolean
  can_view_shop_sales: boolean
  max_discount_pct: number
  created_at: string
  updated_at: string
  deactivated_at: string | null
  pin_set: boolean
  pin_must_change: boolean
  pin_locked_until: string | null
}

export type PendingInvite = {
  id: string
  display_name: string
  can_view_shop_sales: boolean
  max_discount_pct: number
  created_at: string
  expires_at: string
}

/** Invite created by the owner: the code is shown once and never stored in clear. */
export type CreatedInvite = PendingInvite & { invite_id: string; code: string }

/** Till session on the owner's shared device (case b): kept in memory / sessionStorage only. */
export type TillSession = {
  shopId: string
  memberId: string
  displayName: string
  maxDiscountPct: number
  token: string
  expiresAt: string
  /** The cashier's account (sales.seller_id): « ses ventes » at the counter. */
  sellerId?: string
  /** The cashier may see every sale of the shop (otherwise only theirs). */
  canViewShopSales?: boolean
}

export type RedeemResult =
  | {
      status: 'joined'
      member_id: string
      shop_id: string
      shop_name: string
      display_name: string
    }
  | { status: 'invalid' }
  | { status: 'locked'; retry_after: string }

const num = (x: unknown) => Number(x ?? 0)

async function rpc<T>(promise: PromiseLike<{ data: unknown; error: unknown }>): Promise<T> {
  const { data, error } = await promise
  if (error) throw error
  return data as T
}

export const myMemberShops = () =>
  rpc<MemberShop[]>(supabase.rpc('my_member_shops')).then((rows) =>
    (rows ?? []).map((r) => ({ ...r, max_discount_pct: num(r.max_discount_pct) })),
  )

export const redeemMemberInvite = (code: string) =>
  rpc<RedeemResult>(supabase.rpc('redeem_member_invite', { p_code: code }))

export const setMyPin = (shopId: string, newPin: string, currentPin?: string) =>
  rpc<PinResult>(
    supabase.rpc('set_my_pin', {
      p_shop_id: shopId,
      p_new_pin: newPin,
      ...(currentPin ? { p_current_pin: currentPin } : {}),
    }),
  )

export const verifyMyPin = (shopId: string, pin: string) =>
  rpc<PinResult>(supabase.rpc('verify_my_pin', { p_shop_id: shopId, p_pin: pin }))

export const listShopMembers = (shopId: string) =>
  rpc<TeamMember[]>(supabase.rpc('list_shop_members', { p_shop_id: shopId })).then((rows) =>
    (rows ?? []).map((r) => ({ ...r, max_discount_pct: num(r.max_discount_pct) })),
  )

export const listMemberInvites = (shopId: string) =>
  rpc<PendingInvite[]>(supabase.rpc('list_member_invites', { p_shop_id: shopId }))

export const createMemberInvite = (
  shopId: string,
  displayName: string,
  canViewShopSales: boolean,
  maxDiscountPct: number,
) =>
  rpc<CreatedInvite>(
    supabase.rpc('create_member_invite', {
      p_shop_id: shopId,
      p_display_name: displayName,
      p_can_view_shop_sales: canViewShopSales,
      p_max_discount_pct: maxDiscountPct,
    }),
  )

export const revokeMemberInvite = (inviteId: string) =>
  rpc<boolean>(supabase.rpc('revoke_member_invite', { p_invite_id: inviteId }))

export const setMemberActive = (memberId: string, active: boolean) =>
  rpc<unknown>(supabase.rpc('set_member_active', { p_member_id: memberId, p_active: active }))

export const setMemberPermissions = (
  memberId: string,
  canViewShopSales: boolean,
  maxDiscountPct: number,
) =>
  rpc<unknown>(
    supabase.rpc('set_member_permissions', {
      p_member_id: memberId,
      p_can_view_shop_sales: canViewShopSales,
      p_max_discount_pct: maxDiscountPct,
    }),
  )

export const ownerResetMemberPin = (memberId: string) =>
  rpc<unknown>(supabase.rpc('owner_reset_member_pin', { p_member_id: memberId }))

/** Opens a till session for `member` after checking THEIR PIN (owner's device). */
export async function openTillSession(
  shopId: string,
  memberId: string,
  pin: string,
): Promise<{ session: TillSession } | { refused: PinResult }> {
  const r = await rpc<
    | (PinResult & { status: Exclude<PinResult['status'], 'ok'> })
    | {
        status: 'ok'
        token: string
        expires_at: string
        member_id: string
        user_id?: string
        display_name: string
        max_discount_pct: number
        can_view_shop_sales?: boolean
      }
  >(supabase.rpc('open_till_session', { p_shop_id: shopId, p_member_id: memberId, p_pin: pin }))
  if (r.status !== 'ok') return { refused: r }
  return {
    session: {
      shopId,
      memberId: r.member_id,
      displayName: r.display_name,
      maxDiscountPct: num(r.max_discount_pct),
      token: r.token,
      expiresAt: r.expires_at,
      sellerId: r.user_id,
      canViewShopSales: Boolean(r.can_view_shop_sales),
    },
  }
}

export const closeTillSession = (shopId: string, token: string) =>
  rpc<boolean>(supabase.rpc('close_till_session', { p_shop_id: shopId, p_token: token }))

// Code du responsable et mode comptoir (migration 20261014090200_owner_pin) ---------------------

/** Owner PIN state (never the PIN): set or not, locked until when. */
export type OwnerPinStatus = { pin_set: boolean; locked_until: string | null }

export const ownerPinStatus = (shopId: string) =>
  rpc<OwnerPinStatus | null>(supabase.rpc('owner_pin_status', { p_shop_id: shopId })).then(
    (r): OwnerPinStatus => ({
      pin_set: Boolean(r?.pin_set),
      locked_until: r?.locked_until ?? null,
    }),
  )

export const setOwnerPin = (shopId: string, newPin: string, currentPin?: string) =>
  rpc<PinResult>(
    supabase.rpc('set_owner_pin', {
      p_shop_id: shopId,
      p_new_pin: newPin,
      ...(currentPin ? { p_current_pin: currentPin } : {}),
    }),
  )

/** Forgotten owner PIN: erased (open till sessions closed), a new one is chosen right after. */
export const resetOwnerPin = (shopId: string) =>
  rpc<boolean>(supabase.rpc('reset_owner_pin', { p_shop_id: shopId }))

/**
 * Leaves counter mode: the server checks the OWNER's PIN, then closes the till session `token`.
 * Only `{ status: 'ok' }` gives the full application back.
 */
export const leaveCounterMode = (shopId: string, pin: string, token?: string) =>
  rpc<PinResult>(
    supabase.rpc('leave_counter_mode', {
      p_shop_id: shopId,
      p_pin: pin,
      ...(token ? { p_token: token } : {}),
    }),
  )

/** Reopens a till locked after inactivity, with the PIN of the cashier of the session. */
export const unlockTillSession = (shopId: string, token: string, pin: string) =>
  rpc<PinResult>(
    supabase.rpc('unlock_till_session', { p_shop_id: shopId, p_token: token, p_pin: pin }),
  )
