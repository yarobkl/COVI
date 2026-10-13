/** Private user profile photos. Never trust account metadata as an authorization claim. */
export const PROFILE_PHOTO_BUCKET = 'covi-profile-photos'
export const MAX_SOURCE_PHOTO_BYTES = 15 * 1024 * 1024
export const MAX_SAVED_PHOTO_BYTES = 2 * 1024 * 1024

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const PHOTO_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
const PHOTO_EXTENSIONS = /\.(jpe?g|png|webp|heic|heif)$/i

/** Only a file in this logged-in user's private directory may be shown. */
export function currentProfilePhotoPath(metadataValue: unknown, userId: string | undefined) {
  if (!userId || !UUID.test(userId) || typeof metadataValue !== 'string') return null
  const path = metadataValue.trim()
  return new RegExp('^' + userId + '/[0-9a-f-]{36}\\.jpg$', 'i').test(path) &&
    UUID.test(path.slice(userId.length + 1, -4))
    ? path
    : null
}

export function validateProfilePhoto(file: Pick<File, 'size' | 'type' | 'name'>): string | null {
  if (!Number.isFinite(file.size) || file.size <= 0) return 'Cette photo est vide.'
  if (file.size > MAX_SOURCE_PHOTO_BYTES) return 'Cette photo est trop volumineuse (15 Mo maximum).'
  if (
    !PHOTO_TYPES.has(file.type.toLowerCase()) &&
    !(file.type === '' && PHOTO_EXTENSIONS.test(file.name))
  )
    return 'Choisissez une image JPEG, PNG, WebP ou HEIC.'
  return null
}

/** Browser-side normalization strips GPS/EXIF and converts HEIC when Safari can decode it. */
export async function prepareProfilePhoto(file: File): Promise<Blob> {
  const error = validateProfilePhoto(file)
  if (error) throw new Error(error)

  const sourceUrl = URL.createObjectURL(file)
  try {
    const image = new Image()
    try {
      await new Promise<void>((resolve, reject) => {
        image.onload = () => resolve()
        image.onerror = () =>
          reject(new Error('Format de photo non pris en charge sur cet appareil.'))
        image.src = sourceUrl
      })
    } catch {
      throw new Error('Impossible de lire cette photo. Essayez une image JPEG.')
    }

    const width = image.naturalWidth
    const height = image.naturalHeight
    if (!width || !height) throw new Error('La photo ne peut pas être lue.')
    const scale = Math.min(1, 720 / Math.max(width, height))
    const canvas = document.createElement('canvas')
    canvas.width = Math.max(1, Math.round(width * scale))
    canvas.height = Math.max(1, Math.round(height * scale))
    const context = canvas.getContext('2d')
    if (!context) throw new Error('Impossible de préparer la photo sur cet appareil.')
    context.drawImage(image, 0, 0, canvas.width, canvas.height)
    const normalized = await new Promise<Blob>((resolve, reject) => {
      canvas.toBlob(
        (blob) => {
          if (blob) resolve(blob)
          else reject(new Error('Impossible de convertir la photo.'))
        },
        'image/jpeg',
        0.82,
      )
    })
    if (normalized.size > MAX_SAVED_PHOTO_BYTES)
      throw new Error('La photo reste trop volumineuse. Choisissez-en une autre.')
    return normalized
  } finally {
    URL.revokeObjectURL(sourceUrl)
  }
}
