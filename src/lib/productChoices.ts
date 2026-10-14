import type { Product } from './types'

/** Existing shop choices come first; the most common clothing options are preloaded. */
const DEFAULT_NAMES = ['Jean', 'T-shirt', 'Robe', 'Chemise', 'Chaussures']
const DEFAULT_CATEGORIES = ['Jeans', 'T-shirts', 'Robes', 'Chemises', 'Chaussures']
const DEFAULT_SIZES = ['Taille unique', 'XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL']

function choices(base: readonly string[], saved: (string | null)[]) {
  return [...new Set([...base, ...saved.filter((v): v is string => Boolean(v?.trim()))])]
}

export function productChoices(products: readonly Product[]) {
  return {
    names: choices(DEFAULT_NAMES, products.map((p) => p.name)),
    categories: choices(DEFAULT_CATEGORIES, products.map((p) => p.category)),
    brands: choices([], products.map((p) => p.brand)),
    sizes: choices(DEFAULT_SIZES, products.map((p) => p.size)),
  }
}
