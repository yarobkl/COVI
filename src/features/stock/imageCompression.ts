import { NBSP } from '../../lib/format'

// Product photos are shrunk on the phone before they leave it: a 12-megapixel photo (4 to 8 Mo)
// becomes a JPEG of about 200 to 400 Ko, which goes through a weak network.

/** Types accepted by the storage bucket (same rule as addProduct in lib/covi.ts). */
export const PHOTO_TYPES = ['image/jpeg', 'image/png', 'image/webp'] as const
/** Largest file sent (same rule as addProduct). */
export const PHOTO_MAX_BYTES = 5 * 1024 * 1024
/** Longest side of the photo sent, in pixels. */
export const PHOTO_MAX_SIDE = 1600
/** JPEG quality of the photo sent. */
export const PHOTO_QUALITY = 0.8

export const PHOTO_TYPE_ERROR = 'Cette photo ne passe pas. Prenez une photo JPG ou PNG.'
export const PHOTO_SIZE_ERROR =
  'Cette photo ne passe pas. Prenez une photo JPG ou PNG de moins de 5 Mo.'

/** Size of the photo once its longest side is at most `max` (never enlarged). */
export function fitWithin(width: number, height: number, max = PHOTO_MAX_SIDE) {
  const scale = Math.min(1, max / Math.max(width, height))
  return {
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale)),
  }
}

/** What is wrong with a photo before it is shrunk (`null` when its type is accepted). */
export const photoTypeError = (file: Pick<File, 'type'>) =>
  (PHOTO_TYPES as readonly string[]).includes(file.type) ? null : PHOTO_TYPE_ERROR

type Picture = { width: number; height: number; source: CanvasImageSource; close?: () => void }

async function decode(file: Blob): Promise<Picture> {
  if (typeof createImageBitmap === 'function') {
    const bitmap = await createImageBitmap(file)
    return {
      width: bitmap.width,
      height: bitmap.height,
      source: bitmap,
      close: () => bitmap.close(),
    }
  }
  const url = URL.createObjectURL(file)
  try {
    const img = new Image()
    img.src = url
    await img.decode()
    return { width: img.naturalWidth, height: img.naturalHeight, source: img }
  } finally {
    URL.revokeObjectURL(url)
  }
}

const toBlob = (canvas: HTMLCanvasElement, quality: number) =>
  new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/jpeg', quality))

/** `robe.png` → `robe.jpg`. */
const jpegName = (name: string) => (name.replace(/\.[^./\\]+$/, '') || 'photo') + '.jpg'

/**
 * Shrinks a photo to 1600 px on its longest side and re-encodes it as JPEG (quality 0.8) with a
 * canvas. Transparent parts of a PNG become white. When the photo cannot be decoded here, or the
 * result would not be smaller, the original file is kept: addProduct still checks its type and
 * weight before sending it.
 */
export async function compressPhoto(
  file: File,
  { maxSide = PHOTO_MAX_SIDE, quality = PHOTO_QUALITY } = {},
): Promise<File> {
  let picture: Picture
  try {
    picture = await decode(file)
  } catch {
    return file
  }
  try {
    const size = fitWithin(picture.width, picture.height, maxSide)
    const canvas = document.createElement('canvas')
    canvas.width = size.width
    canvas.height = size.height
    const context = canvas.getContext('2d')
    if (!context) return file
    context.fillStyle = '#ffffff'
    context.fillRect(0, 0, size.width, size.height)
    context.drawImage(picture.source, 0, 0, size.width, size.height)
    const blob = await toBlob(canvas, quality)
    const resized = size.width !== picture.width || size.height !== picture.height
    if (!blob || (!resized && blob.size >= file.size)) return file
    return new File([blob], jpegName(file.name), {
      type: 'image/jpeg',
      lastModified: file.lastModified,
    })
  } finally {
    picture.close?.()
  }
}

/**
 * The photo to send, or why it cannot be sent: its type is checked first, then it is shrunk, then
 * its weight is checked (a big photo straight from the camera passes once shrunk).
 */
export async function preparePhoto(
  file: File,
): Promise<{ file: File; error: null } | { file: null; error: string }> {
  const typeError = photoTypeError(file)
  if (typeError) return { file: null, error: typeError }
  const ready = await compressPhoto(file)
  if (ready.size > PHOTO_MAX_BYTES) return { file: null, error: PHOTO_SIZE_ERROR }
  return { file: ready, error: null }
}

/** « 312 Ko », « 1,4 Mo ». */
export const weight = (bytes: number) =>
  bytes < 1024 * 1024
    ? `${Math.max(1, Math.round(bytes / 1024))}${NBSP}Ko`
    : `${(bytes / 1024 / 1024).toFixed(1).replace('.', ',')}${NBSP}Mo`
