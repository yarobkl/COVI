import { useId, type ReactNode } from 'react'
import '../../styles/app/check-field.css'
import { cx } from './cx'

/**
 * A yes / no choice written as a sentence (« Pièce unique (friperie) », « Je l’ai déjà reçu »):
 * a real checkbox, 24 px, and the whole line is the touch target.
 */
export function CheckField({
  label,
  hint,
  checked,
  onChange,
  disabled = false,
  className,
}: {
  label: ReactNode
  hint?: ReactNode
  checked: boolean
  onChange: (checked: boolean) => void
  disabled?: boolean
  className?: string
}) {
  const id = useId()
  return (
    <div className={cx('check-field', className)}>
      <input
        className="check-field__input"
        type="checkbox"
        id={id}
        checked={checked}
        disabled={disabled}
        aria-describedby={hint ? `${id}-hint` : undefined}
        onChange={(e) => onChange(e.target.checked)}
      />
      <label className="check-field__label" htmlFor={id}>
        {label}
      </label>
      {hint && (
        <p className="check-field__hint" id={`${id}-hint`}>
          {hint}
        </p>
      )}
    </div>
  )
}
