// COVI icons (design system § 7): drawn for the app, 1.75 px stroke, 24 × 24 grid.
// Few of them on purpose: navigation, icon buttons, payment methods and messages only.
import { Icon, type IconProps } from './Icon'

export type { IconProps }

/** Accueil: small house with its door. */
export const HomeIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M3.5 11 12 4l8.5 7M6 9.5V20h12V9.5M10 20v-5.5h4V20" />
  </Icon>
)

/** Vendre: till receipt with a torn bottom edge. */
export const ReceiptIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M6 3h12v18l-2.5-1.7L13 21l-2.5-1.7L8 21l-2-1.7ZM9 8h6M9 11.5h6M9 15h3.5" />
  </Icon>
)

/** Stock: clothes hanger. */
export const HangerIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M10 6.5a2 2 0 1 1 2 2V10m0 0-8.5 6a1 1 0 0 0 .6 1.8h15.8a1 1 0 0 0 .6-1.8Z" />
  </Icon>
)

/** Ventes: bound notebook. */
export const NotebookIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M6 3.5h11a2 2 0 0 1 2 2v15H8a2 2 0 0 1-2-2ZM6 17a2 2 0 0 1 2-1.5h11M9.5 7.5h6M9.5 11h6" />
  </Icon>
)

/** Arrivage: closed carton with its tape. */
export const BoxIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M3.5 8 12 4l8.5 4v8.5L12 20.5l-8.5-4ZM3.5 8 12 12l8.5-4M12 12v8.5M7.75 6l8.5 4" />
  </Icon>
)

/** Ballon: bundle of second-hand clothes, gathered at the top and tied with string. */
export const BaleIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M7.2 9.4C5 10.4 4 12.3 4 14.5 4 18 7 20 12 20s8-2 8-5.5c0-2.2-1-4.1-3.2-5.1M7.2 9.4c1.5.5 3.1.7 4.8.7s3.3-.2 4.8-.7M8.6 9.2c-.5-1.8.3-3.4 1.7-3.6.7-.1 1.1.4 1.7.4s1-.5 1.7-.4c1.4.2 2.2 1.8 1.7 3.6M12 10.1V20M4.5 13.6c2.5 1 5 1 7.5 0s5-1 7.5 0M4.8 17c2.4 1 4.8 1 7.2 0s4.8-1 7.2 0" />
  </Icon>
)

/** En route: delivery truck. */
export const TruckIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M2.5 6.5H14V16H2.5ZM14 9.5h4l3.5 3.5V16H14" />
    <circle cx="6.5" cy="17.5" r="1.75" />
    <circle cx="17.5" cy="17.5" r="1.75" />
  </Icon>
)

/** Charges: bill with a folded corner and a minus. */
export const BillIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M6 3h9l4 4v14H6ZM15 3v4h4M9.5 13h6" />
  </Icon>
)

/** Bilan: four bars on a line. */
export const BarsIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M3.5 20.5h17M7 17.5V12M11 17.5V7M15 17.5v-7.5M19 17.5V5" />
  </Icon>
)

/** Ma boutique: shop front with a scalloped awning. */
export const ShopIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M3 9h18l-1.5-5h-15ZM3 9a3 3 0 0 0 6 0 3 3 0 0 0 6 0 3 3 0 0 0 6 0M4.5 11.5V20h15v-8.5M10 20v-5h4v5" />
  </Icon>
)

export const SearchIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="10.5" cy="10.5" r="6" />
    <path d="m15 15 5 5" />
  </Icon>
)

export const PlusIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M12 5v14M5 12h14" />
  </Icon>
)

export const MinusIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M5 12h14" />
  </Icon>
)

export const CloseIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="m6 6 12 12M18 6 6 18" />
  </Icon>
)

export const ChevronLeftIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M15 5l-7 7 7 7" />
  </Icon>
)

export const ChevronRightIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="m9 5 7 7-7 7" />
  </Icon>
)

/** Effacer (numeric pad): backspace key. */
export const BackspaceIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M9 5.5h11a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H9L3 12ZM12 9.5l5 5M17 9.5l-5 5" />
  </Icon>
)

/** Pas de réseau: crossed-out cloud. */
export const CloudOffIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M7 18h10.5a3.5 3.5 0 0 0 .3-7 5.5 5.5 0 0 0-10.6-.7A4 4 0 0 0 7 18ZM4 4l16 16" />
  </Icon>
)

/** À envoyer: cloud with an arrow going up. */
export const CloudUpIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M7 18h10.5a3.5 3.5 0 0 0 .3-7 5.5 5.5 0 0 0-10.6-.7A4 4 0 0 0 7 18ZM12 15.5v-4M10.3 13.2 12 11.5l1.7 1.7" />
  </Icon>
)

/** Coché: tick drawn by hand. */
export const CheckIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4 12.5c2 2 4 4 5.5 6.5 3-7 6.5-12 11.5-15" />
  </Icon>
)

/** Espèces: bank note. */
export const CashIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M3 7h18v10H3ZM6.5 10v4M17.5 10v4" />
    <circle cx="12" cy="12" r="2.5" />
  </Icon>
)

/** Mobile Money: phone with waves. */
export const MobileMoneyIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M8 3h8a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1ZM11 18h2M10 8.5c1.3-1 2.7-1 4 0M11 10.8c.6-.4 1.4-.4 2 0" />
  </Icon>
)

/** Carte: bank card. */
export const CardIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M3 6h18v12H3ZM3 10h18M6.5 14.5h4" />
  </Icon>
)

/** Virement: two opposite arrows. */
export const TransferIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4 9h15l-4-4M20 15H5l4 4" />
  </Icon>
)

/** Modifier: pen. */
export const PenIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="m4 20 1-4.5L15.5 5a2.1 2.1 0 0 1 3 3L8 18.5ZM13.5 7l3 3" />
  </Icon>
)

/** Supprimer: bin. */
export const TrashIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4.5 7h15M9.5 7V4.5h5V7M6.5 7l1 13h9l1-13M10.5 11v5.5M13.5 11v5.5" />
  </Icon>
)

/** Menu / Plus: three lines, the last one shorter. */
export const MenuIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4 7h16M4 12h16M4 17h11" />
  </Icon>
)

/** À savoir: « i » in a circle. */
export const InfoIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M12 11v5.5M12 7.75v.25" />
  </Icon>
)

/** Reçu par SMS: speech bubble with two lines. */
export const MessageIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4 5.5h16V16H10l-4 3.5V16H4ZM8 9.5h8M8 12.5h5" />
  </Icon>
)

/** Afficher le mot de passe. */
export const EyeIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12Z" />
    <circle cx="12" cy="12" r="2.75" />
  </Icon>
)

/** Masquer le mot de passe. */
export const EyeOffIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12ZM4 4l16 16" />
    <circle cx="12" cy="12" r="2.75" />
  </Icon>
)
