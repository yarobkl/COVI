import { supabase } from './supabase'

/**
 * Owner-only signal: a database notification merely triggers a fresh, authorized
 * RPC read. Never display or trust the change payload in the cashier interface.
 * The checkout_orders table must be added to the Supabase Realtime publication
 * in a reviewed migration; polling remains the fallback until that is done.
 */
export function watchCheckoutOrderUpdates(shopId: string, refresh: () => void): () => void {
  const channel = supabase
    .channel('covi-checkout-inbox:' + shopId)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'checkout_orders',
        filter: 'shop_id=eq.' + shopId,
      },
      () => refresh(),
    )
    .subscribe()

  return () => {
    void supabase.removeChannel(channel)
  }
}
