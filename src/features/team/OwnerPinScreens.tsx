import { useState } from 'react'
import { Button } from '../../components/ui'
import {
  leaveCounterMode,
  ownerPinResultMessage,
  pinProblem,
  setOwnerPin,
  teamErrorMessage,
} from '../../lib/team'
import { PinPad } from './PinPad'

type Step = 'current' | 'new' | 'confirm'

/**
 * « Choisissez votre code de responsable » : asked before the first « Changer de caissier », or
 * to change it (`askCurrent`). Typed twice; trivial codes are refused here and by the server.
 */
export function OwnerPinSetup({
  shopId,
  askCurrent = false,
  onDone,
  onCancel,
}: {
  shopId: string
  askCurrent?: boolean
  onDone: () => void
  onCancel?: () => void
}) {
  const [step, setStep] = useState<Step>(askCurrent ? 'current' : 'new')
  const [current, setCurrent] = useState('')
  const [first, setFirst] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const restart = (message: string) => {
    setError(message)
    setFirst('')
    setStep(askCurrent ? 'current' : 'new')
  }

  const save = async (pin: string) => {
    if (pin !== first) return restart('Les deux codes ne sont pas pareils. Recommencez.')
    setBusy(true)
    setError('')
    try {
      const result = await setOwnerPin(shopId, pin, askCurrent ? current : undefined)
      if (result.status === 'ok') onDone()
      else restart(ownerPinResultMessage(result))
    } catch (e) {
      restart(teamErrorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  const titles: Record<Step, string> = {
    current: 'Votre code de responsable actuel',
    new: 'Choisissez votre code de responsable',
    confirm: 'Tapez-le une deuxième fois',
  }
  const hints: Record<Step, string> = {
    current: 'Pour changer de code, tapez d’abord celui que vous utilisez.',
    new: 'Il sera demandé pour quitter le comptoir et revenir à toute l’application. 4 à 6 chiffres, connus de vous seul : ne le donnez à aucun caissier.',
    confirm: 'Pour être sûr de ne pas vous tromper.',
  }

  return (
    <div className="owner-pin">
      <PinPad
        key={step}
        title={titles[step]}
        hint={hints[step]}
        error={error}
        busy={busy}
        submitLabel={step === 'confirm' ? 'Enregistrer mon code' : 'Continuer'}
        onSubmit={(pin) => {
          if (step === 'current') {
            setCurrent(pin)
            setError('')
            setStep('new')
          } else if (step === 'new') {
            const problem = pinProblem(pin)
            if (problem) return setError(problem)
            setFirst(pin)
            setError('')
            setStep('confirm')
          } else void save(pin)
        }}
      />
      {onCancel && (
        <Button variant="ghost" onClick={onCancel}>
          Annuler
        </Button>
      )}
    </div>
  )
}

/**
 * « Revenir au responsable » : the OWNER's code, checked by the server (leave_counter_mode, 5
 * errors → 15 minutes), which also closes the till session. Only then the full app comes back.
 */
export function OwnerPinPrompt({
  shopId,
  token,
  onLeft,
  onCancel,
  onSignOut,
}: {
  shopId: string
  /** Till session to close once the code is accepted. */
  token?: string
  onLeft: () => void
  onCancel: () => void
  /** Forgotten code: sign out, the account password is asked to come back. */
  onSignOut: () => void
}) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const check = async (pin: string) => {
    setBusy(true)
    setError('')
    try {
      const result = await leaveCounterMode(shopId, pin, token)
      if (result.status === 'ok') onLeft()
      else setError(ownerPinResultMessage(result))
    } catch (e) {
      setError(teamErrorMessage(e))
    } finally {
      setBusy(false)
    }
  }
  return (
    <div className="pin-screen">
      <PinPad
        title="Code du responsable"
        hint="Pour quitter le comptoir et revenir à toute l’application."
        error={error}
        busy={busy}
        submitLabel="Revenir au responsable"
        onSubmit={(pin) => void check(pin)}
      />
      <Button variant="ghost" onClick={onCancel}>
        Rester au comptoir
      </Button>
      <p className="muted pin-screen__help">
        Code oublié ? Déconnectez-vous : le mot de passe du compte sera demandé pour revenir, puis
        choisissez un nouveau code dans Ma boutique, rubrique Équipe.
      </p>
      <Button variant="ghost" onClick={onSignOut}>
        Se déconnecter
      </Button>
    </div>
  )
}
