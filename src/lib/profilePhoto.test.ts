import { describe, expect, it } from 'vitest'
import {
  currentProfilePhotoPath,
  MAX_SOURCE_PHOTO_BYTES,
  PROFILE_PHOTO_BUCKET,
  validateProfilePhoto,
} from './profilePhoto'

const user = '11111111-1111-4111-8111-111111111111'
const other = '22222222-2222-4222-8222-222222222222'
const photo = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'

describe('COVI private profile photos', () => {
  it('uses a separate private bucket', () => {
    expect(PROFILE_PHOTO_BUCKET).toBe('covi-profile-photos')
  })
  it('never displays an avatar path from another user or a URL in metadata', () => {
    expect(currentProfilePhotoPath(`${user}/${photo}.jpg`, user)).toBe(
      `${user}/${photo}.jpg`,
    )
    expect(currentProfilePhotoPath(`${other}/${photo}.jpg`, user)).toBeNull()
    expect(currentProfilePhotoPath('https://attacker.example/photo.jpg', user)).toBeNull()
    expect(currentProfilePhotoPath(`${user}/../${photo}.jpg`, user)).toBeNull()
    expect(currentProfilePhotoPath(`${user}/${photo}.png`, user)).toBeNull()
    expect(currentProfilePhotoPath(null, user)).toBeNull()
  })
  it('accepts common formats and iPhone HEIC while rejecting unsafe uploads', () => {
    expect(validateProfilePhoto({ size: 400, type: 'image/jpeg', name: 'photo.jpg' })).toBeNull()
    expect(validateProfilePhoto({ size: 400, type: 'image/heic', name: 'photo.HEIC' })).toBeNull()
    expect(validateProfilePhoto({ size: 400, type: '', name: 'photo.heic' })).toBeNull()
    expect(validateProfilePhoto({ size: 400, type: 'image/svg+xml', name: 'avatar.svg' })).toMatch(
      /JPEG/,
    )
    expect(validateProfilePhoto({ size: 400, type: 'text/html', name: 'evil.jpg' })).toMatch(
      /JPEG/,
    )
    expect(validateProfilePhoto({ size: 0, type: 'image/png', name: 'empty.png' })).toBeTruthy()
    expect(validateProfilePhoto({
      size: MAX_SOURCE_PHOTO_BYTES + 1, type: 'image/png', name: 'large.png',
    })).toMatch(/15 Mo/)
  })
})
