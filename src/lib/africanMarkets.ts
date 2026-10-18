/**
 * Country/currency directory for COVI onboarding. ISO 4217, NOT implicit
 * exchange rates. Region membership and currency union are separate facts.
 *
 * BEAC: https://www.beac.int/billets-pieces/histoire-franc-cfa/
 * BCEAO: https://www.bceao.int/en/content/presentation-wamu
 * ECOWAS members: https://www.ecowas.int/?page_id=40
 * ECOWAS withdrawal (2025-01-29): https://www.ecowas.int/press-statement-2/
 * DRC central bank: https://www.bcc.cd/la-banque/billets-et-monnaie/role-et-enjeux-du-franc-congolais
 * UN M49: https://unstats.un.org/unsd/methodology/m49/
 */
export const AFRICAN_MARKET_GROUPS = [
  { key: 'cemac', label: 'CEMAC — Afrique centrale (XAF)' },
  { key: 'uemoa', label: 'UEMOA — Afrique de l’Ouest (XOF)' },
  { key: 'ecowas_other', label: 'CEDEAO — autres monnaies nationales' },
  { key: 'central_other', label: 'Afrique centrale hors CEMAC' },
  { key: 'great_lakes', label: 'Grands Lacs — pays complémentaires' },
] as const

export const AFRICAN_MARKETS = [
  { country: 'République du Congo', region: 'cemac', currency: 'XAF' },
  { country: 'Cameroun', region: 'cemac', currency: 'XAF' },
  { country: 'Gabon', region: 'cemac', currency: 'XAF' },
  { country: 'République centrafricaine', region: 'cemac', currency: 'XAF' },
  { country: 'Guinée équatoriale', region: 'cemac', currency: 'XAF' },
  { country: 'Tchad', region: 'cemac', currency: 'XAF' },
  { country: 'Côte d’Ivoire', region: 'uemoa', currency: 'XOF' },
  { country: 'Bénin', region: 'uemoa', currency: 'XOF' },
  { country: 'Sénégal', region: 'uemoa', currency: 'XOF' },
  { country: 'Togo', region: 'uemoa', currency: 'XOF' },
  { country: 'Guinée-Bissau', region: 'uemoa', currency: 'XOF' },
  { country: 'Burkina Faso', region: 'uemoa', currency: 'XOF' },
  { country: 'Mali', region: 'uemoa', currency: 'XOF' },
  { country: 'Niger', region: 'uemoa', currency: 'XOF' },
  { country: 'Ghana', region: 'ecowas_other', currency: 'GHS' },
  { country: 'Nigeria', region: 'ecowas_other', currency: 'NGN' },
  { country: 'Guinée', region: 'ecowas_other', currency: 'GNF' },
  { country: 'Gambie', region: 'ecowas_other', currency: 'GMD' },
  { country: 'Libéria', region: 'ecowas_other', currency: 'LRD' },
  { country: 'Sierra Leone', region: 'ecowas_other', currency: 'SLE' },
  { country: 'Cap-Vert', region: 'ecowas_other', currency: 'CVE' },
  {
    country: 'République démocratique du Congo',
    region: 'central_other',
    currency: 'CDF',
    secondary: 'USD',
  },
  { country: 'Angola', region: 'central_other', currency: 'AOA' },
  { country: 'São Tomé-et-Príncipe', region: 'central_other', currency: 'STN' },
  { country: 'Burundi', region: 'great_lakes', currency: 'BIF' },
  { country: 'Rwanda', region: 'great_lakes', currency: 'RWF' },
] as const

export type AfricanCountry = (typeof AFRICAN_MARKETS)[number]['country']
export type AfricanCurrency = (typeof AFRICAN_MARKETS)[number]['currency'] | 'USD'

export function marketForCountry(country: string) {
  return AFRICAN_MARKETS.find((entry) => entry.country === country) ?? null
}

export function officialCurrencyForCountry(country: string): AfricanCurrency | null {
  return marketForCountry(country)?.currency ?? null
}

export function paymentCurrenciesForCountry(country: string): readonly AfricanCurrency[] {
  const market = marketForCountry(country)
  if (!market) return []
  return 'secondary' in market ? [market.currency, market.secondary] : [market.currency]
}

export function currencyLabel(currency: AfricanCurrency): string {
  const labels: Record<AfricanCurrency, string> = {
    XAF: 'Franc CFA d’Afrique centrale (XAF)',
    XOF: 'Franc CFA d’Afrique de l’Ouest (XOF)',
    CDF: 'Franc congolais (CDF)',
    USD: 'Dollar américain (USD)',
    AOA: 'Kwanza angolais (AOA)',
    STN: 'Dobra de São Tomé-et-Príncipe (STN)',
    BIF: 'Franc burundais (BIF)',
    RWF: 'Franc rwandais (RWF)',
    GHS: 'Cedi ghanéen (GHS)',
    NGN: 'Naira nigérian (NGN)',
    GNF: 'Franc guinéen (GNF)',
    GMD: 'Dalasi gambien (GMD)',
    LRD: 'Dollar libérien (LRD)',
    SLE: 'Leone sierra-léonais (SLE)',
    CVE: 'Escudo cap-verdien (CVE)',
  }
  return labels[currency]
}
