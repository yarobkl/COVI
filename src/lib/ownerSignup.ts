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
  return {
    businessKind: isBusinessKind(value('business_kind')) ? (value('business_kind') as BusinessKind) : 'retail',
    businessName: value('business_name').slice(0, 120),
    firstName: value('first_name').slice(0, 80),
    lastName: value('last_name').slice(0, 80),
    phone: value('phone_number').slice(0, 32),
  }
}
