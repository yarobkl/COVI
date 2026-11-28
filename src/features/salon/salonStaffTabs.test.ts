import { describe, expect, it } from 'vitest'
import { tabFromHash, tabsFor } from './salonStaffTabs'

describe('espace des collaborateurs du salon', () => {
  it('chaque rôle voit seulement ses écrans', () => {
    expect(tabsFor('stylist')).toEqual(['agenda'])
    expect(tabsFor('cashier')).toEqual(['agenda', 'caisse', 'clients'])
    expect(tabsFor('manager')).toContain('reports')
    expect(tabsFor('cashier')).not.toContain('reports')
    expect(tabsFor('cashier')).not.toContain('team')
  })

  it('les liens de l’accueil ouvrent l’onglet correspondant', () => {
    expect(tabFromHash('#/salon-caisse')).toBe('caisse')
    expect(tabFromHash('#/salon-bookings')).toBe('agenda')
    expect(tabFromHash('#/vendre')).toBeNull()
  })
})
