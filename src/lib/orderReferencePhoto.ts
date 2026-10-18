/** A reference to an image seen on WhatsApp/social media, never a stock product photo.
 * The picture is optional, compressed locally, and sent with one public order.
 */
export const MAX_REFERENCE_UPLOAD_BYTES = 320_000
const MAX_SOURCE_BYTES = 12 * 1024 * 1024
const JPEG_DATA_URI = /^data:image\/jpeg;base64,([A-Za-z0-9+/]+={0,2})$/

export function validateReferencePhotoDataUri(value: string): string {
  const match = JPEG_DATA_URI.exec(value)
  if (!match || value.length > 450_000) {
    throw new Error('La capture doit être une petite image JPEG valide.')
  }
  const bytes = atob(match[1])
  if (
    bytes.length < 4 ||
    bytes.length > MAX_REFERENCE_UPLOAD_BYTES ||
    bytes.charCodeAt(0) !== 0xff ||
    bytes.charCodeAt(1) !== 0xd8 ||
    bytes.charCodeAt(2) !== 0xff ||
    bytes.charCodeAt(bytes.length - 2) !== 0xff ||
    bytes.charCodeAt(bytes.length - 1) !== 0xd9
  ) {
    throw new Error('La capture JPEG est invalide ou trop volumineuse.')
  }
  return value
}

/** Uses browser-native canvas on the customer's device; no image API or paid service. */
export async function prepareOrderReferencePhoto(file: File): Promise<string> {
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
    throw new Error('Choisissez une image JPEG, PNG ou WebP.')
  }
  if (file.size === 0 || file.size > MAX_SOURCE_BYTES) {
    throw new Error('Cette image est vide ou dépasse 12 Mo.')
  }
  const url = URL.createObjectURL(file)
  try {
    const image = new Image()
    await new Promise<void>((resolve, reject) => {
      image.onload = () => resolve()
      image.onerror = () => reject(new Error('Impossible de lire cette photo.'))
      image.src = url
    })
    if (!image.naturalWidth || !image.naturalHeight) {
      throw new Error('Dimensions de la capture invalides.')
    }
    const scale = Math.min(1, 1100 / Math.max(image.naturalWidth, image.naturalHeight))
    const canvas = document.createElement('canvas')
    canvas.width = Math.max(1, Math.round(image.naturalWidth * scale))
    canvas.height = Math.max(1, Math.round(image.naturalHeight * scale))
    const ctx = canvas.getContext('2d')
    if (!ctx) throw new Error('Votre appareil ne peut pas préparer cette photo.')
    ctx.fillStyle = '#ffffff'
    ctx.fillRect(0, 0, canvas.width, canvas.height)
    ctx.drawImage(image, 0, 0, canvas.width, canvas.height)
    for (const quality of [0.77, 0.55, 0.37]) {
      const value = canvas.toDataURL('image/jpeg', quality)
      try {
        return validateReferencePhotoDataUri(value)
      } catch {
        // Retry with lower quality to stay within the strict server size limit.
      }
    }
    throw new Error('Cette capture est trop volumineuse, essayez une image plus petite.')
  } finally {
    URL.revokeObjectURL(url)
  }
}
