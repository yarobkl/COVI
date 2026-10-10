import { MinusIcon, PlusIcon } from '../icons'
import { IconButton } from './IconButton'

/** Quantity − n + with tactile keys; the buttons name the article they change. */
export function Stepper({
  value,
  min = 1,
  max,
  onChange,
  itemName,
}: {
  value: number
  min?: number
  max: number
  onChange: (value: number) => void
  itemName: string
}) {
  return (
    <div className="stepper" role="group" aria-label={`Combien de ${itemName} ?`}>
      <IconButton
        variant="tactile"
        label={`Une pièce de moins : ${itemName}`}
        disabled={value <= min}
        onClick={() => onChange(Math.max(min, value - 1))}
      >
        <MinusIcon />
      </IconButton>
      <output className="stepper__value" aria-live="polite">
        {value}
      </output>
      <IconButton
        variant="tactile"
        label={`Une pièce de plus : ${itemName}`}
        disabled={value >= max}
        onClick={() => onChange(Math.min(max, value + 1))}
      >
        <PlusIcon />
      </IconButton>
    </div>
  )
}
