import { persistedUserId, supabase } from './supabase'
import {
  RetryLaterError,
  cacheServerStock,
  cachedStock,
  resumeSync,
  setSyncUser,
  withTimeout,
} from './offline'
import { paymentCode } from './format'
import type { TablesInsert } from './database.types'
import type { Product, Sale } from './types'
// Bind the offline sales queue to the signed-in account (deferred: auth callbacks must not call back into supabase).
// Without network, supabase-js reports no session (INITIAL_SESSION null) while it still keeps the
// expired one: the queue stays bound to that account so that sales can be recorded offline, and is
// only unbound on SIGNED_OUT (sign-out, or refresh token refused by the server).
supabase.auth.onAuthStateChange((event, session) => {
  const id = session?.user?.id ?? (event === 'SIGNED_OUT' ? null : persistedUserId())
  setTimeout(() => {
    setSyncUser(id)
    // A fresh token: whatever failed with the old one can be sent now, without waiting for the backoff.
    if (session && (event === 'SIGNED_IN' || event === 'TOKEN_REFRESHED')) resumeSync()
  }, 0)
})
// Bound right away from the persisted session: supabase-js may take ~25 s to report it offline.
const persistedUser = persistedUserId()
if (persistedUser) setSyncUser(persistedUser)

/**
 * Ensures a valid access token before a write. Without one, supabase-js would send the request
 * with the publishable key only: RLS would then return empty lists, and record_sale would fail with
 * a permission error that must not count as a refusal of the sale.
 */
async function requireSession() {
  const { data } = await supabase.auth.getSession()
  if (!data.session)
    throw new RetryLaterError('Session non disponible : jeton à rafraîchir (token).')
  return data.session
}
// Above this, the stock list falls back to the offline copy (slow or unreliable network).
const LIST_TIMEOUT_MS = 12000
export async function signedProductImage(path: string | null | undefined) {
  if (!path) return null
  const { data, error } = await supabase.storage
    .from('covi-product-images')
    .createSignedUrl(path, 3600)
  if (error) throw error
  return data.signedUrl
}
export async function listProducts(shopId: string, includeSold = false, includeTest = false) {
  const visible = (x: Product[]) => (includeTest ? x : x.filter((p) => !p.is_test))
  const offlineList = () =>
    visible(cachedStock<Product>(shopId).filter((x) => x.status === 'active'))
  // Offline, the copy is served at once instead of waiting for supabase-js to give up.
  if (!includeSold && !navigator.onLine) return offlineList()
  const fromServer = async () => {
    await requireSession()
    let q = supabase
      .from('products')
      .select('*')
      .eq('shop_id', shopId)
      .order('created_at', { ascending: false })
    if (!includeTest && includeSold) q = q.eq('is_test', false)
    if (!includeSold) q = q.eq('status', 'active')
    const { data, error } = await q
    if (error) throw error
    // `status` is narrowed to the values allowed by its CHECK constraint (see types.ts).
    const rows = await Promise.all(
      ((data ?? []) as Product[]).map(async (p) => ({
        ...p,
        image_url: await signedProductImage(p.image_path).catch(() => null),
      })),
    )
    if (includeSold) return rows
    cacheServerStock(shopId, rows)
    return visible(rows)
  }
  if (includeSold) return fromServer()
  try {
    return await withTimeout(fromServer(), LIST_TIMEOUT_MS)
  } catch (e) {
    if (cachedStock(shopId).length || !navigator.onLine) return offlineList()
    throw e
  }
}
export async function addProduct(
  shopId: string,
  input: Pick<
    TablesInsert<'products'>,
    | 'name'
    | 'category'
    | 'brand'
    | 'size'
    | 'initial_sale_price'
    | 'quantity_on_hand'
    | 'is_unique_piece'
    | 'arrival_id'
    | 'is_test'
  > & { image?: File | null },
) {
  const productId = crypto.randomUUID(),
    image = input.image
  let imagePath: string | null = null
  if (image) {
    if (
      !['image/jpeg', 'image/png', 'image/webp'].includes(image.type) ||
      image.size > 5 * 1024 * 1024
    )
      throw new Error('Choisissez une image JPG, PNG ou WebP de 5 Mo maximum.')
    const ext = image.type === 'image/jpeg' ? 'jpg' : image.type.split('/')[1],
      path = `${shopId}/${productId}-${crypto.randomUUID()}.${ext}`
    const { error: uploadError } = await supabase.storage
      .from('covi-product-images')
      .upload(path, image, { contentType: image.type, upsert: false })
    if (uploadError)
      throw new Error(
        'La photo n’a pas pu être enregistrée. Vérifiez votre connexion puis réessayez.',
      )
    imagePath = path
  }
  const { image: ignored, ...fields } = input
  void ignored
  const { data, error } = await supabase
    .from('products')
    .insert({ id: productId, shop_id: shopId, ...fields, image_path: imagePath })
    .select()
    .single()
  if (error) {
    if (imagePath) await supabase.storage.from('covi-product-images').remove([imagePath])
    throw error
  }
  return data as Product // status narrowed as in listProducts
}
export async function recordSale(
  shopId: string,
  productId: string,
  quantity: number,
  soldUnitPrice: number,
  paymentLabel: string,
  clientOperationId: string,
) {
  await requireSession()
  const { data, error } = await supabase.rpc('record_sale', {
    p_shop_id: shopId,
    p_product_id: productId,
    p_quantity: quantity,
    p_sold_unit_price: soldUnitPrice,
    p_payment_method: paymentCode(paymentLabel),
    p_client_operation_id: clientOperationId,
  })
  if (error) throw error
  return data
}
export async function listSales(shopId: string): Promise<Sale[]> {
  const { data, error } = await supabase
    .from('sales')
    .select(
      'id,sold_at,payment_method,total_amount,is_test,sale_items(quantity,initial_unit_price,sold_unit_price,products(name,brand,arrival_id,image_path,arrivals(code,kind)))',
    )
    .eq('shop_id', shopId)
    .order('sold_at', { ascending: false })
    .limit(500)
  if (error) throw error
  return Promise.all(
    (data ?? []).map(async (sale) => ({
      ...sale,
      sale_items: await Promise.all(
        (sale.sale_items ?? []).map(async (item) => ({
          ...item,
          products: item.products
            ? {
                ...item.products,
                image_url: await signedProductImage(item.products.image_path).catch(() => null),
              }
            : null,
        })),
      ),
    })),
  )
}
