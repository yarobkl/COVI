import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  compressPhoto,
  fitWithin,
  PHOTO_MAX_BYTES,
  PHOTO_SIZE_ERROR,
  PHOTO_TYPE_ERROR,
  preparePhoto,
} from './imageCompression'

const MB = 1024 * 1024
const photo = (bytes: number, type = 'image/jpeg', name = 'IMG_2041.jpg') =>
  new File([new Uint8Array(bytes)], name, { type, lastModified: 1 })

describe('fitWithin', () => {
  it('brings the longest side down to 1600 px, keeping the proportions', () => {
    expect(fitWithin(4000, 3000)).toEqual({ width: 1600, height: 1200 })
    expect(fitWithin(3000, 4000)).toEqual({ width: 1200, height: 1600 })
  })
  it('never enlarges a small photo', () => {
    expect(fitWithin(800, 600)).toEqual({ width: 800, height: 600 })
  })
})

// jsdom has no canvas: the decoding and the canvas are simulated.
describe('compressPhoto (simulated canvas)', () => {
  let drawn: { width: number; height: number; type?: string; quality?: number; fill?: string }
  let outputBytes: number
  let decodeSize: { width: number; height: number }
  const close = vi.fn()

  beforeEach(() => {
    drawn = { width: 0, height: 0 }
    outputBytes = 300 * 1024
    decodeSize = { width: 4000, height: 3000 }
    vi.stubGlobal(
      'createImageBitmap',
      vi.fn(async () => ({ ...decodeSize, close })),
    )
    const context = {
      fillStyle: '',
      fillRect: vi.fn(function (this: { fillStyle: string }) {
        drawn.fill = this.fillStyle
      }),
      drawImage: vi.fn((_src: unknown, _x: number, _y: number, w: number, h: number) => {
        drawn.width = w
        drawn.height = h
      }),
    }
    vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockImplementation(
      () => context as unknown as CanvasRenderingContext2D,
    )
    vi.spyOn(HTMLCanvasElement.prototype, 'toBlob').mockImplementation(function (
      this: HTMLCanvasElement,
      done: BlobCallback,
      type?: string,
      quality?: number,
    ) {
      drawn.type = type
      drawn.quality = quality
      done(new Blob([new Uint8Array(outputBytes)], { type: type ?? 'image/png' }))
    })
  })
  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
    close.mockClear()
  })

  it('shrinks a camera photo to 1600 px and re-encodes it as JPEG 0.8', async () => {
    const out = await compressPhoto(photo(6 * MB))
    expect(drawn).toMatchObject({ width: 1600, height: 1200, type: 'image/jpeg', quality: 0.8 })
    expect(out.type).toBe('image/jpeg')
    expect(out.name).toBe('IMG_2041.jpg')
    expect(out.size).toBe(300 * 1024)
    expect(close).toHaveBeenCalled()
  })

  it('paints transparent PNG parts white and names the file .jpg', async () => {
    const out = await compressPhoto(photo(2 * MB, 'image/png', 'robe.png'))
    expect(drawn.fill).toBe('#ffffff')
    expect(out.name).toBe('robe.jpg')
  })

  it('keeps a small photo that would not get lighter', async () => {
    decodeSize = { width: 900, height: 900 }
    outputBytes = 500 * 1024
    const original = photo(200 * 1024)
    expect(await compressPhoto(original)).toBe(original)
  })

  it('keeps the original when the photo cannot be decoded here', async () => {
    vi.stubGlobal(
      'createImageBitmap',
      vi.fn(async () => {
        throw new Error('decode')
      }),
    )
    const original = photo(MB)
    expect(await compressPhoto(original)).toBe(original)
  })

  it('preparePhoto: checks the type first, then the weight once shrunk', async () => {
    expect(await preparePhoto(photo(MB, 'image/heic', 'a.heic'))).toEqual({
      file: null,
      error: PHOTO_TYPE_ERROR,
    })
    const ok = await preparePhoto(photo(8 * MB))
    expect(ok.error).toBeNull()
    expect(ok.file?.size).toBeLessThan(PHOTO_MAX_BYTES)
    outputBytes = 6 * MB
    expect(await preparePhoto(photo(9 * MB))).toEqual({ file: null, error: PHOTO_SIZE_ERROR })
  })
})
