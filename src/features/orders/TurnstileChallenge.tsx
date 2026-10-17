import { useEffect, useRef } from 'react'
import { turnstileSiteKey } from '../../lib/publicOrders'

type TurnstileApi = {
  render: (
    element: HTMLElement,
    options: {
      sitekey: string
      action: string
      language: string
      callback: (token: string) => void
      'expired-callback': () => void
      'error-callback': () => void
    },
  ) => string
  reset: (widgetId: string) => void
  remove: (widgetId: string) => void
}
type TurnstileWindow = Window & { turnstile?: TurnstileApi }

/**
 * Contrôle anti-robot Cloudflare Turnstile. Le navigateur n'obtient qu'un jeton à usage unique :
 * la passerelle le vérifie avec la clé secrète, côté serveur, avant d'enregistrer la demande.
 * `resetKey` : changer sa valeur redemande un jeton neuf (après un envoi refusé).
 */
export function TurnstileChallenge({
  onToken,
  resetKey,
}: {
  onToken: (token: string) => void
  resetKey: number
}) {
  const container = useRef<HTMLDivElement>(null)
  const widget = useRef<string | null>(null)
  const callback = useRef(onToken)
  useEffect(() => {
    callback.current = onToken
  }, [onToken])

  useEffect(() => {
    let cancelled = false
    const win = window as TurnstileWindow
    const render = () => {
      if (cancelled || widget.current || !win.turnstile || !container.current) return
      widget.current = win.turnstile.render(container.current, {
        sitekey: turnstileSiteKey,
        action: 'covi_order',
        language: 'fr',
        callback: (token) => callback.current(token),
        'expired-callback': () => callback.current(''),
        'error-callback': () => callback.current(''),
      })
    }
    let script = document.querySelector<HTMLScriptElement>('#covi-turnstile')
    if (!script) {
      script = document.createElement('script')
      script.id = 'covi-turnstile'
      script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit'
      script.async = true
      document.head.appendChild(script)
    }
    script.addEventListener('load', render)
    render()
    return () => {
      cancelled = true
      script?.removeEventListener('load', render)
      if (widget.current) win.turnstile?.remove(widget.current)
      widget.current = null
    }
  }, [])

  useEffect(() => {
    if (resetKey === 0 || !widget.current) return
    callback.current('')
    ;(window as TurnstileWindow).turnstile?.reset(widget.current)
  }, [resetKey])

  return <div className="order-guest__turnstile" ref={container} />
}
