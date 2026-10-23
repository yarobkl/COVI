import type { ReactNode } from 'react'
import { Notice, Skeleton } from '../../components/ui'

/** Onglets d'une page (boutons, pas de changement d'adresse). */
export function SalonTabs<T extends string>({
  label,
  tabs,
  value,
  onChange,
}: {
  label: string
  tabs: readonly { value: T; label: string }[]
  value: T
  onChange: (value: T) => void
}) {
  return (
    <div className="tabs page-tabs" role="tablist" aria-label={label}>
      {tabs.map((t) => (
        <button
          key={t.value}
          type="button"
          role="tab"
          className="tabs__tab"
          aria-selected={value === t.value}
          onClick={() => onChange(t.value)}
        >
          {t.label}
        </button>
      ))}
    </div>
  )
}

/** Message d'une action (succès calme, erreur en rouge). */
export function ActionMessage({ message, isError }: { message: string; isError: boolean }) {
  if (!message) return null
  return <Notice tone={isError ? 'danger' : 'success'}>{message}</Notice>
}

/** Chargement, erreur, ou contenu. */
export function Loaded({
  loading,
  error,
  children,
}: {
  loading: boolean
  error: string
  children: ReactNode
}) {
  if (loading) return <Skeleton caption="On ouvre le cahier du salon…" />
  if (error)
    return (
      <Notice tone="danger" title="Données du salon indisponibles">
        {error}
      </Notice>
    )
  return <>{children}</>
}
