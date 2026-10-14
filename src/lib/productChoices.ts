import type { Product } from './types'

/** Use saved choices from this boutique, with a few useful starting suggestions. */
function distinct(values: (string | null)[]) {
  return [...new Set(values.filter((value): value is string => Boolean(value)))]
}

export function productChoices(products: readonly Product[]) {
  return {
    names: distinct(['Jean', 'T-shirt', 'Robe', ...products.map((p) => p.name)]),
    categories: distinct(['Jeans', 'T-shirts', 'Robes', ...products.map((p) => p.category)]),
    brands: distinct(products.map((p) => p.brand)),
    sizes: distinct(['S', 'M', 'L', 'XL', 'XXL', ...products.map((p) => p.size)]),
  }
}
