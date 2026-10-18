import { supabase } from './supabase'

type FutureCashierRpc = {
  rpc: (
    name:
      | 'create_checkout_cashier_invite'
      | 'redeem_checkout_cashier_invite'
      | 'set_checkout_cashier_active'
      | 'list_checkout_cashiers'
      | 'get_my_checkout_cashier_shops'
      | 'set_checkout_cashier_pin',
    args: Record<string, unknown>,
  ) => PromiseLike<{ data: unknown; error: { message: string } | null }>
}

const UUID = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i
const PIN = /^[0-9]{6,8}$/
const rpc = supabase as unknown as FutureCashierRpc

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw new Error('Réponse de gestion des caissiers invalide.')
  return value as Record<string, unknown>
}
async function request(
  name: Parameters<FutureCashierRpc['rpc']>[0],
  args: Record<string, unknown>,
) {
  const { data, error } = await rpc.rpc(name, args)
  if (error) throw new Error(error.message)
  return data
}
function validShop(id: string) {
  if (!UUID.test(id)) throw new Error('Identifiant de boutique invalide.')
}

export type CashierMembership = {
  shopId: string
  shopName: string
  firstName: string
  pinConfigured: boolean
}

export type CashierTeamMember = {
  userId: string
  firstName: string
  active: boolean
  pinConfigured: boolean
}

export async function myCashierShops(): Promise<CashierMembership[]> {
  const data = await request('get_my_checkout_cashier_shops', {})
  if (!Array.isArray(data) || data.length > 50) throw new Error('Liste des boutiques invalide.')
  return data.map((item) => {
    const row = record(item)
    if (
      !UUID.test(String(row.shopId)) ||
      typeof row.shopName !== 'string' ||
      !row.shopName ||
      typeof row.firstName !== 'string' ||
      !row.firstName ||
      typeof row.pinConfigured !== 'boolean'
    )
      throw new Error('Boutique caissier invalide.')
    return row as CashierMembership
  })
}

export async function createCashierInvite(shopId: string, firstName: string) {
  validShop(shopId)
  const data = record(
    await request('create_checkout_cashier_invite', {
      p_shop_id: shopId,
      p_first_name: firstName.trim(),
    }),
  )
  if (!UUID.test(String(data.inviteCode)) || typeof data.expiresAt !== 'string')
    throw new Error('Code invitation invalide.')
  return { inviteCode: data.inviteCode as string, expiresAt: data.expiresAt as string }
}

export async function redeemCashierInvite(inviteCode: string) {
  if (!UUID.test(inviteCode)) throw new Error('Le code d’invitation est invalide.')
  const row = record(
    await request('redeem_checkout_cashier_invite', {
      p_invite_code: inviteCode,
    }),
  )
  if (!UUID.test(String(row.shopId))) throw new Error('Invitation refusée.')
  return row.shopId as string
}

export async function listCashiers(shopId: string): Promise<CashierTeamMember[]> {
  validShop(shopId)
  const data = await request('list_checkout_cashiers', { p_shop_id: shopId })
  if (!Array.isArray(data) || data.length > 250) throw new Error('Équipe caisse invalide.')
  return data.map((item) => {
    const row = record(item)
    if (
      !UUID.test(String(row.userId)) ||
      typeof row.firstName !== 'string' ||
      typeof row.active !== 'boolean' ||
      typeof row.pinConfigured !== 'boolean'
    )
      throw new Error('Caissier invalide.')
    return row as CashierTeamMember
  })
}

export async function setCashierActive(shopId: string, userId: string, active: boolean) {
  validShop(shopId)
  if (!UUID.test(userId)) throw new Error('Caissier invalide.')
  const result = await request('set_checkout_cashier_active', {
    p_shop_id: shopId,
    p_cashier_user_id: userId,
    p_active: active,
  })
  if (result !== true) throw new Error('Modification du caissier refusée.')
}

export async function setPersonalCashierPin(shopId: string, newPin: string, currentPin?: string) {
  validShop(shopId)
  if (!PIN.test(newPin) || (currentPin !== undefined && !PIN.test(currentPin)))
    throw new Error('Le code personnel doit avoir 6 à 8 chiffres.')
  const accepted = await request('set_checkout_cashier_pin', {
    p_shop_id: shopId,
    p_new_pin: newPin,
    p_current_pin: currentPin ?? null,
  })
  if (accepted !== true) throw new Error('Ancien code incorrect ou compte temporairement bloqué.')
}

export function validCashierPin(pin: string): boolean {
  return PIN.test(pin)
}
