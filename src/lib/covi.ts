import { supabase } from './supabase'
import { cacheServerStock, cachedStock, setSyncUser } from './offline'
import { paymentCode } from './format'
import type { TablesInsert } from './database.types'
import type { Product, Sale } from './types'
// Bind the offline sales queue to the signed-in account (deferred: auth callbacks must not call back into supabase).
supabase.auth.onAuthStateChange((_event, session) => {
  const id = session?.user?.id ?? null
  setTimeout(() => setSyncUser(id), 0)
})
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
  try {
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
  } catch (e) {
    if (!includeSold) {
      const local = cachedStock<Product>(shopId)
      if (local.length || !navigator.onLine)
        return visible(local.filter((x) => x.status === 'active'))
    }
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
