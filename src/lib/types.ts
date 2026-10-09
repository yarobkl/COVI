// Domain types shared by the data layer and the pages, derived from the generated Supabase types
// (src/lib/database.types.ts). Text columns restricted by a CHECK constraint are narrowed to their
// allowed values here, since the generator types them as plain strings.
import type { Tables } from './database.types'

/** The signed-in owner's shop, as loaded by AuthGate and edited in the settings. */
export type Shop = Pick<Tables<'shops'>, 'id' | 'name' | 'city' | 'country' | 'currency'>

/** CHECK (kind in ('supplier_order','balloon')). */
export type ArrivalKind = 'supplier_order' | 'balloon'
export type Arrival = Omit<Tables<'arrivals'>, 'kind'> & { kind: ArrivalKind }

/** CHECK (status in ('active','sold','archived')). */
export type ProductStatus = 'active' | 'sold' | 'archived'
/** A product row, with a short-lived signed URL of its photo when it has one. */
export type Product = Omit<Tables<'products'>, 'status'> & {
  status: ProductStatus
  image_url?: string | null
}

export type Expense = Tables<'shop_expenses'>

/** One line of a sale, with its product (signed photo URL) and the product's arrival. */
export type SaleLine = Pick<
  Tables<'sale_items'>,
  'quantity' | 'initial_unit_price' | 'sold_unit_price'
> & {
  products:
    | (Pick<Tables<'products'>, 'name' | 'brand' | 'arrival_id' | 'image_path'> & {
        image_url: string | null
        arrivals: Pick<Tables<'arrivals'>, 'code' | 'kind'> | null
      })
    | null
}
/** A sale as listed in the history (`listSales`). */
export type Sale = Pick<
  Tables<'sales'>,
  'id' | 'sold_at' | 'payment_method' | 'total_amount' | 'is_test'
> & { sale_items: SaleLine[] }
/** A sale line flattened with its sale's id, date, payment method and test flag. */
export type SoldItem = SaleLine & Pick<Sale, 'id' | 'sold_at' | 'payment_method' | 'is_test'>
