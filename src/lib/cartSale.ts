import { supabase } from './supabase'
import { paymentCode } from './format'

export type CartSaleItem = { product_id: string; quantity: number; sold_unit_price: number }

/** Caller must persist and reuse operationId for retries of this immutable cart. */
export async function recordCartSale(shopId: string, items: readonly CartSaleItem[], paymentLabel: string, operationId: string) {
  const { data: session } = await supabase.auth.getSession()
  if (!session.session) throw new Error('Authentication required')
  const { data, error } = await supabase.rpc('record_cart_sale', {
    p_shop_id: shopId,
    p_items: items.map(({ product_id, quantity, sold_unit_price }) => ({ product_id, quantity, sold_unit_price })),
    p_payment_method: paymentCode(paymentLabel),
    p_client_operation_id: operationId,
  })
  if (error) throw error
  return data
}
