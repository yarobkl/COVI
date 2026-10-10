import { useEffect, useId, useRef, useState } from 'react'
import { CloseIcon, InfoIcon } from '../../components/icons'
import { Button } from '../../components/ui'
import { preparePhoto, weight } from './imageCompression'

/**
 * « Photo (facultatif) »: take or choose a picture, see it, change or remove it. The picture is
 * shrunk on the device (1600 px, JPEG) before being kept for the upload.
 */
export function PhotoField({
  value,
  onChange,
  onBusyChange,
}: {
  value: File | null
  onChange: (file: File | null) => void
  onBusyChange?: (busy: boolean) => void
}) {
  const id = useId()
  const input = useRef<HTMLInputElement>(null)
  const [preview, setPreview] = useState<string | null>(null)
  const previewUrl = useRef<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  // The preview is a short-lived URL of the shrunk photo, released when replaced or unmounted.
  const choose = (file: File | null) => {
    if (previewUrl.current) URL.revokeObjectURL(previewUrl.current)
    previewUrl.current =
      file && typeof URL.createObjectURL === 'function' ? URL.createObjectURL(file) : null
    setPreview(previewUrl.current)
    onChange(file)
  }
  useEffect(
    () => () => {
      if (previewUrl.current) URL.revokeObjectURL(previewUrl.current)
    },
    [],
  )

  async function pick(file: File | undefined) {
    if (!file) return
    setError('')
    setBusy(true)
    onBusyChange?.(true)
    try {
      const ready = await preparePhoto(file)
      if (ready.error !== null) {
        setError(ready.error)
        choose(null)
      } else choose(ready.file)
    } finally {
      setBusy(false)
      onBusyChange?.(false)
      if (input.current) input.current.value = ''
    }
  }

  return (
    <div className="field photo-field">
      <p className="field__label" id={`${id}-label`}>
        Photo<span className="field__optional"> (facultatif)</span>
      </p>
      <div className="photo-field__row">
        <span className="photo-field__frame" aria-hidden="true">
          {preview ? <img src={preview} alt="" /> : <span>Pas de photo</span>}
        </span>
        <div className="photo-field__actions">
          <input
            ref={input}
            id={id}
            className="visually-hidden photo-field__input"
            type="file"
            accept="image/jpeg,image/png,image/webp"
            aria-labelledby={`${id}-label ${id}-pick`}
            aria-describedby={error ? `${id}-error` : `${id}-hint`}
            onChange={(e) => void pick(e.target.files?.[0])}
          />
          <label className="btn btn--secondary photo-field__pick" htmlFor={id} id={`${id}-pick`}>
            {busy ? 'Un instant…' : value ? 'Changer la photo' : 'Prendre ou choisir une photo'}
          </label>
          {value && !busy && (
            <Button variant="ghost" icon={<CloseIcon />} onClick={() => choose(null)}>
              Retirer la photo
            </Button>
          )}
        </div>
      </div>
      {error ? (
        <p className="field__error" id={`${id}-error`} role="alert">
          <InfoIcon />
          {error}
        </p>
      ) : (
        <p className="field__hint" id={`${id}-hint`} aria-live="polite">
          {busy
            ? 'On prépare la photo…'
            : value
              ? `Photo prête (${weight(value.size)}) : elle partira vite, même avec peu de réseau.`
              : 'JPG ou PNG. Elle est réduite sur ce téléphone avant de partir.'}
        </p>
      )}
    </div>
  )
}
