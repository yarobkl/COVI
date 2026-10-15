import { useCallback, useEffect, useId, useState, type FormEvent } from 'react'
import { Button, Dialog, Field, Input, Notice } from '../../components/ui'
import {
  createMemberInvite,
  listMemberInvites,
  listShopMembers,
  ownerResetMemberPin,
  revokeMemberInvite,
  setMemberActive,
  setMemberPermissions,
  teamErrorMessage,
  type CreatedInvite,
  type PendingInvite,
  type TeamMember,
} from '../../lib/team'
import { inviteMessage, inviteTime as time } from '../../lib/teamRules'

function InviteForm({
  shopId,
  onCreated,
}: {
  shopId: string
  onCreated: (i: CreatedInvite) => void
}) {
  const [name, setName] = useState('')
  const [viewAll, setViewAll] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const submit = async (e: FormEvent) => {
    e.preventDefault()
    if (!name.trim()) return setError('Indiquez le prénom du caissier.')
    setBusy(true)
    setError('')
    try {
      onCreated(await createMemberInvite(shopId, name.trim(), viewAll, 0))
      setName('')
      setViewAll(false)
    } catch (err) {
      setError(teamErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }
  return (
    <form className="team-invite" onSubmit={(e) => void submit(e)}>
      <Field label="Prénom du caissier">
        {(control) => (
          <Input
            {...control}
            value={name}
            maxLength={60}
            autoComplete="off"
            onChange={(e) => setName(e.target.value)}
          />
        )}
      </Field>
      <label className="team-check">
        <input type="checkbox" checked={viewAll} onChange={(e) => setViewAll(e.target.checked)} />
        Voit toutes les ventes de la boutique
      </label>
      {error && (
        <Notice tone="danger">
          <p>{error}</p>
        </Notice>
      )}
      <Button variant="primary" size="lg" type="submit" busy={busy}>
        Créer un code d’invitation
      </Button>
    </form>
  )
}

function NewInvite({
  invite,
  shopName,
  onClose,
}: {
  invite: CreatedInvite
  shopName: string
  onClose: () => void
}) {
  const [copied, setCopied] = useState(false)
  const text = inviteMessage(shopName, invite)
  return (
    <div className="team-code" role="status">
      <p>
        Code pour <b>{invite.display_name}</b> — notez-le maintenant, il ne s’affichera plus :
      </p>
      <p className="team-code__value">{invite.code}</p>
      <p className="muted">
        Une seule utilisation, jusqu’à {time(invite.expires_at)}. Donnez-le de vive voix ou par
        message à {invite.display_name} seulement.
      </p>
      <div className="team-code__actions">
        <Button
          variant="secondary"
          onClick={() =>
            void navigator.clipboard?.writeText(text).then(
              () => setCopied(true),
              () => setCopied(false),
            )
          }
        >
          {copied ? 'Message copié' : 'Copier le message'}
        </Button>
        <a
          className="btn btn--secondary"
          href={`https://wa.me/?text=${encodeURIComponent(text)}`}
          target="_blank"
          rel="noreferrer"
        >
          Envoyer par WhatsApp
        </a>
        <Button variant="ghost" onClick={onClose}>
          J’ai noté le code
        </Button>
      </div>
    </div>
  )
}

function MemberRow({
  member,
  onChanged,
  onError,
}: {
  member: TeamMember
  onChanged: () => void
  onError: (message: string) => void
}) {
  const [busy, setBusy] = useState<string | null>(null)
  const [confirmReset, setConfirmReset] = useState(false)
  const titleId = useId()
  const run = async (what: string, action: () => Promise<unknown>) => {
    setBusy(what)
    try {
      await action()
      onChanged()
    } catch (e) {
      onError(teamErrorMessage(e))
    } finally {
      setBusy(null)
    }
  }
  const pinState = member.pin_locked_until
    ? `Code PIN bloqué jusqu’à ${new Date(member.pin_locked_until).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}`
    : member.pin_set
      ? 'Code PIN choisi'
      : member.pin_must_change
        ? 'Doit choisir un nouveau code PIN'
        : 'N’a pas encore choisi son code PIN'
  return (
    <li className={member.active ? 'team-member' : 'team-member team-member--off'}>
      <div className="team-member__head">
        <p className="team-member__name">{member.display_name}</p>
        <p className="muted">
          {member.active ? 'Actif' : 'Désactivé'} · {pinState}
        </p>
      </div>
      {member.active && (
        <div className="team-member__rights">
          <label className="team-check">
            <input
              type="checkbox"
              checked={member.can_view_shop_sales}
              disabled={busy !== null}
              onChange={(e) =>
                void run('view', () =>
                  setMemberPermissions(member.id, e.target.checked, member.max_discount_pct),
                )
              }
            />
            Voit toutes les ventes
          </label>
        </div>
      )}
      <div className="team-member__actions">
        {member.active && (
          <Button variant="secondary" onClick={() => setConfirmReset(true)}>
            Réinitialiser le code PIN
          </Button>
        )}
        <Button
          variant={member.active ? 'danger' : 'secondary'}
          busy={busy === 'active'}
          onClick={() => void run('active', () => setMemberActive(member.id, !member.active))}
        >
          {member.active ? 'Désactiver' : 'Réactiver'}
        </Button>
      </div>
      <Dialog open={confirmReset} onClose={() => setConfirmReset(false)} labelledBy={titleId}>
        <div className="dialog__body">
          <h2 className="dialog__title" id={titleId}>
            Réinitialiser le code PIN de {member.display_name} ?
          </h2>
          <p className="dialog__text">
            Son code actuel ne marchera plus. À sa prochaine ouverture de COVI,{' '}
            {member.display_name} choisira un nouveau code, connu de lui seul. Vous ne le verrez
            pas.
          </p>
          <div className="dialog__actions">
            <Button variant="secondary" onClick={() => setConfirmReset(false)} autoFocus>
              Annuler
            </Button>
            <Button
              variant="danger"
              solid
              busy={busy === 'reset'}
              onClick={() =>
                void run('reset', () => ownerResetMemberPin(member.id)).then(() =>
                  setConfirmReset(false),
                )
              }
            >
              Réinitialiser
            </Button>
          </div>
        </div>
      </Dialog>
    </li>
  )
}

/**
 * « Équipe » (owner, in Ma boutique): invite a cashier with a one-time code, choose
 * whether they see every sale, deactivate them, reset their PIN.
 */
export function TeamPanel({ shopId, shopName }: { shopId: string; shopName: string }) {
  const [members, setMembers] = useState<TeamMember[] | null>(null)
  const [invites, setInvites] = useState<PendingInvite[]>([])
  const [created, setCreated] = useState<CreatedInvite | null>(null)
  const [error, setError] = useState('')
  const titleId = useId()

  const reload = useCallback(() => {
    Promise.all([listShopMembers(shopId), listMemberInvites(shopId)]).then(
      ([m, i]) => {
        setMembers(m)
        setInvites(i)
        setError('')
      },
      (e) => setError(teamErrorMessage(e)),
    )
  }, [shopId])

  useEffect(() => {
    reload()
  }, [reload])

  return (
    <section className="card team" aria-labelledby={titleId}>
      <h2 id={titleId}>Équipe</h2>
      <p className="muted">
        Chaque caissier a son propre compte et son propre code PIN. Ses ventes portent son nom. Il
        ne voit ni vos arrivages, ni vos charges, ni vos bénéfices.
      </p>
      {error && (
        <Notice tone="danger">
          <p>{error}</p>
        </Notice>
      )}

      {members === null && !error && <p>Chargement de l’équipe…</p>}
      {members && members.length > 0 && (
        <ul className="team-members" aria-label="Caissiers">
          {members.map((m) => (
            <MemberRow
              key={`${m.id}:${m.updated_at}:${m.pin_set}`}
              member={m}
              onChanged={reload}
              onError={setError}
            />
          ))}
        </ul>
      )}
      {members && members.length === 0 && <p>Pas encore de caissier.</p>}

      {invites.length > 0 && (
        <>
          <h3>Invitations en attente</h3>
          <ul className="team-invites">
            {invites.map((i) => (
              <li key={i.id}>
                <span>
                  {i.display_name} · valable jusqu’à {time(i.expires_at)}
                </span>
                <Button
                  variant="ghost"
                  onClick={() =>
                    void revokeMemberInvite(i.id).then(reload, (e) => setError(teamErrorMessage(e)))
                  }
                >
                  Annuler l’invitation
                </Button>
              </li>
            ))}
          </ul>
        </>
      )}

      <p className="muted">
        Le compte de gestion est partagé. Chaque caissier utilise son propre PIN pour vendre.
      </p>

      <h3>Inviter un caissier</h3>
      {created ? (
        <NewInvite invite={created} shopName={shopName} onClose={() => setCreated(null)} />
      ) : (
        <InviteForm
          shopId={shopId}
          onCreated={(invite) => {
            setCreated(invite)
            reload()
          }}
        />
      )}
    </section>
  )
}
