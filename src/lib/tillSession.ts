// Session de caisse de l'appareil partagé (compte du propriétaire, « Changer de caissier »).
//
// Le jeton renvoyé par open_till_session donne le droit de vendre au nom d'un caissier : il est
// gardé en mémoire et, au plus, dans sessionStorage (perdu à la fermeture de l'onglet), JAMAIS
// dans localStorage. Il est effacé à la fermeture de la session, au changement de caissier, à la
// déconnexion et dès qu'il expire.
import type { TillSession } from './team'

const KEY = 'covi:till-session:v1'
let current: TillSession | null = null
let loaded = false
const listeners = new Set<() => void>()

function load(): TillSession | null {
  if (loaded) return current
  loaded = true
  try {
    const raw = sessionStorage.getItem(KEY)
    current = raw ? (JSON.parse(raw) as TillSession) : null
  } catch {
    current = null
  }
  return current
}

function save(session: TillSession | null) {
  current = session
  loaded = true
  try {
    if (session) sessionStorage.setItem(KEY, JSON.stringify(session))
    else sessionStorage.removeItem(KEY)
  } catch {
    // Private mode or storage disabled: memory only.
  }
  listeners.forEach((l) => l())
}

/**
 * Current session for `shopId`, or null (none, another shop, or expired). An expired session is
 * forgotten, unless `forget` is false (React snapshots must not change the store).
 */
export function getTillSession(
  shopId: string,
  now = Date.now(),
  forget = true,
): TillSession | null {
  const s = load()
  if (!s) return null
  if (new Date(s.expiresAt).getTime() <= now) {
    if (forget) save(null)
    return null
  }
  return s.shopId === shopId ? s : null
}

export const setTillSession = (session: TillSession) => save(session)
export const clearTillSession = () => save(null)

/** Token to forget on sign-out, read without expiry checks. */
export const peekTillSession = () => load()

export function subscribeTillSession(listener: () => void) {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}
