import { useMemo } from 'react'
import { localQrSvgDataUrl } from '../../lib/localQr'

/** Locally generated, printable, contrast-safe QR for a permanent shop link. */
export function LocalQRCode({ value, shopName }: { value: string; shopName: string }) {
  const imageUrl = useMemo(() => localQrSvgDataUrl(value), [value])
  return (
    <section className="checkout-share__qr" aria-label="QR code de commande à imprimer">
      <p className="hand">Scannez ici pour commander.</p>
      <img src={imageUrl} width={264} height={264} alt={'QR code de la boutique ' + shopName} />
      <strong>{shopName}</strong>
      <p>Choisissez vos articles ; le vendeur confirmera la commande et le paiement reçu.</p>
      <button
        type="button"
        className="btn btn--tactile checkout-share__print"
        onClick={() => window.print()}
      >
        Imprimer le QR code
      </button>
    </section>
  )
}
