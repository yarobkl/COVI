import { supabase } from './supabase'

export type RestaurantStaffRole = 'waiter' | 'kitchen' | 'cashier'
export type RestaurantStaffSpace = {
  shop_id: string
  shop_name: string
  staff_role: RestaurantStaffRole
  display_name: string
}

/** A signed-in employee sees only workplaces where their access is active. */
export async function myRestaurantStaffSpaces(): Promise<RestaurantStaffSpace[]> {
  const { data, error } = await supabase.rpc('restaurant_staff_my_spaces')
  if (error) throw error
  if (!data || data.length > 50) throw new Error('Liste des restaurants indisponible.')
  return data.filter(
    (x): x is RestaurantStaffSpace =>
      typeof x.shop_id === 'string' &&
      typeof x.shop_name === 'string' &&
      typeof x.display_name === 'string' &&
      (x.staff_role === 'waiter' || x.staff_role === 'kitchen' || x.staff_role === 'cashier'),
  )
}
