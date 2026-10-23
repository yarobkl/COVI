import { Button } from '../../components/ui'
import type { MemberShop } from '../../lib/team'
import type { RestaurantStaffSpace } from '../../lib/restaurantStaff'
import type { SalonSpace } from '../../lib/salon'
import type { Shop } from '../../lib/types'
import { AuthPage } from '../auth/AuthPage'

/** Which space to open when the account owns a shop AND works as a cashier elsewhere. */
export type SpaceChoice =
  | { kind: 'owner' }
  | { kind: 'cashier'; shopId: string }
  | { kind: 'restaurant-staff'; shopId: string }
  | { kind: 'salon-staff'; shopId: string }

/** « Où travaillez-vous aujourd’hui ? » : the owned shop, then each cashier membership. */
export function SpaceChooser({
  shop,
  memberships,
  restaurantSpaces = [],
  salonSpaces = [],
  onChoose,
  onJoin,
  onRestaurantJoin,
  onSalonJoin,
  onSignOut,
}: {
  shop: Shop | null
  memberships: MemberShop[]
  restaurantSpaces?: RestaurantStaffSpace[]
  salonSpaces?: SalonSpace[]
  onRestaurantJoin?: () => void
  onSalonJoin?: () => void
  onChoose: (choice: SpaceChoice) => void
  onJoin: () => void
  onSignOut: () => void
}) {
  return (
    <AuthPage title="Où travaillez-vous aujourd’hui ?" lead="Choisissez la boutique à ouvrir.">
      <ul className="space-chooser">
        {shop && (
          <li>
            <Button variant="primary" size="lg" block onClick={() => onChoose({ kind: 'owner' })}>
              {shop.name} · responsable
            </Button>
          </li>
        )}
        {memberships.map((m) => (
          <li key={m.member_id}>
            <Button
              variant="secondary"
              size="lg"
              block
              onClick={() => onChoose({ kind: 'cashier', shopId: m.shop_id })}
            >
              Caisse de {m.shop_name}
            </Button>
          </li>
        ))}
        {restaurantSpaces.map((space) => (
          <li key={space.shop_id}>
            <Button
              variant="secondary"
              block
              size="lg"
              onClick={() => onChoose({ kind: 'restaurant-staff', shopId: space.shop_id })}
            >
              {space.shop_name} ·{' '}
              {space.staff_role === 'waiter'
                ? 'Service'
                : space.staff_role === 'kitchen'
                  ? 'Cuisine'
                  : 'Caisse restaurant'}
            </Button>
          </li>
        ))}
        {salonSpaces.map((space) => (
          <li key={space.shop_id}>
            <Button
              variant="secondary"
              block
              size="lg"
              onClick={() => onChoose({ kind: 'salon-staff', shopId: space.shop_id })}
            >
              {space.shop_name} ·{' '}
              {space.role === 'stylist'
                ? 'Coiffeur'
                : space.role === 'cashier'
                  ? 'Caisse du salon'
                  : 'Responsable du salon'}
            </Button>
          </li>
        ))}
        <li>
          <Button variant="ghost" block onClick={onJoin}>
            J’ai un code de caissier
          </Button>
        </li>
        {onRestaurantJoin && (
          <li>
            <Button variant="ghost" block onClick={onRestaurantJoin}>
              J’ai un code d’employé de restaurant
            </Button>
          </li>
        )}
        {onSalonJoin && (
          <li>
            <Button variant="ghost" block onClick={onSalonJoin}>
              J’ai un code d’accès à un salon
            </Button>
          </li>
        )}
        <li>
          <Button variant="ghost" block onClick={onSignOut}>
            Se déconnecter
          </Button>
        </li>
      </ul>
    </AuthPage>
  )
}
