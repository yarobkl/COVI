import { useEffect, useState } from 'react'
import { fcfa } from '../../lib/format'
import { BackspaceIcon } from '../icons'
import { Button } from './Button'
import { cx } from './cx'
import { keyFromKeyboard, lowerBy, PAD_KEYS, pressKey, type PadKey } from './numpad'

const keyLabel = (key: PadKey) =>
  key === 'back' ? 'Effacer un chiffre' : key === '000' ? 'Trois zéros' : undefined

/**
 * Price pad for the negotiation: big keys, « 000 », −500 / −1 000 / « Prix affiché » shortcuts and
 * the discount spelled out. With `keyboard`, digits, Backspace and Enter work from a physical
 * keyboard (the matching key flashes).
 */
export function NumPad({
  label = 'Vendu à',
  value,
  onChange,
  reference,
  onConfirm,
  confirmLabel = 'Garder ce prix',
  keyboard = false,
}: {
  label?: string
  /** Price typed so far, `null` when nothing is typed. */
  value: number | null
  onChange: (value: number | null) => void
  /** Displayed price (prix affiché), for the shortcut and the discount. */
  reference?: number
  onConfirm: () => void
  confirmLabel?: string
  keyboard?: boolean
}) {
  const [tapped, setTapped] = useState<PadKey | null>(null)
  const canConfirm = value !== null && value > 0

  useEffect(() => {
    if (!keyboard) return
    const onKey = (e: KeyboardEvent) => {
      if (e.ctrlKey || e.metaKey || e.altKey) return
      const target = e.target instanceof Element ? e.target : null
      if (target?.closest('input, textarea, select, [contenteditable="true"]')) return
      const action = keyFromKeyboard(e.key)
      if (!action) return
      if (action === 'confirm') {
        // Enter on a focused button already clicks it: only confirm from elsewhere.
        if (target?.closest('button, a')) return
        e.preventDefault()
        if (canConfirm) onConfirm()
        return
      }
      e.preventDefault()
      onChange(pressKey(value, action))
      setTapped(action)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [keyboard, value, onChange, onConfirm, canConfirm])

  useEffect(() => {
    if (!tapped) return
    const timer = setTimeout(() => setTapped(null), 150)
    return () => clearTimeout(timer)
  }, [tapped])

  const discount = reference !== undefined && value !== null ? reference - value : 0
  return (
    <div className="numpad" role="group" aria-label="Pavé de prix">
      <output className="numpad__display" aria-live="polite">
        <span className="numpad__label">{label}</span>
        <span className="numpad__value">
          <span>{value === null ? '' : fcfa(value)}</span>
          <span className="numpad__caret" aria-hidden="true" />
          <span className="amount__unit">FCFA</span>
        </span>
        {reference !== undefined && (
          <span className="numpad__ref">
            Prix affiché <span className="figures">{fcfa(reference)}</span>
            {discount > 0 && (
              <>
                {' · '}
                <span className="numpad__discount">
                  <span className="figures">{fcfa(discount)}</span>&nbsp;FCFA de remise
                </span>
              </>
            )}
          </span>
        )}
      </output>
      <div className="numpad__quick">
        <Button variant="tactile" onClick={() => onChange(lowerBy(value, 500))}>
          <span aria-hidden="true">−&nbsp;500</span>
          <span className="visually-hidden">Baisser de 500 FCFA</span>
        </Button>
        <Button variant="tactile" onClick={() => onChange(lowerBy(value, 1000))}>
          <span aria-hidden="true">−&nbsp;1&nbsp;000</span>
          <span className="visually-hidden">Baisser de 1 000 FCFA</span>
        </Button>
        {reference !== undefined && (
          <Button variant="tactile" className="btn--text" onClick={() => onChange(reference)}>
            Prix affiché
          </Button>
        )}
      </div>
      <div className="numpad__keys">
        {PAD_KEYS.map((key) => (
          <button
            key={key}
            type="button"
            className={cx(
              'numpad__key',
              (key === 'back' || key === '000') && 'numpad__key--fn',
              tapped === key && 'is-tapped',
            )}
            aria-label={keyLabel(key)}
            onClick={() => onChange(pressKey(value, key))}
          >
            {key === 'back' ? <BackspaceIcon /> : key}
          </button>
        ))}
      </div>
      <Button variant="sale" size="xl" block disabled={!canConfirm} onClick={onConfirm}>
        {canConfirm ? confirmLabel : 'Indiquez le prix'}
      </Button>
    </div>
  )
}
