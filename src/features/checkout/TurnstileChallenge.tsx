import { useEffect, useRef } from 'react'
import { Notice } from '../../components/ui'

type TurnstileApi = {
  render: (
    element: HTMLElement,
    options: {
      sitekey: string
      action: string
      callback: (token: string) => void
      'expired-callback': () => void
      'error-callback': () => void
    },
  ) => string
  remove: (widgetId: string) => void
}
type TurnstileWindow = Window & { turnstile?: TurnstileApi }
type Props = { onTokenChange: (token: string) => void }

const siteKey = import.meta.env.VITE_COVI_TURNSTILE_SITE_KEY

/** Browser widget only; the Edge gateway independently verifies every token. */
export function TurnstileChallenge({ onTokenChange }: Props) {
  const container = useRef<HTMLDivElement>(null)
  const callback = useRef(onTokenChange)
  useEffect(() => {
    callback.current = onTokenChange
  }, [onTokenChange])

  useEffect(() => {
    if (!siteKey) return
    let cancelled = false
    let widgetId: string | undefined
    const win = window as TurnstileWindow
    const renderWidget = () => {
      if (cancelled || widgetId || !win.turnstile || !container.current) return
      widgetId = win.turnstile.render(container.current, {
        sitekey: siteKey,
        action: 'covi_checkout',
        callback: (token) => callback.current(token),
        'expired-callback': () => callback.current(''),
        'error-callback': () => callback.current(''),
      })
    }

    let script = document.querySelector<HTMLScriptElement>('#covi-turnstile-script')
    if (!script) {
      script = document.createElement('script')
      script.id = 'covi-turnstile-script'
      script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit'
      script.async = true
      script.defer = true
      document.head.appendChild(script)
    }
    script.addEventListener('load', renderWidget)
    renderWidget()
    return () => {
      cancelled = true
      script?.removeEventListener('load', renderWidget)
      if (widgetId) win.turnstile?.remove(widgetId)
    }
  }, [])

  if (!siteKey)
    return (
      <Notice tone="danger">
        <p>Le contrôle anti-robot n'est pas configuré. L'envoi est désactivé.</p>
      </Notice>
    )

  return (
    <div className="checkout-guest__turnstile">
      <p>Vérification de sécurité avant l'envoi</p>
      <div ref={container} aria-label="Vérification anti-robot" />
    </div>
  )
}
