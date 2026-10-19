import { supabase, supabaseUrl } from './supabase'

export const websiteConnectUrl = `${supabaseUrl}/functions/v1/covi-connect`

export type WebsiteConnection = {
  id: string
  label: string
  siteUrl: string
  keyPrefix: string
  active: boolean
  createdAt: string
  lastUsedAt: string | null
}

export type CreatedWebsiteConnection = Pick<WebsiteConnection, 'id' | 'label' | 'siteUrl' | 'createdAt'> & {
  secret: string
}

async function authenticatedWebsiteRequest<T>(method: 'GET' | 'POST', query: string, payload?: unknown) {
  const { data: { session }, error } = await supabase.auth.getSession()
  if (error || !session?.access_token) throw new Error('Reconnectez-vous à COVI.')
  const response = await fetch(websiteConnectUrl + query, {
    method,
    headers: {
      authorization: `Bearer ${session.access_token}`,
      ...(payload ? { 'content-type': 'application/json' } : {})
    },
    ...(payload ? { body: JSON.stringify(payload) } : {})
  })
  const data = await response.json().catch(() => null)
  if (!response.ok) {
    if (response.status === 401) throw new Error('Session expirée. Reconnectez-vous.')
    if (response.status === 403) throw new Error('Accès réservé au propriétaire de la boutique.')
    throw new Error('Impossible de gérer les sites connectés. Réessayez.')
  }
  return data.result as T
}

export const listWebsiteConnections = (shopId: string) =>
  authenticatedWebsiteRequest<WebsiteConnection[]>('GET', `/manage?shop_id=${encodeURIComponent(shopId)}`)

export const createWebsiteConnection = (shopId: string, label: string, siteUrl: string) =>
  authenticatedWebsiteRequest<CreatedWebsiteConnection>('POST', '/manage', {
    action: 'create', shopId, label, siteUrl
  })

export const revokeWebsiteConnection = (connectionId: string) =>
  authenticatedWebsiteRequest<boolean>('POST', '/manage', { action: 'revoke', connectionId })
