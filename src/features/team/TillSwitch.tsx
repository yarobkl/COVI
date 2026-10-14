import { useEffect, useId, useState } from 'react'
import { Button, Dialog, Notice } from '../../components/ui'
import { enterCounterMode } from '../../lib/counterMode'
import {
  listShopMembers,
  openTillSession,
  ownerPinStatus,
  pinResultMessage,
  teamErrorMessage,
  type TeamMember,
} from '../../lib/team'
import { setTillSession } from '../../lib/tillSession'
import { OwnerPinSetup } from './OwnerPinScreens'
import { PinPad } from './PinPad'

type Step = 'loading' | 'owner-pin' | 'list'

/**
 * Shared counter device signed in as the OWNER: « Caissier : Vous (responsable) · Changer ».
 * The owner first chooses their own code (once), asked later to leave the counter. Picking a
 * cashier asks for THEIR PIN (open_till_session); the device then switches to counter mode
 * (CounterGate): sales in the cashier's name, within their maximum discount, and the owner's
 * pages closed until the owner's code.
 */
export function TillSwitch({ shopId }: { shopId: string }) {
  const [open, setOpen] = useState(false)
  const [step, setStep] = useState<Step>('loading')
  const [members, setMembers] = useState<TeamMember[] | null>(null)
  const [loadError, setLoadError] = useState('')
  const [picked, setPicked] = useState<TeamMember | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const titleId = useId()

  useEffect(() => {
    if (!open) return
    let active = true
    ownerPinStatus(shopId).then(
      (status) => active && setStep(status.pin_set ? 'list' : 'owner-pin'),
      (e) => {
        if (!active) return
        setLoadError(teamErrorMessage(e))
        setStep('list')
      },
    )
    listShopMembers(shopId).then(
      (rows) => {
        if (!active) return
        setMembers(rows.filter((m) => m.active))
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
    setLoadError('')
    setStep('loading')
  }

  const unlock = async (member: TeamMember, pin: string) => {
    setBusy(true)
    setError('')
    try {
      const result = await openTillSession(shopId, member.id, pin)
      if ('refused' in result) return setError(pinResultMessage(result.refused))
      setTillSession(result.session)
      enterCounterMode(shopId)
      close()
    } catch (e) {
      // The owner's code was erased meanwhile (another device): choose it again.
      if (/owner pin required/i.test(String((e as { message?: unknown })?.message ?? ''))) {
        setPicked(null)
        setStep('owner-pin')
        return
      }
      setError(teamErrorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="till-switch">
      <p className="till-switch__who">
        Caissier : <b>Vous (responsable)</b>
      </p>
      <Button variant="secondary" onClick={() => setOpen(true)} aria-haspopup="dialog">
        Changer
      </Button>
      <Dialog open={open} onClose={close} labelledBy={titleId} sheet>
        <div className="dialog__body till-switch__dialog">
          {step === 'loading' ? (
            <>
              <h2 className="dialog__title" id={titleId}>
                Qui tient la caisse ?
              </h2>
              <p className="muted">Chargement…</p>
            </>
          ) : step === 'owner-pin' ? (
            <>
              <h2 className="visually-hidden" id={titleId}>
                Votre code de responsable
              </h2>
              <OwnerPinSetup shopId={shopId} onDone={() => setStep('list')} onCancel={close} />
            </>
          ) : picked ? (
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
              <p className="muted">
                L’appareil passe en mode comptoir : seulement Vendre et les ventes du caissier.
                Votre code de responsable sera demandé pour revenir.
              </p>
              {loadError && (
                <Notice tone="danger">
                  <p>{loadError}</p>
                </Notice>
              )}
              <ul className="till-switch__list">
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
