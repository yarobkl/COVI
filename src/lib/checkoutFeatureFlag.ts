/** Deliberately OFF in production until the checkout SQL and Supabase RLS pass review.
 * Vite includes only the public boolean in the browser bundle; no secret belongs here.
 */
export const categoryCheckoutEnabled =
  import.meta.env.VITE_COVI_CATEGORY_CHECKOUT_ENABLED === 'true'
