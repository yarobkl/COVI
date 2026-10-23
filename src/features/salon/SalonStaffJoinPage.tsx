import { useState, type FormEvent } from 'react'
import { Button, Field, Input, Notice } from '../../components/ui'
import { salonApi, salonErrorMessage } from '../../lib/salon'
import { AuthPage } from '../auth/AuthPage'

/** Un collaborateur rejoint un salon avec le code à usage unique donné par le propriétaire. */
export function SalonStaffJoinPage({
  onJoined,
  onBack,
}: {
  onJoined: (shopId: string) => void
  onBack: () => void
}) {
  const [code, setCode] = useState('')
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')

  async function join(e: FormEvent) {
    e.preventDefault()
    if (!/^[A-F0-9]{32}$/.test(code)) {
      setMessage('Le code du salon contient 32 caractères (chiffres et lettres A à F).')
      return
    }
    setBusy(true)
    setMessage('')
    try {
      const result = await salonApi.join(code)
      if (result.ok && result.shop_id) {
        onJoined(result.shop_id)
        return
      }
      setMessage(
        result.reason === 'locked'
          ? 'Trop de codes incorrects. Réessayez dans quinze minutes.'
          : result.reason === 'already_member'
            ? 'Vous faites déjà partie de ce salon.'
            : 'Code invalide, expiré ou déjà utilisé. Demandez un nouveau code au propriétaire.',
      )
    } catch (e) {
      setMessage(salonErrorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <AuthPage
      title="Rejoindre un salon"
      lead="Utilisez votre propre compte COVI et le code donné par le propriétaire du salon."
    >
      <form className="auth__form" onSubmit={(e) => void join(e)}>
        <Field label="Code d’accès au salon">
          {(control) => (
            <Input
              {...control}
              value={code}
              autoComplete="off"
              autoCapitalize="characters"
              spellCheck={false}
              maxLength={32}
              placeholder="Code de 32 caractères"
              onChange={(e) => setCode(e.target.value.toUpperCase().replace(/[^A-F0-9]/g, ''))}
            />
          )}
        </Field>
        {message && (
          <Notice tone="danger">
            <p>{message}</p>
          </Notice>
        )}
        <Button variant="primary" type="submit" busy={busy} block>
          Rejoindre le salon
        </Button>
        <Button variant="ghost" onClick={onBack} block>
          Retour
        </Button>
      </form>
    </AuthPage>
  )
}
