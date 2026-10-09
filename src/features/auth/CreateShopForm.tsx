import type { FormEvent } from 'react'
import { supabase } from '../../lib/supabase'
import type { Shop } from '../../lib/types'
import { authError } from './authErrors'

/** First sign-in: creates the owner's shop (currency fixed to XAF). */
export function CreateShopForm({
  message,
  onMessage,
  onCreated,
}: {
  message: string
  onMessage: (message: string) => void
  onCreated: (shop: Shop) => void
}) {
  async function createShop(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    onMessage('')
    const f = new FormData(e.currentTarget)
    const { data, error } = await supabase.rpc('create_my_shop', {
      p_name: String(f.get('name')),
      p_city: String(f.get('city') || ''),
      p_country: String(f.get('country') || 'Congo'),
      p_currency: 'XAF',
    })
    if (error) onMessage(authError(error))
    else onCreated(data as Shop)
  }
  return (
    <div className="authshell">
      <form className="authcard" onSubmit={createShop}>
        <div className="authlogo">
          C<span>O</span>VI
        </div>
        <h1>Créons votre commerce</h1>
        <p>Ces informations personnaliseront votre espace COVI.</p>
        <label>
          Nom de la boutique
          <input name="name" required placeholder="Ex. Boutique Élégance" />
        </label>
        <label>
          Ville
          <input name="city" placeholder="Ex. Brazzaville" />
        </label>
        <label>
          Pays
          <input name="country" defaultValue="Congo" />
        </label>
        {message && <p className="authmessage">{message}</p>}
        <button className="primary" type="submit">
          Créer mon commerce
        </button>
      </form>
    </div>
  )
}
