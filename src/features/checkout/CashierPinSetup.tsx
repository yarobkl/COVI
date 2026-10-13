import { useState, type FormEvent } from 'react'
import { Button, Field, Input, Notice, Sheet } from '../../components/ui'
import { setPersonalCashierPin } from '../../lib/cashierAccounts'

/** Does not store or display the personal code outside the transient form. */
export function CashierPinSetup({
  shopId,
  hasPin,
  onSaved,
}: {
  shopId: string
  hasPin: boolean
  onSaved: () => void
}) {
  const [oldPin, setOldPin] = useState('')
  const [pin, setPin] = useState('')
  const [check, setCheck] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  async function save(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setError('')
    if (!/^[0-9]{6,8}$/.test(pin) || pin !== check) {
      setError('Choisissez 6 à 8 chiffres et confirmez exactement le même code.')
      return
    }
    setBusy(true)
    try {
      await setPersonalCashierPin(shopId,pin,hasPin ? oldPin : undefined)
      setPin('')
      setCheck('')
      setOldPin('')
      onSaved()
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Enregistrement refusé.')
    } finally {
      setBusy(false)
    }
  }
  return (
    <Sheet>
      <h3>Mon code personnel de caisse</h3>
      <p>Ce code protège votre validation des paiements. Ne le partagez pas.</p>
      <form onSubmit={(event) => { void save(event) }}>
        {hasPin && (
          <Field label="Code actuel">
            {(props) => <Input {...props} type="password" inputMode="numeric"
              pattern="[0-9]{6,8}" autoComplete="off" required value={oldPin}
              onChange={(e) => setOldPin(e.target.value)} />}
          </Field>
        )}
        <Field label="Nouveau code (6 à 8 chiffres)">
          {(props) => <Input {...props} type="password" inputMode="numeric"
            pattern="[0-9]{6,8}" autoComplete="new-password" required value={pin}
            onChange={(e) => setPin(e.target.value)} />}
        </Field>
        <Field label="Confirmer le nouveau code">
          {(props) => <Input {...props} type="password" inputMode="numeric"
            pattern="[0-9]{6,8}" autoComplete="new-password" required value={check}
            onChange={(e) => setCheck(e.target.value)} />}
        </Field>
        {error && <Notice tone="danger"><p>{error}</p></Notice>}
        <Button type="submit" variant="primary" busy={busy}>
          {hasPin ? 'Modifier mon code' : 'Activer mon code'}
        </Button>
      </form>
    </Sheet>
  )
}
