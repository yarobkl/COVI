import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'

/** Only the owning merchant obtains a short-lived URL through Storage RLS.
 * This reference never becomes a public product or stock photo.
 */
export function PrivateOrderReferenceImage({
  shopId,
  orderId,
  imagePath,
}: {
  shopId: string
  orderId: string
  imagePath: string | null
}) {
  const [signed, setSigned] = useState<{ path: string; url: string } | null>(null)
  const [failed, setFailed] = useState<string | null>(null)
  useEffect(() => {
    let active = true
    if (!imagePath) return () => { active = false }
    const expected = shopId + '/' + orderId + '/reference.jpg'
    if (imagePath !== expected) {
      return () => { active = false }
    }
    void supabase.storage
      .from('covi-order-references')
      .createSignedUrl(imagePath, 180)
      .then(({ data, error: failure }) => {
        if (!active) return
        if (failure || !data?.signedUrl) {
          setFailed(imagePath)
        } else {
          setSigned({ path: imagePath, url: data.signedUrl })
        }
      })
    return () => { active = false }
  }, [shopId, orderId, imagePath])

  if (!imagePath) return null
  const url = signed?.path === imagePath ? signed.url : ''
  const expected = shopId + '/' + orderId + '/reference.jpg'
  const error = imagePath !== expected
    ? 'La référence photo ne correspond pas à cette commande.'
    : failed === imagePath ? 'Cette capture n’est pas disponible.' : ''
  return (
    <section className="checkout-inbox__reference" aria-label="Capture jointe à la demande">
      <p className="field__hint">
        Capture envoyée par le client depuis un statut ou un live — référence uniquement,
        sans création de fiche produit.
      </p>
      {url && (
        <img
          src={url}
          alt="Capture de l’article vu sur les réseaux, jointe par le client"
          loading="lazy"
          style={{ maxWidth: '100%', maxHeight: 320, objectFit: 'contain' }}
        />
      )}
      {error && <p role="status">{error}</p>}
    </section>
  )
}
