import { useEffect, useId, useState } from 'react'
import { Button, Dialog, Notice } from '../../components/ui'
import {
  closeTillSession,
  listShopMembers,
  openTillSession,
  pinResultMessage,
  teamErrorMessage,
  type TeamMember,
} from '../../lib/team'
import { clearTillSession, setTillSession } from '../../lib/tillSession'
import { PinPad } from './PinPad'
import { useTillSession } from './useTillSession'

/**
 * Shared counter device signed in as the OWNER: « Caissier : Awa · Changer ». Picking a cashier
 * asks for THEIR PIN (open_till_session); the sales then go in their name, within their maximum
 * discount. « Vous (responsable) » closes the till session.
 */
export function TillSwitch({ shopId }: { shopId: string }) {
  const session = useTillSession(shopId)
  const [open, setOpen] = useState(false)
  const [members, setMembers] = useState<TeamMember[] | null>(null)
  const [loadError, setLoadError] = useState('')
  const [picked, setPicked] = useState<TeamMember | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const titleId = useId()

  useEffect(() => {
    if (!open) return
    let active = true
    listShopMembers(shopId).then(
      (rows) => {
        if (!active) return
        setMembers(rows.filter((m) => m.active))
        setLoadError('')
      },
      (e) => active && setLoadError(teamErrorMessage(e)),
    )
    return () => {
      active = false
    }
  }, [open, shopId])

  const close = () => {
    setOpen(false)
    setPicked(null)
    setError('')
  }

  const backToOwner = async () => {
    const previous = session
    clearTillSession()
    close()
    if (previous) await closeTillSession(shopId, previous.token).catch(() => false)
  }

  const unlock = async (member: TeamMember, pin: string) => {
    setBusy(true)
    setError('')
    try {
      const result = await openTillSession(shopId, member.id, pin)
      if ('refused' in result) return setError(pinResultMessage(result.refused))
      const previous = session
      setTillSession(result.session)
      close()
      if (previous) await closeTillSession(shopId, previous.token).catch(() => false)
    } catch (e) {
      setError(teamErrorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="till-switch">
      <p className="till-switch__who">
        Caissier : <b>{session ? session.displayName : 'Vous (responsable)'}</b>
        {session && session.maxDiscountPct > 0 && (
          <span className="muted"> · remise max {session.maxDiscountPct} %</span>
        )}
      </p>
      <Button variant="secondary" onClick={() => setOpen(true)} aria-haspopup="dialog">
        Changer
      </Button>
      <Dialog open={open} onClose={close} labelledBy={titleId} sheet>
        <div className="dialog__body till-switch__dialog">
          {picked ? (
            <>
              <h2 className="visually-hidden" id={titleId}>
                Changer de caissier
              </h2>
              <PinPad
                title={`Code PIN de ${picked.display_name}`}
                hint={`${picked.display_name} tape son code. Vous ne le voyez pas.`}
                error={error}
                busy={busy}
                submitLabel="Ouvrir sa caisse"
                onSubmit={(pin) => void unlock(picked, pin)}
              />
              <Button variant="ghost" onClick={() => setPicked(null)}>
                Choisir quelqu’un d’autre
              </Button>
            </>
          ) : (
            <>
              <h2 className="dialog__title" id={titleId}>
                Qui tient la caisse ?
              </h2>
              {loadError && (
                <Notice tone="danger">
                  <p>{loadError}</p>
                </Notice>
              )}
              <ul className="till-switch__list">
                <li>
                  <Button variant="secondary" size="lg" block onClick={() => void backToOwner()}>
                    Vous (responsable)
                  </Button>
                </li>
                {members === null && !loadError && <li className="muted">Chargement…</li>}
                {members?.map((m) => (
                  <li key={m.id}>
                    <Button
                      variant="secondary"
                      size="lg"
                      block
                      disabled={!m.pin_set}
                      onClick={() => {
                        setError('')
                        setPicked(m)
                      }}
                    >
                      {m.pin_set ? m.display_name : `${m.display_name} (code PIN à choisir)`}
                    </Button>
                  </li>
                ))}
                {members?.length === 0 && (
                  <li className="muted">
                    Pas encore de caissier. Invitez-en un dans Ma boutique, rubrique Équipe.
                  </li>
                )}
              </ul>
            </>
          )}
        </div>
      </Dialog>
    </div>
  )
}
