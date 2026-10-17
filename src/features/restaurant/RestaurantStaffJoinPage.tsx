import { useState, type FormEvent } from 'react'
import { Button, Field, Input, Notice } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { AuthPage } from '../auth/AuthPage'

export function RestaurantStaffJoinPage({
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
      setMessage('Le code du restaurant doit contenir 32 caractères.')
      return
    }
    setBusy(true)
    setMessage('')
    try {
      const { data, error } = await supabase.rpc('restaurant_staff_join', { p_code: code })
      if (error) throw error
      const result = data && typeof data === 'object' && !Array.isArray(data) ? data : null
      if (result?.ok === true && typeof result.shopId === 'string') {
        onJoined(result.shopId)
        return
      }
      setMessage(result?.reason === 'locked'
        ? 'Trop de codes incorrects. Réessayez dans quinze minutes.'
        : 'Code invalide, expiré ou déjà utilisé. Demandez une nouvelle invitation.')
    } catch {
      setMessage('Connexion impossible. Vérifiez votre réseau puis réessayez.')
    } finally {
      setBusy(false)
    }
  }
  return <AuthPage title="Rejoindre un restaurant"
    lead="Utilisez votre propre compte COVI et le code donné par le propriétaire.">
    <form className="auth__form" onSubmit={e=>void join(e)}>
      <Field label="Code personnel d’invitation">
        {control=><Input {...control}
          value={code}
          autoComplete="off"
          autoCapitalize="characters"
          spellCheck={false}
          maxLength={32}
          placeholder="Code de 32 caractères"
          onChange={e=>setCode(e.target.value.toUpperCase().replace(/[^A-F0-9]/g,''))}
        />}
      </Field>
      {message && <Notice tone="danger"><p>{message}</p></Notice>}
      <Button variant="primary" type="submit" busy={busy} block>
        Rejoindre mon restaurant
      </Button>
      <Button variant="ghost" onClick={onBack} block>Retour</Button>
    </form>
  </AuthPage>
}
