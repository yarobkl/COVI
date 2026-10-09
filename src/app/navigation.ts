import type { ComponentType } from 'react'
import {
  BaleIcon,
  BarsIcon,
  BillIcon,
  BoxIcon,
  HangerIcon,
  HomeIcon,
  MenuIcon,
  NotebookIcon,
  ReceiptIcon,
  ShopIcon,
  type IconProps,
} from '../components/icons'

/** Pages of the signed-in application, identified by their title in the side navigation. */
export type Page =
  | 'Tableau de bord'
  | 'Nouvelle vente'
  | 'Mon stock'
  | 'Mes arrivages'
  | 'Mes commandes'
  | 'Mes ballons'
  | 'Produits vendus'
  | 'Charges de la boutique'
  | 'Statistiques'
  | 'Paramètres'

export const defaultPage: Page = 'Tableau de bord'

/** Side navigation, in display order. */
export const sideNavigation: readonly { page: Page; icon: ComponentType<IconProps> }[] = [
  { page: 'Tableau de bord', icon: HomeIcon },
  { page: 'Nouvelle vente', icon: ReceiptIcon },
  { page: 'Mon stock', icon: HangerIcon },
  { page: 'Mes arrivages', icon: BoxIcon },
  { page: 'Mes commandes', icon: BoxIcon },
  { page: 'Mes ballons', icon: BaleIcon },
  { page: 'Produits vendus', icon: NotebookIcon },
  { page: 'Charges de la boutique', icon: BillIcon },
  { page: 'Statistiques', icon: BarsIcon },
  { page: 'Paramètres', icon: ShopIcon },
]

/** Bottom navigation shown on small screens: short label and target page. */
export const bottomNavigation: readonly {
  label: string
  icon: ComponentType<IconProps>
  page: Page
}[] = [
  { label: 'Accueil', icon: HomeIcon, page: 'Tableau de bord' },
  { label: 'Vendre', icon: ReceiptIcon, page: 'Nouvelle vente' },
  { label: 'Stock', icon: HangerIcon, page: 'Mon stock' },
  { label: 'Plus', icon: MenuIcon, page: 'Mes arrivages' },
]
