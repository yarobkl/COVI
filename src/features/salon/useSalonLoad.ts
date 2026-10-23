import { useCallback, useEffect, useState } from 'react'
import { salonErrorMessage } from '../../lib/salon'
import { salonDay } from './salonFormat'

/**
 * Charge des données du salon et les recharge à la demande. `load` doit être stable
 * (useCallback) : chaque nouvelle fonction relance le chargement.
 */
export function useSalonLoad<T>(load: () => Promise<T>) {
  const [data, setData] = useState<T | null>(null)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)
  const [version, setVersion] = useState(0)

  useEffect(() => {
    let alive = true
    load().then(
      (value) => {
        if (!alive) return
        setData(value)
        setError('')
        setLoading(false)
      },
      (e: unknown) => {
        if (!alive) return
        setError(salonErrorMessage(e))
        setLoading(false)
      },
    )
    return () => {
      alive = false
    }
  }, [load, version])

  const reload = useCallback(() => setVersion((v) => v + 1), [])
  return { data, error, loading, reload, setData }
}

/** Exécute une action, garde le message de résultat et empêche le double envoi. */
export function useSalonAction() {
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  const [isError, setIsError] = useState(false)
  const run = useCallback(async <T>(action: () => Promise<T>, success?: string) => {
    setBusy(true)
    try {
      const result = await action()
      setIsError(false)
      setMessage(success ?? '')
      return result
    } catch (e) {
      setIsError(true)
      setMessage(salonErrorMessage(e))
      return undefined
    } finally {
      setBusy(false)
    }
  }, [])
  const clear = useCallback(() => setMessage(''), [])
  return { busy, message, isError, run, clear, setMessage, setIsError }
}

/**
 * Jour courant dans le fuseau du salon, recalculé chaque minute : une page laissée ouverte
 * après minuit passe d'elle-même au nouveau jour.
 */
export function useSalonToday(tz: string) {
  const [today, setToday] = useState(() => salonDay(new Date(), tz))
  useEffect(() => {
    const tick = () => setToday(salonDay(new Date(), tz))
    tick()
    const timer = setInterval(tick, 60000)
    return () => clearInterval(timer)
  }, [tz])
  return today
}
