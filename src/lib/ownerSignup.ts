import { isBusinessKind, type BusinessKind } from './businessKinds'

/**
 * Account profile and requested establishment are user-editable onboarding hints.
 * Never use this metadata to authorize shop, employee or cashier permissions.
 */
export type OwnerSignupDetails = {
  first_name: string
  last_name: string
  full_name: string
  phone_number: string
  business_kind: BusinessKind
  business_name: string
}

export const normalizePhone = (phone: string) => phone.replace(/[\s().-]/g, '').trim()

export function isValidOwnerPhone(phone: string): boolean {
  return /^\+[1-9][0-9]{7,14}$/.test(normalizePhone(phone))
}

export function createOwnerSignupDetails(args: {
  firstName: string
  lastName: string
  phone: string
  businessKind: string
  businessName: string
}): OwnerSignupDetails {
  const firstName = args.firstName.trim().replace(/\s+/g, ' ')
  const lastName = args.lastName.trim().replace(/\s+/g, ' ')
  const businessName = args.businessName.trim().replace(/\s+/g, ' ')
  if (firstName.length < 2 || firstName.length > 80 || lastName.length < 2 || lastName.length > 80)
    throw Error('Indiquez un prénom et un nom de 2 à 80 caractères.')
  if (!isValidOwnerPhone(args.phone))
    throw Error('Saisissez un téléphone international valide, par exemple +242061234567.')
  if (!isBusinessKind(args.businessKind)) throw Error('Choisissez une activité proposée par COVI.')
  if (businessName.length < 2 || businessName.length > 120)
    throw Error('Le nom de votre établissement doit contenir 2 à 120 caractères.')
  return {
    first_name: firstName,
    last_name: lastName,
    full_name: firstName + ' ' + lastName,
    phone_number: normalizePhone(args.phone),
    business_kind: args.businessKind,
    business_name: businessName,
  }
}

export function ownerOnboardingHints(metadata: Record<string, unknown> | null | undefined): {
  businessKind: BusinessKind
  businessName: string
  firstName: string
  lastName: string
  phone: string
} {
  const value = (key: string) =>
    typeof metadata?.[key] === 'string' ? (metadata[key] as string).trim() : ''
  const fullName = value('full_name') || value('name')
  const pieces = fullName.split(/\s+/).filter(Boolean)
  const oauthIntent = readOwnerOAuthIntent()
  const fromAuthKind = value('business_kind')
  return {
    businessKind: isBusinessKind(fromAuthKind)
      ? fromAuthKind
      : (oauthIntent?.businessKind ?? 'retail'),
    businessName: (value('business_name') || oauthIntent?.businessName || '').slice(0, 120),
    firstName: (value('first_name') || pieces[0] || '').slice(0, 80),
    lastName: (value('last_name') || pieces.slice(1).join(' ') || '').slice(0, 80),
    phone: value('phone_number').slice(0, 32),
  }
}

/** Short-lived UX hints across OAuth redirect; NEVER an authorization source. */
const SIGNUP_INTENT_KEY = 'covi:owner-oauth-intent:v1'

export function storeOwnerOAuthIntent(kind: BusinessKind, businessName: string) {
  if (typeof sessionStorage === 'undefined') return
  try {
    sessionStorage.setItem(
      SIGNUP_INTENT_KEY,
      JSON.stringify({ kind, businessName: businessName.trim().slice(0, 120), at: Date.now() }),
    )
  } catch {
    // Private-mode and restricted-storage browsers can still complete onboarding manually.
  }
}

export function readOwnerOAuthIntent(): {
  businessKind: BusinessKind
  businessName: string
} | null {
  if (typeof sessionStorage === 'undefined') return null
  try {
    const raw = sessionStorage.getItem(SIGNUP_INTENT_KEY)
    if (!raw) return null
    const value = JSON.parse(raw) as { kind?: string; businessName?: string; at?: number }
    if (
      !value.at ||
      !Number.isFinite(value.at) ||
      value.at > Date.now() ||
      Date.now() - value.at > 60 * 60 * 1000 ||
      !value.kind ||
      !isBusinessKind(value.kind)
    ) {
      sessionStorage.removeItem(SIGNUP_INTENT_KEY)
      return null
    }
    return {
      businessKind: value.kind,
      businessName: typeof value.businessName === 'string' ? value.businessName.slice(0, 120) : '',
    }
  } catch {
    return null
  }
}

export function clearOwnerOAuthIntent() {
  if (typeof sessionStorage === 'undefined') return
  try {
    sessionStorage.removeItem(SIGNUP_INTENT_KEY)
  } catch {
    // Clearing a non-sensitive hint must never prevent the shop from opening.
  }
}
