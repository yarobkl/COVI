import { useId, useMemo } from 'react'
import { Field, Input } from '../../components/ui'
import { countrySuggestions, type CountryKind } from './countrySuggestions'

/**
 * « Pays d’origine » with a search: what is typed is kept as is (a city or a market is welcome for
 * a bale), and the matching countries are offered as touch keys under the field.
 */
export function CountryField({
  label,
  value,
  onChange,
  kind,
  optional = false,
  hint,
  error,
  placeholder,
}: {
  label: string
  value: string
  onChange: (value: string) => void
  kind: CountryKind
  optional?: boolean
  hint?: string
  error?: string
  placeholder?: string
}) {
  const listId = useId()
  const suggestions = useMemo(() => countrySuggestions(value, kind), [value, kind])
  return (
    <Field label={label} optional={optional} hint={hint} error={error}>
      {(control) => (
        <>
          <Input
            {...control}
            value={value}
            onChange={(e) => onChange(e.target.value)}
            placeholder={placeholder}
            autoComplete="off"
            maxLength={80}
          />
          {suggestions.length > 0 && (
            <div className="country-keys" role="group" aria-label="Pays proposés" id={listId}>
              {suggestions.map((name) => (
                <button
                  key={name}
                  type="button"
                  className="country-key"
                  onClick={() => onChange(name)}
                >
                  {name}
                </button>
              ))}
            </div>
          )}
        </>
      )}
    </Field>
  )
}
