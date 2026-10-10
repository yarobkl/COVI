import { useId } from 'react'
import '../../styles/app/filters.css'
import { cx } from './cx'

export type FilterChip<T extends string> = { value: T; label: string }

/**
 * A screen filter written as a row of words (« Aujourd’hui · 7 jours · Ce mois · Tout »): real
 * radio buttons, so arrow keys and screen readers work; the chosen word is circled in pen. Lighter
 * than `Segmented`, which stays for the payment method of the sale.
 */
export function FilterChips<T extends string>({
  legend,
  hideLegend = false,
  options,
  value,
  onChange,
  className,
}: {
  legend: string
  /** The legend is still read by screen readers. */
  hideLegend?: boolean
  options: readonly FilterChip<T>[]
  value: T
  onChange: (value: T) => void
  className?: string
}) {
  const name = useId()
  return (
    <fieldset className={cx('chips', className)}>
      <legend className={hideLegend ? 'visually-hidden' : 'chips__legend'}>{legend}</legend>
      <div className="chips__options">
        {options.map((option) => (
          <label className="chips__option" key={option.value}>
            <input
              className="chips__input"
              type="radio"
              name={name}
              value={option.value}
              checked={value === option.value}
              onChange={() => onChange(option.value)}
            />
            <span className="chips__label">{option.label}</span>
          </label>
        ))}
      </div>
    </fieldset>
  )
}
