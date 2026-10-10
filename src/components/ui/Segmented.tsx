import { useId, type ReactNode } from 'react'
import { cx } from './cx'

export type SegmentedOption<T extends string> = { value: T; label: string; icon?: ReactNode }

/**
 * A choice among a few options (payment method) made of real radio buttons: arrow keys, screen
 * readers and forms work for free. `sale`: tactile keys that stay pressed, yellow when chosen.
 */
export function Segmented<T extends string>({
  legend,
  options,
  value,
  onChange,
  sale = false,
  className,
}: {
  legend: ReactNode
  options: readonly SegmentedOption<T>[]
  value: T | null
  onChange: (value: T) => void
  sale?: boolean
  className?: string
}) {
  const name = useId()
  return (
    <fieldset className={cx('segmented', sale && 'segmented--sale', className)}>
      <legend className="segmented__legend">{legend}</legend>
      <div className="segmented__options">
        {options.map((option) => (
          <label className="segmented__option" key={option.value}>
            <input
              className="segmented__input"
              type="radio"
              name={name}
              value={option.value}
              checked={value === option.value}
              onChange={() => onChange(option.value)}
            />
            <span className="segmented__label">
              {option.icon}
              {option.label}
            </span>
          </label>
        ))}
      </div>
    </fieldset>
  )
}
