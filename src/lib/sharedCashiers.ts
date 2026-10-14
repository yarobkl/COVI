import { supabase } from './supabase'
import type { TillSession } from './team'
import type { PinResult } from './teamRules'

export type SharedCashier = {
  id: string
  display_name: string
  active: boolean
  pin_set: boolean
  max_discount_pct: number
  can_view_shop_sales: boolean
}

async function rpc<T>(request: PromiseLike<{ data: unknown; error: unknown }>): Promise<T> {
  const { data, error } = await request
  if (error) throw error
  return data as T
}

/** No extra employee login: these are PIN-protected profiles under the shared shop account. */
export const listSharedCashiers = (shopId: string) =>
  rpc<SharedCashier[]>(supabase.rpc('list_shared_cashiers', { p_shop_id: shopId }))

export const createSharedCashier = (
  shopId: string,
  name: string,
  pin: string,
  discount: number,
  canViewShopSales = false,
) =>
  rpc<SharedCashier>(
    supabase.rpc('create_shared_cashier', {
      p_shop_id: shopId,
      p_display_name: name,
      p_pin: pin,
      p_max_discount_pct: discount,
      p_can_view_shop_sales: canViewShopSales,
    }),
  )

export const setSharedCashierActive = (cashierId: string, active: boolean) =>
  rpc<boolean>(
    supabase.rpc('set_shared_cashier_active', {
      p_cashier_id: cashierId,
      p_active: active,
    }),
  )

export async function openSharedCashierTill(
  shopId: string,
  cashierId: string,
  pin: string,
): Promise<{ session: TillSession } | { refused: PinResult }> {
  const result = await rpc<
    PinResult & {
      token?: string
      session_id?: string
      expires_at?: string
      member_id?: string
      user_id?: string
      display_name?: string
      max_discount_pct?: number
      can_view_shop_sales?: boolean
    }
  >(
    supabase.rpc('open_shared_cashier_till', {
      p_shop_id: shopId,
      p_cashier_id: cashierId,
      p_pin: pin,
    }),
  )
  if (result.status !== 'ok') return { refused: result }
  if (!result.token || !result.expires_at) throw new Error('Session de caisse incomplète.')
  return {
    session: {
      shopId,
      memberId: cashierId,
      cashierProfileId: cashierId,
      displayName: result.display_name ?? '',
      maxDiscountPct: Number(result.max_discount_pct ?? 0),
      token: result.token,
      expiresAt: result.expires_at,
      sellerId: result.user_id,
      canViewShopSales: Boolean(result.can_view_shop_sales),
    },
  }
}

export const unlockSharedCashierTill = (shopId: string, token: string, pin: string) =>
  rpc<PinResult>(
    supabase.rpc('unlock_shared_cashier_till', {
      p_shop_id: shopId,
      p_token: token,
      p_pin: pin,
    }),
  )

export const closeSharedCashierTill = (shopId: string, token: string) =>
  rpc<boolean>(
    supabase.rpc('close_shared_cashier_till', {
      p_shop_id: shopId,
      p_token: token,
    }),
  )
