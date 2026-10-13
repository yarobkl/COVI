import { useState } from 'react'

export type ShopGpsPosition = {
  latitude: number
  longitude: number
  accuracy: number
}

/**
 * Geolocation API is built into mobile browsers, no Google Maps account or API key.
 * Request is strictly opt-in; only a real button click asks the browser for permission.
 */
export function ShopGpsControl({
  value,
  onChange,
}: {
  value: ShopGpsPosition | null
  onChange: (value: ShopGpsPosition | null) => void
}) {
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')

  function locate() {
    if (busy) return
    if (!navigator.geolocation) {
      setMessage('La position GPS n’est pas disponible sur cet appareil.')
      return
    }
    setBusy(true)
    setMessage('')
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => {
        setBusy(false)
        if (
          !Number.isFinite(coords.latitude) ||
          !Number.isFinite(coords.longitude) ||
          !Number.isFinite(coords.accuracy)
        ) {
          setMessage('La position obtenue n’est pas exploitable. Essayez de nouveau.')
          return
        }
        onChange({
          latitude: coords.latitude,
          longitude: coords.longitude,
          accuracy: Math.max(0.1, coords.accuracy),
        })
      },
      (error) => {
        setBusy(false)
        setMessage(
          error.code === 1
            ? 'Accès à la position refusé. Vous pouvez toujours choisir votre quartier.'
            : 'Position introuvable. Réessayez depuis votre boutique, avec le GPS activé.',
        )
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
    )
  }

  return (
    <div className="field">
      <p className="field__label">Position GPS de ma boutique (facultatif)</p>
      <p className="field__hint">
        Uniquement si vous êtes dans votre boutique. Votre position n’est jamais demandée
        automatiquement. Le point sur la carte sera ajouté dans une prochaine version.
      </p>
      <div>
        <button
          type="button"
          className="btn btn--secondary"
          disabled={busy}
          onClick={locate}
        >
          {busy ? 'Localisation en cours…' : value ? 'Actualiser ma position' : 'Utiliser ma position GPS'}
        </button>
        {value && (
          <button
            type="button"
            className="btn btn--ghost"
            onClick={() => {
              onChange(null)
              setMessage('')
            }}
          >
            Effacer ma position
          </button>
        )}
      </div>
      {value && (
        <p role="status" className="field__hint">
          ✓ Position enregistrable · précision estimée : {Math.ceil(value.accuracy)} m.
          Vous pourrez la corriger sur la carte plus tard.
        </p>
      )}
      {message && <p role="status" className="field__hint">{message}</p>}
    </div>
  )
}
