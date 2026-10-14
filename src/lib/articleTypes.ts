/** A shop offers article families independently of sold-out stock. */
export const DEFAULT_ARTICLE_TYPES = [
  'Pantalon',
  'Chemise',
  'Jean',
  'T-shirt',
  'Polo',
  'Robe',
  'Jupe',
  'Short',
  'Veste',
  'Pull',
  'Sweat',
  'Ensemble',
  'Chaussures',
  'Sandales',
  'Sac',
  'Accessoire',
] as const

export const uniqueArticleTypes = (values: readonly string[]) => {
  const seen = new Set<string>()
  return values
    .map((item) => item.trim())
    .filter((item) => {
      const key = item.toLocaleLowerCase('fr')
      if (!key || seen.has(key)) return false
      seen.add(key)
      return true
    })
}
