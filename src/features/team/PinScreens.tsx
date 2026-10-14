import { useState } from 'react'
import { Button } from '../../components/ui'
import {
  pinProblem,
  pinResultMessage,
  setMyPin,
  teamErrorMessage,
  verifyMyPin,
} from '../../lib/team'
import { PinPad } from './PinPad'

/**
 * Till locked (opening, inactivity): the cashier types THEIR PIN, checked by the server
 * (verify_my_pin, 5 errors → 15 minutes). `onNotSet` when the owner reset the PIN meanwhile.
 */
export function PinLockScreen({
  shopId,
  shopName,
  cashierName,
  onUnlocked,
  onNotSet,
  onSignOut,
}: {
  shopId: string
  shopName: string
  cashierName: string
  onUnlocked: () => void
  onNotSet: () => void
  onSignOut: () => void
}) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const check = async (pin: string) => {
    setBusy(true)
    setError('')
    try {
      const result = await verifyMyPin(shopId, pin)
      if (result.status === 'ok') onUnlocked()
      else if (result.status === 'not_set') onNotSet()
      else setError(pinResultMessage(result))
    } catch (e) {
      setError(teamErrorMessage(e))
    } finally {
      setBusy(false)
    }
  }
  return (
    <div className="pin-screen">
      <p className="pin-screen__shop">{shopName}</p>
      <PinPad
        title={`Bonjour ${cashierName}`}
        hint="Tapez votre code PIN pour ouvrir la caisse."
        error={error}
        busy={busy}
        submitLabel="Ouvrir la caisse"
        onSubmit={(pin) => void check(pin)}
      />
      <Button variant="ghost" onClick={onSignOut}>
        Ce n’est pas moi : se déconnecter
      </Button>
    </div>
  )
}

type Step = 'current' | 'new' | 'confirm'

/**
 * « Choisissez votre code PIN » : first time, after a reset by the owner (no current PIN), or a
 * change asked by the cashier (`askCurrent`). Typed twice; trivial codes are refused here and by
 * the server.
 */
export function PinSetupScreen({
  shopId,
  shopName,
  askCurrent = false,
  reset = false,
  onDone,
  onCancel,
}: {
  shopId: string
  shopName: string
  askCurrent?: boolean
  /** The owner reset the PIN: say why a new one is needed. */
  reset?: boolean
  onDone: () => void
  onCancel?: () => void
}) {
  const [step, setStep] = useState<Step>(askCurrent ? 'current' : 'new')
  const [current, setCurrent] = useState('')
  const [first, setFirst] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const save = async (pin: string) => {
    if (pin !== first) {
      setError('Les deux codes ne sont pas pareils. Recommencez.')
      setFirst('')
      setStep('new')
      return
    }
    setBusy(true)
    setError('')
    try {
      const result = await setMyPin(shopId, pin, askCurrent ? current : undefined)
      if (result.status === 'ok') onDone()
      else {
        setError(pinResultMessage(result))
        setFirst('')
        setStep(askCurrent ? 'current' : 'new')
      }
    } catch (e) {
      setError(teamErrorMessage(e))
      setFirst('')
      setStep('new')
    } finally {
      setBusy(false)
    }
  }

  const titles: Record<Step, string> = {
    current: 'Votre code PIN actuel',
    new: 'Choisissez votre code PIN',
    confirm: 'Tapez-le une deuxième fois',
  }
  const hints: Record<Step, string> = {
    current: 'Pour changer de code, tapez d’abord celui que vous utilisez.',
    new: reset
      ? 'Le responsable a effacé votre ancien code. Choisissez-en un nouveau : 4 à 6 chiffres, connus de vous seul.'
      : '4 à 6 chiffres, connus de vous seul. Il ouvre votre caisse et signe vos ventes.',
    confirm: 'Pour être sûr de ne pas vous tromper.',
  }

  return (
    <div className="pin-screen">
      <p className="pin-screen__shop">{shopName}</p>
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
