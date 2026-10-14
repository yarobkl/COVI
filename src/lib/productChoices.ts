import type { Product } from './types'

/** Suggested choices; every saved value from this boutique stays available. */
const DEFAULT_NAMES = `
Jean
T-shirt
Robe
Chemise
Pantalon
Veste
Jupe
Short
Pull
Sweat
Ensemble
Chaussures
Sandales
Sac
Accessoire
`.trim().split('\n')
const DEFAULT_CATEGORIES = `
Jeans
T-shirts
Robes
Chemises
Pantalons
Vestes
Jupes
Shorts
Pulls
Sweats
Ensembles
Chaussures
Sandales
Sacs
Accessoires
Enfants
Autres vêtements
`.trim().split('\n')
const DEFAULT_SIZES = `
Taille unique
XS
S
M
L
XL
XXL
XXXL
34
35
36
37
38
39
40
41
42
43
44
45
46
48
50
52
54
56
`.trim().split('\n')

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
