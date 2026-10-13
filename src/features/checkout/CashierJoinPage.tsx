import { useState, type FormEvent } from 'react'
import { Button, Field, Input, Notice, Sheet } from '../../components/ui'
import { redeemCashierInvite } from '../../lib/cashierAccounts'

export function CashierJoinPage({
  onJoined,
  onCreateShop,
  signOut,
}: {
  onJoined: () => void
  onCreateShop: () => void
  signOut: () => Promise<void>
}) {
  const [code, setCode] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  async function join(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setError('')
    setBusy(true)
    try {
      await redeemCashierInvite(code.trim())
      onJoined()
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Invitation refusée.')
    } finally {
      setBusy(false)
    }
  }
  return (
    <main className="checkout-guest seyes margin-rule">
      <Sheet>
        <p className="hand">COVI — Le cahier de la boutique</p>
        <h1>Rejoindre une caisse</h1>
        <p>Vous avez reçu un code du propriétaire ? Saisissez-le pour rejoindre sa boutique avec votre propre compte.</p>
        <form onSubmit={(e) => { void join(e) }}>
          <Field label="Code d'invitation personnel">
            {(props) => <Input {...props} required autoComplete="off" value={code}
              onChange={(e) => setCode(e.target.value)} placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" />}
          </Field>
          {error && <Notice tone="danger"><p>{error}</p></Notice>}
          <Button variant="primary" type="submit" busy={busy}>Rejoindre la caisse</Button>
        </form>
        <p>Vous n'êtes pas caissier et vous ouvrez votre propre commerce ?</p>
        <Button variant="secondary" onClick={onCreateShop}>Créer ma boutique</Button>
        <Button variant="secondary" onClick={() => { void signOut() }}>Changer de compte</Button>
      </Sheet>
    </main>
  )
}
