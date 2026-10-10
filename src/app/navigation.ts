import type { ComponentType } from 'react'
import {
  BarsIcon,
  BillIcon,
  BoxIcon,
  HangerIcon,
  HomeIcon,
  NotebookIcon,
  ReceiptIcon,
  ShopIcon,
  type IconProps,
} from '../components/icons'
import type { PageId } from './routes'

export type NavEntry = { page: PageId; label: string; icon: ComponentType<IconProps> }

/** Every page, with the words of the shop (TON-ET-VOCABULAIRE.md). */
export const pages: Record<PageId, NavEntry> = {
  accueil: { page: 'accueil', label: 'Accueil', icon: HomeIcon },
  vendre: { page: 'vendre', label: 'Vendre', icon: ReceiptIcon },
  stock: { page: 'stock', label: 'Stock', icon: HangerIcon },
  arrivages: { page: 'arrivages', label: 'Arrivages', icon: BoxIcon },
  ventes: { page: 'ventes', label: 'Ventes', icon: NotebookIcon },
  charges: { page: 'charges', label: 'Charges', icon: BillIcon },
  bilan: { page: 'bilan', label: 'Bilan', icon: BarsIcon },
  boutique: { page: 'boutique', label: 'Ma boutique', icon: ShopIcon },
}

/** Computer « Sommaire », under the « Nouvelle vente » key (which leads to Vendre). */
export const sommaire: readonly NavEntry[] = [
  pages.accueil,
  pages.stock,
  pages.arrivages,
  pages.ventes,
  pages.charges,
  pages.bilan,
  pages.boutique,
]

/** Phone bottom bar: Accueil · Vendre (key) · Stock, then « Plus » opens the menu. */
export const bottomBar: readonly NavEntry[] = [pages.accueil, pages.vendre, pages.stock]

/** Pages listed in the « Plus » menu on phones. */
export const morePages: readonly NavEntry[] = [
  pages.arrivages,
  pages.ventes,
  pages.charges,
  pages.bilan,
  pages.boutique,
]
