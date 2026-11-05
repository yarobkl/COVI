/** Runtime guard: iOS styling is enabled only inside the actual Capacitor WKWebView.
 * Safari on iPhone and the Vercel website must keep the web visual identity. */
type NativeBridge = {
  getPlatform?: () => string
  isNativePlatform?: () => boolean
}

export function isCoviIosApp(): boolean {
  const bridge = (window as Window & { Capacitor?: NativeBridge }).Capacitor
  return bridge?.getPlatform?.() === 'ios' && bridge.isNativePlatform?.() !== false
}
