import type { ComponentType } from 'react'
import {
  BarsIcon,
  BillIcon,
  BoxIcon,
  HangerIcon,
  HomeIcon,
  NotebookIcon,
  PeopleIcon,
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
  commandes: { page: 'commandes', label: 'Commandes', icon: BoxIcon },
  stock: { page: 'stock', label: 'Stock', icon: HangerIcon },
  arrivages: { page: 'arrivages', label: 'Arrivages', icon: BoxIcon },
  ventes: { page: 'ventes', label: 'Ventes', icon: NotebookIcon },
  charges: { page: 'charges', label: 'Charges', icon: BillIcon },
  personnel: { page: 'personnel', label: 'Personnel', icon: PeopleIcon },
  bilan: { page: 'bilan', label: 'Bilan', icon: BarsIcon },
  boutique: { page: 'boutique', label: 'Ma boutique', icon: ShopIcon },
  assistant: { page: 'assistant', label: 'Assistant IA', icon: NotebookIcon },
  'restaurant-orders': { page: 'restaurant-orders', label: 'Service & caisse', icon: ReceiptIcon },
  'restaurant-tables': { page: 'restaurant-tables', label: 'Plan de salle', icon: BoxIcon },
  'restaurant-menu': { page: 'restaurant-menu', label: 'Carte & boissons', icon: NotebookIcon },
  'salon-services': { page: 'salon-services', label: 'Prestations', icon: ReceiptIcon },
  'salon-bookings': { page: 'salon-bookings', label: 'Agenda', icon: NotebookIcon },
  'salon-caisse': { page: 'salon-caisse', label: 'Caisse', icon: ReceiptIcon },
  'salon-clients': { page: 'salon-clients', label: 'Clients', icon: PeopleIcon },
  'salon-equipe': { page: 'salon-equipe', label: 'Équipe', icon: PeopleIcon },
  'salon-stock': { page: 'salon-stock', label: 'Produits', icon: BoxIcon },
  'salon-rapports': { page: 'salon-rapports', label: 'Rapports', icon: BarsIcon },
  'salon-reglages': { page: 'salon-reglages', label: 'Réglages du salon', icon: ShopIcon },
}

/** Computer « Sommaire », under the « Nouvelle vente » key (which leads to Vendre). */
export const sommaire: readonly NavEntry[] = [
  pages.accueil,
  pages.commandes,
  pages.stock,
  pages.arrivages,
  pages.ventes,
  pages.charges,
  pages.personnel,
  pages.bilan,
  pages.assistant,
  pages.boutique,
]

/** Phone bottom bar: Accueil · Vendre (key) · Stock, then « Plus » opens the menu. */
export const bottomBar: readonly NavEntry[] = [pages.accueil, pages.vendre, pages.stock]

/** Pages listed in the « Plus » menu on phones. */
export const morePages: readonly NavEntry[] = [
  pages.commandes,
  pages.arrivages,
  pages.ventes,
  pages.charges,
  pages.personnel,
  pages.bilan,
  pages.assistant,
  pages.boutique,
]
