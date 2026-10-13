import { useEffect, useState } from 'react'
import type { User } from '@supabase/supabase-js'
import { supabase } from '../../lib/supabase'
import { currentProfilePhotoPath, PROFILE_PHOTO_BUCKET } from '../../lib/profilePhoto'

/** Read a private photo with a short-lived URL; refresh it during long sessions. */
export function useProfilePhoto(user: User | null) {
  const path = currentProfilePhotoPath(user?.user_metadata?.profile_photo_path, user?.id)
  const [photo, setPhoto] = useState<{ path: string; url: string } | null>(null)

  useEffect(() => {
    if (!path) return
    let active = true
    async function refresh() {
      const { data, error } = await supabase.storage
        .from(PROFILE_PHOTO_BUCKET)
        .createSignedUrl(path!, 3600)
      if (active && !error && data?.signedUrl) setPhoto({ path: path!, url: data.signedUrl })
    }
    void refresh()
    const interval = window.setInterval(() => void refresh(), 45 * 60 * 1000)
    return () => {
      active = false
      window.clearInterval(interval)
    }
  }, [path])

  return photo?.path === path ? photo.url : null
}
