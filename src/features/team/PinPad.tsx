import { useEffect, useId, useState } from 'react'
import { Button, Notice } from '../../components/ui'

const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9'] as const

/**
 * Numeric keypad for a personal PIN (4 to 6 digits). The digits are never shown, only dots;
 * the physical keyboard works too (digits, Backspace, Enter). The value is cleared after each
 * submit: a refused PIN is typed again from scratch.
 */
export function PinPad({
  title,
  hint,
  error,
  busy = false,
  submitLabel = 'Valider',
  onSubmit,
}: {
  title: string
  hint?: string
  error?: string
  busy?: boolean
  submitLabel?: string
  onSubmit: (pin: string) => void
}) {
  const [pin, setPin] = useState('')
  const titleId = useId()
  const ready = pin.length >= 4 && !busy

  const press = (digit: string) => setPin((p) => (p.length < 6 ? p + digit : p))
  const erase = () => setPin((p) => p.slice(0, -1))
  const submit = () => {
    if (pin.length < 4 || busy) return
    const value = pin
    setPin('')
    onSubmit(value)
  }

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return
      if (/^[0-9]$/.test(e.key)) setPin((p) => (p.length < 6 ? p + e.key : p))
      else if (e.key === 'Backspace') setPin((p) => p.slice(0, -1))
      else if (e.key === 'Enter') document.getElementById(`${titleId}-ok`)?.click()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [titleId])

  return (
    <section className="pinpad" aria-labelledby={titleId}>
      <h2 className="pinpad__title" id={titleId}>
        {title}
      </h2>
      {hint && <p className="pinpad__hint">{hint}</p>}
      <p className="pinpad__dots" role="status" aria-live="polite">
        <span className="visually-hidden">
          {pin.length === 0 ? 'Aucun chiffre saisi' : `${pin.length} chiffres saisis`}
        </span>
        {Array.from({ length: Math.max(4, pin.length) }, (_, i) => (
          <span
            key={i}
            aria-hidden="true"
            className={i < pin.length ? 'pinpad__dot pinpad__dot--on' : 'pinpad__dot'}
          />
        ))}
      </p>
      {error && (
        <Notice tone="danger">
          <p>{error}</p>
        </Notice>
      )}
      <div className="pinpad__keys" role="group" aria-label="Clavier du code PIN">
        {KEYS.map((k) => (
          <button
            key={k}
            type="button"
            className="pinpad__key"
            disabled={busy}
            onClick={() => press(k)}
          >
            {k}
          </button>
        ))}
        <button
          type="button"
          className="pinpad__key pinpad__key--text"
          disabled={busy || pin.length === 0}
          onClick={erase}
          aria-label="Effacer le dernier chiffre"
        >
          Effacer
        </button>
        <button type="button" className="pinpad__key" disabled={busy} onClick={() => press('0')}>
          0
        </button>
        <span aria-hidden="true" />
      </div>
      <Button
        id={`${titleId}-ok`}
        variant="primary"
        size="lg"
        block
        busy={busy}
        disabled={!ready}
        onClick={submit}
      >
        {pin.length < 4 ? 'Tapez 4 à 6 chiffres' : submitLabel}
      </Button>
    </section>
  )
}
