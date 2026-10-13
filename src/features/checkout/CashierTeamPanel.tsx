import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { Button, Field, Input, Notice, Sheet } from '../../components/ui'
import {
  createCashierInvite, listCashiers, setCashierActive,
  type CashierTeamMember,
} from '../../lib/cashierAccounts'
import { CashierPinSetup } from './CashierPinSetup'

/** Invites grant ONLY cashier checkout access. Never give staff owner settings,
 * product editing, financial dashboards or public-link administration.
 */
export function CashierTeamPanel({ shopId }: { shopId: string }) {
  const [team, setTeam] = useState<CashierTeamMember[]>([])
  const [name, setName] = useState('')
  const [invitation, setInvitation] = useState<{ code: string; expiry: string } | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [ownerPinConfigured, setOwnerPinConfigured] = useState(false)

  const refresh = useCallback(async () => {
    try {
      const list = await listCashiers(shopId)
      setTeam(list)
      const user = (await import('../../lib/supabase')).supabase.auth
      const { data } = await user.getUser()
      setOwnerPinConfigured(list.some(x => x.userId === data.user?.id && x.pinConfigured))
      setError('')
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Équipe indisponible.')
    }
  }, [shopId])

  useEffect(() => { void refresh() }, [refresh])

  async function invite(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setError('')
    setBusy(true)
    try {
      const result = await createCashierInvite(shopId,name)
      setInvitation({ code: result.inviteCode, expiry: result.expiresAt })
      setName('')
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Invitation impossible.')
    } finally {
      setBusy(false)
    }
  }

  async function toggle(row: CashierTeamMember) {
    setError('')
    setBusy(true)
    try {
      await setCashierActive(shopId,row.userId,!row.active)
      await refresh()
      setNotice(row.active ? 'Accès à la caisse désactivé.' : 'Accès à la caisse réactivé.')
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Modification refusée.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <section className="checkout-team">
      <header>
        <h2>Les caissiers de ma boutique</h2>
        <p>Un compte COVI par caissier, un code personnel par personne et un accès limité à cette boutique.</p>
      </header>
      <CashierPinSetup shopId={shopId} hasPin={ownerPinConfigured} onSaved={() => { void refresh(); setNotice('Votre code de caisse est actif.') }} />
      <Sheet>
        <h3>Inviter un caissier</h3>
        <p>Votre employé crée d'abord son compte COVI personnel, puis utilise le code d'invitation depuis l'écran de connexion.</p>
        <form onSubmit={(e) => { void invite(e) }}>
          <Field label="Prénom de votre caissier">
            {(props) => <Input {...props} required maxLength={60} value={name}
              onChange={(e) => setName(e.target.value)} placeholder="Ex. Aminata" />}
          </Field>
          <Button type="submit" disabled={busy} busy={busy} variant="primary">
            Créer une invitation valable 48 h
          </Button>
        </form>
        {invitation && (
          <div role="status">
            <p>Code unique à transmettre uniquement à ce caissier :</p>
            <p className="figures" style={{ overflowWrap: 'anywhere' }}>{invitation.code}</p>
            <Button variant="secondary" onClick={() => {
              void navigator.clipboard.writeText(invitation.code)
            }}>Copier le code</Button>
            <p>Expire le {new Date(invitation.expiry).toLocaleString('fr-FR')}. Il ne peut servir qu'une seule fois.</p>
          </div>
        )}
      </Sheet>
      <Sheet>
        <h3>Équipe de caisse</h3>
        {!team.length && <p>Aucun caissier invité n'a encore rejoint la boutique.</p>}
        {team.map(row => (
          <div key={row.userId} className="checkout-team__member">
            <strong>{row.firstName}</strong>
            <span>{row.active ? ' · Actif' : ' · Désactivé'}</span>
            <span>{row.pinConfigured ? ' · Code actif' : ' · Code non créé'}</span>
            <Button variant="secondary" disabled={busy} onClick={() => { void toggle(row) }}>
              {row.active ? 'Désactiver' : 'Réactiver'}
            </Button>
          </div>
        ))}
        <Button variant="secondary" onClick={() => { void refresh() }}>Actualiser l'équipe</Button>
        {error && <Notice tone="danger"><p>{error}</p></Notice>}
        {notice && <p role="status">{notice}</p>}
      </Sheet>
    </section>
  )
}
