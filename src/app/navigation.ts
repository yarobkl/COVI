import {
  Boxes,
  ChartNoAxesCombined,
  History,
  Home,
  Menu,
  Package,
  ReceiptText,
  Settings,
  Ship,
  ShoppingCart,
  type LucideIcon,
} from 'lucide-react'

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
export const sideNavigation: readonly { page: Page; icon: LucideIcon }[] = [
  { page: 'Tableau de bord', icon: Home },
  { page: 'Nouvelle vente', icon: ShoppingCart },
  { page: 'Mon stock', icon: Package },
  { page: 'Mes arrivages', icon: Ship },
  { page: 'Mes commandes', icon: Boxes },
  { page: 'Mes ballons', icon: Boxes },
  { page: 'Produits vendus', icon: History },
  { page: 'Charges de la boutique', icon: ReceiptText },
  { page: 'Statistiques', icon: ChartNoAxesCombined },
  { page: 'Paramètres', icon: Settings },
]

/** Bottom navigation shown on small screens: short label and target page. */
export const bottomNavigation: readonly { label: string; icon: LucideIcon; page: Page }[] = [
  { label: 'Accueil', icon: Home, page: 'Tableau de bord' },
  { label: 'Vendre', icon: ShoppingCart, page: 'Nouvelle vente' },
  { label: 'Stock', icon: Package, page: 'Mon stock' },
  { label: 'Plus', icon: Menu, page: 'Mes arrivages' },
]
