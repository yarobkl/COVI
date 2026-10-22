/**
 * CRM identity helpers. Pure functions: no database access, persistence or cross-shop lookup.
 * An email or a telephone number is never sufficient proof that two people are the same.
 * Future database uniqueness must ALWAYS include shop_id (tenant boundary).
 */

export type CrmIdentity = {
  name: string
  email: string | null
  phone: string | null
}

export type CrmIdentityInput = {
  name: string
  email?: string | null
  phone?: string | null
}

const clean = (value: string | null | undefined): string | null => {
  const trimmed = value?.trim() ?? ''
  return trimmed.length ? trimmed : null
}

/** Lowercase the email domain and local part for a comparison hint, not as a primary key. */
export function comparisonEmail(value: string | null | undefined): string | null {
  const input = clean(value)
  if (!input) return null
  if (/\s/.test(input)) return null
  const separator = input.lastIndexOf('@')
  if (separator < 1 || separator === input.length - 1) return null
  return input.toLowerCase()
}

/**
 * A phone comparison hint. No country inference: local numbers in different countries
 * must never be merged. Only international +country-code numbers are compared.
 */
export function comparisonInternationalPhone(value: string | null | undefined): string | null {
  const input = clean(value)
  if (!input || !/^\+[\d\s().-]+$/.test(input)) return null
  const digits = input.replace(/\D/g, '')
  if (digits.length < 8 || digits.length > 15 || digits.startsWith('0')) return null
  return '+' + digits
}

export function prepareCrmIdentity(input: CrmIdentityInput): CrmIdentity {
  const name = input.name.trim().replace(/\s+/g, ' ')
  if (!name) throw new Error('Le nom du client est obligatoire.')
  if (name.length > 160) throw new Error('Le nom du client est trop long.')
  const email = clean(input.email)
  const phone = clean(input.phone)
  if (email && (!comparisonEmail(email) || email.length > 254))
    throw new Error("L'adresse e-mail est invalide.")
  if (phone && phone.length > 40) throw new Error('Le numéro de téléphone est trop long.')
  return { name, email, phone }
}

/**
 * Possible duplicate only; NEVER automatic account merge.
 * The caller must already restrict records to the same shop_id.
 */
export function possibleDuplicate(a: CrmIdentity, b: CrmIdentity): boolean {
  const aEmail = comparisonEmail(a.email)
  const bEmail = comparisonEmail(b.email)
  if (aEmail && bEmail && aEmail === bEmail) return true
  const aPhone = comparisonInternationalPhone(a.phone)
  const bPhone = comparisonInternationalPhone(b.phone)
  return Boolean(aPhone && bPhone && aPhone === bPhone)
}
