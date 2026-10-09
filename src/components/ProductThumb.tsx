/** Product photo, or a fallback letter when the product has none. */
export function ProductThumb({
  imageUrl,
  fallback,
}: {
  imageUrl: string | null | undefined
  fallback: string
}) {
  return <div className="thumb">{imageUrl ? <img src={imageUrl} alt="" /> : fallback}</div>
}
