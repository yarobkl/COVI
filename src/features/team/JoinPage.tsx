import { useState, type FormEvent } from 'react'
import { Button, Field, Input, Notice } from '../../components/ui'
import { redeemMemberInvite, teamErrorMessage, type RedeemResult } from '../../lib/team'
import { AuthPage } from '../auth/AuthPage'

/**
 * « Rejoindre une boutique » : a signed-in user types the code given by the owner. The server
 * checks it (one use, 48 h, 5 wrong codes → 15 minutes) and never says why a code is refused.
 */
export function JoinPage({
  onJoined,
  onBack,
}: {
  onJoined: (result: Extract<RedeemResult, { status: 'joined' }>) => void
  onBack: () => void
}) {
  const [code, setCode] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const submit = async (e: FormEvent) => {
    e.preventDefault()
    if (code.replace(/[^A-Za-z0-9]/g, '').length < 12)
      return setError('Le code compte 12 lettres et chiffres, par exemple ABCD-EFGH-JKMN.')
    setBusy(true)
    setError('')
    try {
      const result = await redeemMemberInvite(code)
      if (result.status === 'joined') onJoined(result)
      else if (result.status === 'locked') setError('Trop d’essais. Réessayez dans 15 minutes.')
      else
        setError(
          'Ce code ne marche pas : il est faux, déjà utilisé, annulé ou trop ancien. Demandez un nouveau code au responsable.',
        )
    } catch (err) {
      setError(teamErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }
  return (
    <AuthPage
      title="Rejoindre une boutique"
      lead="Tapez le code que le responsable de la boutique vous a donné."
    >
      <form className="auth__form" onSubmit={(e) => void submit(e)}>
        <Field label="Code d’invitation">
          {(control) => (
            <Input
              {...control}
              value={code}
              autoComplete="off"
              autoCapitalize="characters"
              spellCheck={false}
              placeholder="ABCD-EFGH-JKMN"
              onChange={(e) => setCode(e.target.value.toUpperCase())}
            />
          )}
        </Field>
        {error && (
          <Notice tone="danger">
            <p>{error}</p>
          </Notice>
        )}
        <Button variant="primary" size="lg" block type="submit" busy={busy}>
          Rejoindre la boutique
        </Button>
        <Button variant="ghost" block onClick={onBack}>
          Retour
        </Button>
      </form>
    </AuthPage>
  )
}
