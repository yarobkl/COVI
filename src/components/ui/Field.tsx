import {
  useId,
  useRef,
  type ComponentPropsWithRef,
  type ComponentProps,
  type ReactNode,
} from 'react'
import { CloseIcon, InfoIcon, SearchIcon } from '../icons'
import { cx } from './cx'
import { IconButton } from './IconButton'

/** Attributes Field passes to its control so that label, hint and error are announced with it. */
export type FieldControlProps = {
  id: string
  'aria-describedby'?: string
  'aria-invalid'?: true
}

/**
 * Label above the control, always visible, then an optional hint and error. « (facultatif) » is
 * written in the label instead of starring the required fields.
 */
export function Field({
  label,
  optional = false,
  hint,
  error,
  className,
  children,
}: {
  label: ReactNode
  optional?: boolean
  hint?: ReactNode
  error?: ReactNode
  className?: string
  children: (control: FieldControlProps) => ReactNode
}) {
  const id = useId()
  const hintId = hint ? `${id}-hint` : undefined
  const errorId = error ? `${id}-error` : undefined
  const describedBy = [hintId, errorId].filter(Boolean).join(' ') || undefined
  return (
    <div className={cx('field', className)}>
      <label className="field__label" htmlFor={id}>
        {label}
        {optional && <span className="field__optional"> (facultatif)</span>}
      </label>
      {children({
        id,
        'aria-describedby': describedBy,
        'aria-invalid': error ? true : undefined,
      })}
      {hint && (
        <p className="field__hint" id={hintId}>
          {hint}
        </p>
      )}
      {error && (
        <p className="field__error" id={errorId}>
          <InfoIcon />
          {error}
        </p>
      )}
    </div>
  )
}

/** Text input of the design system (48 px, 56 px inside the sale). */
export function Input({
  className,
  amount = false,
  ...rest
}: ComponentPropsWithRef<'input'> & { amount?: boolean }) {
  return <input {...rest} className={cx('input', amount && 'input--amount', className)} />
}

/**
 * Amount in FCFA: cash-register figures, numeric keyboard on phones (never `type="number"`), and
 * the « FCFA » suffix.
 */
export function AmountInput(props: Omit<ComponentPropsWithRef<'input'>, 'type'>) {
  return (
    <div className="input-group">
      <Input amount type="text" inputMode="numeric" autoComplete="off" {...props} />
      <span className="input-group__suffix" aria-hidden="true">
        FCFA
      </span>
    </div>
  )
}

/** Search box with its magnifier and a button to clear it. The label is read, not shown. */
export function SearchField({
  label,
  value,
  onChange,
  className,
  ...rest
}: Omit<ComponentProps<'input'>, 'value' | 'onChange' | 'type'> & {
  label: string
  value: string
  onChange: (value: string) => void
}) {
  const id = useId()
  const input = useRef<HTMLInputElement>(null)
  return (
    <div className={cx('search', className)}>
      <label className="visually-hidden" htmlFor={id}>
        {label}
      </label>
      <SearchIcon className="search__icon" />
      <input
        {...rest}
        ref={input}
        id={id}
        className="input"
        type="search"
        autoComplete="off"
        value={value}
        onChange={(e) => onChange(e.target.value)}
      />
      {value && (
        <IconButton
          className="search__clear"
          label="Effacer la recherche"
          onClick={() => {
            onChange('')
            input.current?.focus()
          }}
        >
          <CloseIcon />
        </IconButton>
      )}
    </div>
  )
}
