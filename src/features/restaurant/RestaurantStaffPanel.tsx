import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { Button, Notice, PageHead, Sheet } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import type { Tables } from '../../lib/database.types'
import { RestaurantStaffAudit } from './RestaurantStaffAudit'

type Member = Tables<'restaurant_staff_members'>
type Pending = { id: string; display_name: string; staff_role: string; expires_at: string }
type Role = 'waiter' | 'kitchen' | 'cashier'
const roleNames: Record<Role, string> = {
  waiter: 'Service en salle',
  kitchen: 'Cuisine / préparation',
  cashier: 'Caisse',
}
const roleName = (v: string) => roleNames[v as Role] ?? v

/** Administrator only. Salaries are handled in Personnel, never in login permissions. */
export function RestaurantStaffPanel({ shopId }: { shopId: string }) {
  const [staff, setStaff] = useState<Member[]>([])
  const [pending, setPending] = useState<Pending[]>([])
  const [showForm, setShowForm] = useState(false)
  const [name, setName] = useState('')
  const [role, setRole] = useState<Role>('waiter')
  const [oneTimeCode, setOneTimeCode] = useState('')
  const [busy, setBusy] = useState(false)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')

  const reload = useCallback(async () => {
    const [members, invites] = await Promise.all([
      supabase
        .from('restaurant_staff_members')
        .select('*')
        .eq('shop_id', shopId)
        .order('created_at', { ascending: true })
        .limit(500),
      supabase.rpc('restaurant_staff_pending_invites', { p_shop: shopId }),
    ])
    if (
      members.error ||
      invites.error ||
      (members.data?.length ?? 0) >= 500 ||
      (invites.data?.length ?? 0) >= 500
    )
      throw new Error('Liste du personnel incomplète ou indisponible.')
    setStaff(members.data ?? [])
    setPending(invites.data ?? [])
  }, [shopId])

  useEffect(() => {
    let active = true
    void Promise.all([
      supabase
        .from('restaurant_staff_members')
        .select('*')
        .eq('shop_id', shopId)
        .order('created_at', { ascending: true })
        .limit(500),
      supabase.rpc('restaurant_staff_pending_invites', { p_shop: shopId }),
    ]).then(([members, invites]) => {
      if (!active) return
      setLoading(false)
      if (
        members.error ||
        invites.error ||
        (members.data?.length ?? 0) >= 500 ||
        (invites.data?.length ?? 0) >= 500
      )
        setError('Impossible de vérifier le personnel de ce restaurant.')
      else {
        setStaff(members.data ?? [])
        setPending(invites.data ?? [])
      }
    })
    return () => {
      active = false
    }
  }, [shopId])

  async function createInvite(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    if (busy || name.trim().length < 1 || name.trim().length > 80) return
    setBusy(true)
    setError('')
    setNotice('')
    try {
      const { data, error: fault } = await supabase.rpc('restaurant_staff_create_invite', {
        p_shop: shopId,
        p_name: name.trim(),
        p_role: role,
      })
      if (fault) throw fault
      const code =
        data && typeof data === 'object' && !Array.isArray(data) ? String(data.code ?? '') : ''
      if (!/^[A-F0-9]{32}$/.test(code))
        throw new Error('Code non reçu : vérifiez les invitations avant de recommencer.')
      setOneTimeCode(code)
      setName('')
      setShowForm(false)
      await reload()
      setNotice('Invitation créée. Le code ne pourra pas être affiché une seconde fois.')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Impossible de créer cette invitation.')
    } finally {
      setBusy(false)
    }
  }

  async function disable(member: Member) {
    if (
      busy ||
      !member.active ||
      !window.confirm(`Désactiver l’accès de ${member.display_name} à ce restaurant ?`)
    )
      return
    setBusy(true)
    setError('')
    setNotice('')
    try {
      const { data, error: fault } = await supabase.rpc('restaurant_staff_disable', {
        p_shop: shopId,
        p_member: member.id,
      })
      if (fault || !data) throw fault ?? new Error('Compte déjà désactivé.')
      await reload()
      setNotice('Accès désactivé. Cette personne ne peut plus agir au nom du restaurant.')
    } catch {
      setError('Impossible de désactiver cet accès. Réessayez.')
    } finally {
      setBusy(false)
    }
  }

  async function revoke(invite: Pending) {
    if (busy) return
    setBusy(true)
    setError('')
    try {
      const { error: fault } = await supabase.rpc('restaurant_staff_revoke_invite', {
        p_shop: shopId,
        p_invite: invite.id,
      })
      if (fault) throw fault
      await reload()
      setNotice('Invitation annulée.')
    } catch {
      setError('Impossible d’annuler cette invitation.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="page-stack">
      <PageHead
        title="Accès du personnel"
        sub="Chaque employé se connecte avec son compte. Le service, la cuisine et la caisse ont des droits séparés."
        action={
          <Button onClick={() => setShowForm((v) => !v)}>
            {showForm ? 'Fermer' : 'Inviter un employé'}
          </Button>
        }
      />
      <Notice tone="calm">
        <p>
          Les comptes de connexion sont distincts des fiches salariales. Seul le propriétaire peut
          créer ou désactiver les accès et consulter l’historique nominatif complet.
        </p>
      </Notice>
      {error && (
        <Notice tone="danger">
          <p>{error}</p>
        </Notice>
      )}
      {notice && (
        <Notice tone="success">
          <p>{notice}</p>
        </Notice>
      )}
      {oneTimeCode && (
        <Sheet>
          <h2 className="section-title">Code d’invitation personnel</h2>
          <p>
            <strong>{oneTimeCode}</strong>
          </p>
          <p className="muted">
            Utilisable une seule fois, pendant 48 heures. Transmettez-le à la personne concernée,
            puis fermez cette fenêtre. Ne le publiez pas.
          </p>
          <div className="row-actions">
            <Button onClick={() => void navigator.clipboard?.writeText(oneTimeCode)}>
              Copier le code
            </Button>
            <Button onClick={() => setOneTimeCode('')}>J’ai noté le code</Button>
          </div>
        </Sheet>
      )}
      {showForm && (
        <Sheet>
          <form className="form-grid" onSubmit={(e) => void createInvite(e)}>
            <label>
              Prénom ou nom professionnel
              <input
                required
                maxLength={80}
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </label>
            <label>
              Fonction
              <select value={role} onChange={(e) => setRole(e.target.value as Role)}>
                {Object.entries(roleNames).map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
            </label>
            <Button variant="primary" type="submit" busy={busy}>
              Générer l’invitation
            </Button>
          </form>
        </Sheet>
      )}
      <Sheet aria-label="Accès autorisés">
        <h2 className="section-title">Comptes du restaurant</h2>
        {loading ? (
          <p>Vérification des comptes…</p>
        ) : staff.length === 0 ? (
          <p className="muted">Aucun employé connecté à ce restaurant.</p>
        ) : (
          <ul className="team-invites">
            {staff.map((member) => (
              <li key={member.id}>
                <div>
                  <strong>{member.display_name}</strong>
                  <p className="muted">
                    {roleName(member.staff_role)} · {member.active ? 'Actif' : 'Accès désactivé'}
                  </p>
                </div>
                {member.active && (
                  <Button disabled={busy} onClick={() => void disable(member)}>
                    Désactiver
                  </Button>
                )}
              </li>
            ))}
          </ul>
        )}
      </Sheet>
      <Sheet aria-label="Invitations en attente">
        <h2 className="section-title">Invitations en attente</h2>
        {pending.length === 0 ? (
          <p className="muted">Aucune invitation en attente.</p>
        ) : (
          <ul className="team-invites">
            {pending.map((invite) => (
              <li key={invite.id}>
                <div>
                  <strong>{invite.display_name}</strong>
                  <p className="muted">
                    {roleName(invite.staff_role)} · jusqu’au{' '}
                    {new Date(invite.expires_at).toLocaleDateString('fr-FR')}
                  </p>
                </div>
                <Button disabled={busy} onClick={() => void revoke(invite)}>
                  Annuler
                </Button>
              </li>
            ))}
          </ul>
        )}
      </Sheet>
      <RestaurantStaffAudit shopId={shopId} />
  </div>
  )
}
