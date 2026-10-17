import { Button } from '../../components/ui'
import type { MemberShop } from '../../lib/team'
import type { Shop } from '../../lib/types'
import { AuthPage } from '../auth/AuthPage'

/** Which space to open when the account owns a shop AND works as a cashier elsewhere. */
export type SpaceChoice = { kind: 'owner' } | { kind: 'cashier'; shopId: string }

/** « Où travaillez-vous aujourd’hui ? » : the owned shop, then each cashier membership. */
export function SpaceChooser({
  shop,
  memberships,
  onChoose,
  onJoin,
  onSignOut,
}: {
  shop: Shop | null
  memberships: MemberShop[]
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
        <li>
          <Button variant="ghost" block onClick={onJoin}>
            J’ai un code de caissier
          </Button>
        </li>
        <li>
          <Button variant="ghost" block onClick={onSignOut}>
            Se déconnecter
          </Button>
        </li>
      </ul>
    </AuthPage>
  )
}
