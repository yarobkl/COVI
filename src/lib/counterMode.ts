// « Mode comptoir » de l'appareil partagé (compte du propriétaire) : dès qu'un caissier prend la
// caisse, l'application n'affiche plus que l'espace du comptoir ; seul le code du responsable,
// vérifié par la base (leave_counter_mode), rend l'application complète.
//
// Le drapeau est gardé dans localStorage, et non sessionStorage : fermer l'onglet ou recharger la
// page ne doit pas rendre l'application du responsable sans code. Il ne contient AUCUN secret
// (pas de jeton de caisse, pas de code) : seulement la boutique concernée. Le jeton de la session
// de caisse reste en mémoire et dans sessionStorage (src/lib/tillSession.ts).
//
// Il est effacé seulement par la sortie du mode comptoir (code du responsable) et à la
// déconnexion (revenir demande alors le mot de passe du compte).

const KEY = 'covi:counter-mode:v1'
const listeners = new Set<() => void>()

type Stored = { shopId: string; since: string }

function read(): Stored | null {
  try {
    const raw = localStorage.getItem(KEY)
    if (!raw) return null
    const value = JSON.parse(raw) as Partial<Stored> | null
    return value && typeof value.shopId === 'string'
      ? { shopId: value.shopId, since: String(value.since ?? '') }
      : null
  } catch {
    return null
  }
}

// Fallback when storage is unavailable (private mode): the flag lives in memory for this tab.
let memory: Stored | null = null

const current = () => read() ?? memory

function write(value: Stored | null) {
  memory = value
  try {
    if (value) localStorage.setItem(KEY, JSON.stringify(value))
    else localStorage.removeItem(KEY)
  } catch {
    // Storage disabled: memory only.
  }
  listeners.forEach((l) => l())
}

/** Whether the counter mode is on for this shop. */
export const isCounterMode = (shopId: string) => current()?.shopId === shopId

/** Turns the counter mode on (a cashier took the till on the owner's device). */
export const enterCounterMode = (shopId: string) =>
  write({ shopId, since: new Date().toISOString() })

/** Full application back: ONLY after the server accepted the owner's PIN, or at sign-out. */
export const clearCounterMode = () => write(null)

export function subscribeCounterMode(listener: () => void) {
  listeners.add(listener)
  // Another tab of the same device entering or leaving the counter mode.
  const onStorage = (e: StorageEvent) => {
    if (e.key === KEY) listener()
  }
  window.addEventListener('storage', onStorage)
  return () => {
    listeners.delete(listener)
    window.removeEventListener('storage', onStorage)
  }
}
