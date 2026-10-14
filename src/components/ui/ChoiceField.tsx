import { useState } from 'react'

const CUSTOM = '__covi_choice_other__'

/** A real mobile-friendly dropdown, with a separate text box only for NEW values. */
export function ChoiceField({
  name,
  choices,
  required = false,
  prompt = 'Choisir dans la liste',
  otherLabel = 'Autre / Ajouter une valeur',
  customPlaceholder = 'Saisir une nouvelle valeur',
}: {
  name: string
  choices: readonly string[]
  required?: boolean
  prompt?: string
  otherLabel?: string
  customPlaceholder?: string
}) {
  const [chosen, setChosen] = useState('')
  const unique = [...new Set(choices.map((value) => value.trim()).filter(Boolean))]
  const custom = chosen === CUSTOM

  return (
    <>
      <select
        name={custom ? undefined : name}
        value={chosen}
        required={required}
        onChange={(event) => setChosen(event.target.value)}
      >
        <option value="">{prompt}</option>
        {unique.map((value) => (
          <option key={value} value={value}>
            {value}
          </option>
        ))}
        <option value={CUSTOM}>{otherLabel}</option>
      </select>
      {custom && (
        <input
          name={name}
          required={required}
          placeholder={customPlaceholder}
          aria-label={customPlaceholder}
          autoComplete="off"
        />
      )}
    </>
  )
}
