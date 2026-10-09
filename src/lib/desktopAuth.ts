import { supabase } from './supabase'

const DESKTOP_CALLBACK = 'covi://auth/callback'
const handledCallbacks = new Set<string>()

export const isTauriApp = () => typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window
export const desktopAuthRedirect = () => DESKTOP_CALLBACK

export async function openOAuthInSystemBrowser(url: string) {
  const target = new URL(url)
  if (
    target.protocol !== 'https:' ||
    !target.hostname.endsWith('.supabase.co') ||
    target.pathname !== '/auth/v1/authorize'
  ) {
    throw new Error('L’adresse de connexion reçue n’est pas valide.')
  }
  const { openUrl } = await import('@tauri-apps/plugin-opener')
  await openUrl(target.href)
}

async function acceptOAuthCallback(rawUrl: string, onError: (message: string) => void) {
  let url: URL
  try {
    url = new URL(rawUrl)
  } catch {
    return
  }
  if (url.protocol !== 'covi:' || url.hostname !== 'auth' || url.pathname !== '/callback') return
  if (handledCallbacks.has(rawUrl)) return
  handledCallbacks.add(rawUrl)
  if (url.searchParams.has('error')) {
    onError('La connexion Google a été annulée ou refusée. Vous pouvez réessayer.')
    return
  }
  const code = url.searchParams.get('code')
  if (!code) {
    onError('Le retour de connexion ne contient pas de code valide. Réessayez.')
    return
  }
  const { error } = await supabase.auth.exchangeCodeForSession(code)
  if (error) onError('COVI n’a pas pu terminer la connexion. Réessayez depuis l’application.')
}

export async function listenForDesktopOAuth(onError: (message: string) => void) {
  if (!isTauriApp()) return () => undefined
  const { getCurrent, onOpenUrl } = await import('@tauri-apps/plugin-deep-link')
  const unlisten = await onOpenUrl((urls) => {
    for (const url of urls) void acceptOAuthCallback(url, onError)
  })
  const current = await getCurrent()
  for (const url of current ?? []) void acceptOAuthCallback(url, onError)
  return unlisten
}
