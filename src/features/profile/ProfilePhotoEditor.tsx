import { useRef, useState, type ChangeEvent } from 'react'
import { initials, ownerName } from '../../app/identity'
import { useCurrentUser } from '../auth/useCurrentUser'
import {
  currentProfilePhotoPath,
  prepareProfilePhoto,
  PROFILE_PHOTO_BUCKET,
} from '../../lib/profilePhoto'
import { supabase } from '../../lib/supabase'
import { useProfilePhoto } from './useProfilePhoto'

/** One personal, private picture per signed-in account (not the shop's product photos). */
export function ProfilePhotoEditor() {
  const user = useCurrentUser()
  const photoUrl = useProfilePhoto(user)
  const photoPath = currentProfilePhotoPath(user?.user_metadata?.profile_photo_path, user?.id)
  const input = useRef<HTMLInputElement>(null)
  const [busy, setBusy] = useState(false)
  const [notice, setNotice] = useState<{ text: string; error: boolean } | null>(null)
  const label = ownerName(user?.user_metadata) ?? user?.email ?? 'Mon profil'

  async function upload(event: ChangeEvent<HTMLInputElement>) {
    const file = event.currentTarget.files?.[0]
    if (!file || !user || busy) return
    setBusy(true)
    setNotice(null)
    const newPath = `${user.id}/${crypto.randomUUID()}.jpg`
    let uploaded = false
    try {
      const optimized = await prepareProfilePhoto(file)
      const { error: uploadError } = await supabase.storage
        .from(PROFILE_PHOTO_BUCKET)
        .upload(newPath, optimized, { contentType: 'image/jpeg', upsert: false })
      if (uploadError) throw new Error('Envoi impossible. Vérifiez votre connexion puis réessayez.')
      uploaded = true

      const { error: updateError } = await supabase.auth.updateUser({
        data: { profile_photo_path: newPath },
      })
      if (updateError) throw new Error('La photo n’a pas pu être liée à votre compte.')

      // The new photo is already saved, so an old-file cleanup error should not undo it.
      const cleanup = photoPath
        ? await supabase.storage.from(PROFILE_PHOTO_BUCKET).remove([photoPath])
        : null
      setNotice({
        text: cleanup?.error
          ? 'Photo enregistrée. L’ancienne photo n’a pas pu être supprimée.'
          : '✓ Photo de profil enregistrée.',
        error: Boolean(cleanup?.error),
      })
    } catch (error) {
      if (uploaded) await supabase.storage.from(PROFILE_PHOTO_BUCKET).remove([newPath])
      setNotice({
        text: error instanceof Error ? error.message : 'Impossible d’enregistrer la photo.',
        error: true,
      })
    } finally {
      setBusy(false)
      if (input.current) input.current.value = ''
    }
  }

  async function remove() {
    if (!user || !photoPath || busy) return
    setBusy(true)
    setNotice(null)
    try {
      const { error } = await supabase.auth.updateUser({ data: { profile_photo_path: null } })
      if (error) throw new Error('Impossible de modifier le profil. Réessayez.')
      const { error: deleteError } = await supabase.storage
        .from(PROFILE_PHOTO_BUCKET)
        .remove([photoPath])
      setNotice({
        text: deleteError
          ? 'Photo retirée du profil, mais le fichier n’a pas pu être supprimé.'
          : '✓ Photo retirée de votre profil.',
        error: Boolean(deleteError),
      })
    } catch (error) {
      setNotice({
        text: error instanceof Error ? error.message : 'Impossible de retirer la photo.',
        error: true,
      })
    } finally {
      setBusy(false)
    }
  }

  return (
    <section className="sheet profile-photo" aria-labelledby="profile-photo-title">
      <h2 className="section-title" id="profile-photo-title">
        Ma photo de profil
      </h2>
      <div className="profile-photo__row">
        <div className="profile-photo__preview">
          {photoUrl ? (
            <img src={photoUrl} alt="Votre photo de profil" />
          ) : (
            <span aria-label="Photo de profil non définie">{initials(label)}</span>
          )}
        </div>
        <div className="profile-photo__details">
          <p>
            Personnalisez votre compte COVI. Cette photo apparaîtra dans le menu de votre boutique.
          </p>
          <div className="profile-photo__actions">
            <input
              ref={input}
              className="profile-photo__input"
              type="file"
              accept="image/jpeg,image/png,image/webp,image/heic,image/heif"
              aria-label="Choisir une photo de profil"
              disabled={!user || busy}
              onChange={(event) => void upload(event)}
            />
            <button
              type="button"
              className="btn btn--secondary"
              disabled={!user || busy}
              onClick={() => input.current?.click()}
            >
              {busy ? 'Un instant…' : photoPath ? 'Changer ma photo' : 'Ajouter ma photo'}
            </button>
            {photoPath && (
              <button
                type="button"
                className="btn btn--ghost"
                disabled={busy}
                onClick={() => void remove()}
              >
                Supprimer
              </button>
            )}
          </div>
          <small>
            JPEG, PNG, WebP ou photo iPhone (HEIC). L’image est adaptée automatiquement.
          </small>
        </div>
      </div>
      {notice && (
        <p
          role={notice.error ? 'alert' : 'status'}
          className={notice.error ? 'profile-photo__error' : 'profile-photo__success'}
        >
          {notice.text}
        </p>
      )}
    </section>
  )
}
