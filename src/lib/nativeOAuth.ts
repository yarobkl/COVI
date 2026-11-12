import { App } from '@capacitor/app'
import { Browser } from '@capacitor/browser'
import { supabase, supabaseUrl } from './supabase'
import { isCoviIosApp } from './nativePlatform'

export const nativeAuthRedirect = 'covi://auth/callback'
const handled = new Set<string>()

export async function openNativeOAuth(url: string) {
  const target = new URL(url)
  if (target.protocol !== 'https:' || target.origin !== new URL(supabaseUrl).origin || target.pathname !== '/auth/v1/authorize') {
    throw new Error('L’adresse de connexion reçue n’est pas valide.')
  }
  await Browser.open({ url: target.href })
}

export async function listenForNativeOAuth(onError: (message: string) => void) {
  if (!isCoviIosApp()) return () => undefined
  const accept = async (raw: string) => {
    let url: URL
    try { url = new URL(raw) } catch { return }
    if (url.protocol !== 'covi:' || url.hostname !== 'auth' || url.pathname !== '/callback') return
    if (handled.has(raw)) return
    handled.add(raw)
    await Browser.close().catch(() => undefined)
    if (url.searchParams.has('error') || url.hash.includes('error=')) {
      onError('La connexion a été annulée ou refusée. Réessayez.')
      return
    }
    const code = url.searchParams.get('code')
    if (!code) {
      onError('Le retour de connexion est incomplet. Réessayez.')
      return
    }
    try {
      const { error } = await supabase.auth.exchangeCodeForSession(code)
      if (error) onError('COVI n’a pas pu terminer la connexion. Réessayez.')
    } catch {
      onError('COVI n’a pas pu terminer la connexion. Réessayez.')
    }
  }
  const listener = await App.addListener('appUrlOpen', ({ url }) => void accept(url))
  const launch = await App.getLaunchUrl()
  if (launch?.url) void accept(launch.url)
  return () => void listener.remove()
}
