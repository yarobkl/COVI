import { useState, type FormEvent } from 'react'
import { Button, Field, Input, Notice } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import type { Shop } from '../../lib/types'

export function AddEstablishmentForm({
  count,
  onCreated,
  onCancel,
}: {
  count: number
  onCreated: (shop: Shop) => void
  onCancel: () => void
}) {
  const [name, setName] = useState('')
  const [kind, setKind] = useState('boutique')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  async function submit(event: FormEvent) {
    event.preventDefault()
    setBusy(true)
    setMessage('')
    const { data, error } = await supabase.rpc('create_my_shop', {
      p_name: name.trim(),
      p_city: undefined,
      p_country: 'Congo',
      p_currency: 'XAF',
      p_business_kind: kind,
    } as never)
    setBusy(false)
    if (error) {
      setMessage(error.message.includes('Shop quota reached')
        ? 'Vous avez atteint la limite de 3 établissements.'
        : error.message)
      return
    }
    onCreated(data as Shop)
  }
  return (
    <main className="authshell">
      <section className="authcard">
        <h1>Ajouter un établissement</h1>
        <p>Établissement {count + 1} sur 3.</p>
        {message && <Notice tone="danger">{message}</Notice>}
        <form className="auth__form" onSubmit={submit}>
          <Field label="Nom de l’établissement">
            {(control) => <Input {...control} value={name} required minLength={2} onChange={(e) => setName(e.target.value)} />}
          </Field>
          <label>
            <span className="field__label">Activité</span>
            <select value={kind} onChange={(e) => setKind(e.target.value)}>
              <option value="boutique">Boutique</option>
              <option value="restaurant">Restaurant</option>
              <option value="salon">Salon de coiffure</option>
            </select>
          </label>
          <div className="auth__actions">
            <Button type="submit" disabled={busy || count >= 3}>{busy ? 'Création…' : 'Créer l’établissement'}</Button>
            <Button type="button" variant="secondary" onClick={onCancel}>Annuler</Button>
          </div>
        </form>
      </section>
    </main>
  )
}
