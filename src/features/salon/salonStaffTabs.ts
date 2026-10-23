import type { SalonRole } from '../../lib/salon'

export type StaffTab =
  'home' | 'agenda' | 'caisse' | 'clients' | 'services' | 'team' | 'stock' | 'reports'

export const tabLabels: Record<StaffTab, string> = {
  home: 'Accueil',
  agenda: 'Agenda',
  caisse: 'Caisse',
  clients: 'Clients',
  services: 'Prestations',
  team: 'Équipe',
  stock: 'Produits',
  reports: 'Rapports',
}

/** Ce que chaque rôle voit. Le serveur revérifie chaque action : masquer n'est pas protéger. */
export function tabsFor(role: SalonRole): StaffTab[] {
  if (role === 'stylist') return ['agenda']
  if (role === 'cashier') return ['agenda', 'caisse', 'clients']
  return ['home', 'agenda', 'caisse', 'clients', 'services', 'team', 'stock', 'reports']
}

const byHash: Record<string, StaffTab> = {
  'salon-bookings': 'agenda',
  'salon-caisse': 'caisse',
  'salon-clients': 'clients',
  'salon-services': 'services',
  'salon-equipe': 'team',
  'salon-stock': 'stock',
  'salon-rapports': 'reports',
}

export const tabFromHash = (hash: string): StaffTab | null =>
  byHash[hash.replace(/^#\/?/, '').split('/')[0]] ?? null
