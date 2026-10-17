import type { PageId } from './routes'
import { pages, sommaire, bottomBar, morePages } from './navigation'
import type { NavEntry } from './navigation'

export type Sector = 'retail' | 'restaurant' | 'salon'
export const sectorOf = (value: string | null | undefined): Sector =>
  value === 'restaurant' || value === 'salon' ? value : 'retail'

const restaurantPages = [
  pages.accueil,
  pages['restaurant-orders'],
  pages['restaurant-tables'],
  pages['restaurant-menu'],
  pages.personnel,
  pages.charges,
  pages.boutique,
] as const
const salonPages = [
  pages.accueil,
  pages['salon-services'],
  pages['salon-bookings'],
  pages.personnel,
  pages.charges,
  pages.boutique,
] as const

export function navigationFor(kind: Sector): {
  sommaire: readonly NavEntry[]
  bottomBar: readonly NavEntry[]
  morePages: readonly NavEntry[]
  primary: PageId
} {
  if (kind === 'restaurant')
    return {
      sommaire: restaurantPages,
      bottomBar: restaurantPages.slice(0, 3),
      morePages: restaurantPages.slice(3),
      primary: 'restaurant-orders',
    }
  if (kind === 'salon')
    return {
      sommaire: salonPages,
      bottomBar: salonPages.slice(0, 3),
      morePages: salonPages.slice(3),
      primary: 'salon-services',
    }
  return { sommaire, bottomBar, morePages, primary: 'vendre' }
}

export const availableInSector = (kind: Sector, page: PageId) =>
  kind === 'retail'
    ? !['restaurant-orders', 'restaurant-tables', 'restaurant-menu', 'salon-services', 'salon-bookings'].includes(page)
    : navigationFor(kind).sommaire.some((x) => x.page === page)
