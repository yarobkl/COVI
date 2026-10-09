import { useEffect, useState } from 'react'

/**
 * Runs `load` on mount and whenever it changes (memoize it with useCallback), and keeps the last
 * result. After a failure `error` is true until `retry()` runs `load` again.
 */
export function useAsyncData<T>(load: () => Promise<T>) {
  const [state, setState] = useState<{ data: T | null; error: boolean }>({
    data: null,
    error: false,
  })
  const [attempt, setAttempt] = useState(0)
  useEffect(() => {
    let active = true
    load().then(
      (data) => {
        if (active) setState({ data, error: false })
      },
      () => {
        if (active) setState((s) => ({ ...s, error: true }))
      },
    )
    return () => {
      active = false
    }
  }, [load, attempt])
  const retry = () => {
    setState((s) => ({ ...s, error: false }))
    setAttempt((n) => n + 1)
  }
  return { data: state.data, error: state.error, retry }
}
