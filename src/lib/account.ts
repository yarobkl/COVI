// Suppression du compte (exigence App Store) : demandée dans Ma boutique, effective 30 jours plus
// tard ; d'ici là, l'utilisateur peut l'annuler. Voir la migration 20261015160000.
import { supabase } from './supabase'

export type AccountDeletion =
  { pending: false } | { pending: true; requestedAt: string; purgeAfter: string }

export type DeletionRequestResult =
  | { status: 'ok'; purgeAfter: string }
  | { status: 'confirm' }
  | { status: 'invalid'; attemptsLeft?: number }
  | { status: 'locked'; retryAfter?: string }

// Les fonctions récentes ne figurent pas encore dans les types générés de la base.
const db = supabase as unknown as {
  rpc: (
    name: string,
    args?: Record<string, unknown>,
  ) => PromiseLike<{ data: unknown; error: unknown }>
}

async function rpc<T>(name: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await db.rpc(name, args)
  if (error) throw error
  return data as T
}

export async function myAccountDeletion(): Promise<AccountDeletion> {
  const d = await rpc<{ pending: boolean; requested_at?: string; purge_after?: string }>(
    'my_account_deletion',
  )
  return d?.pending
    ? { pending: true, requestedAt: String(d.requested_at), purgeAfter: String(d.purge_after) }
    : { pending: false }
}

export async function requestAccountDeletion(
  confirm: string,
  ownerPin: string,
): Promise<DeletionRequestResult> {
  const r = await rpc<{
    status: string
    purge_after?: string
    attempts_left?: number
    retry_after?: string
  }>('request_account_deletion', { p_confirm: confirm, p_owner_pin: ownerPin || null })
  if (r.status === 'ok') return { status: 'ok', purgeAfter: String(r.purge_after) }
  if (r.status === 'invalid') return { status: 'invalid', attemptsLeft: r.attempts_left }
  if (r.status === 'locked') return { status: 'locked', retryAfter: r.retry_after }
  return { status: 'confirm' }
}

export const cancelAccountDeletion = () => rpc<unknown>('cancel_account_deletion')

/** « 14 novembre 2026 » */
export const deletionDay = (iso: string) =>
  new Date(iso).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' })
