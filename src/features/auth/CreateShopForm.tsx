import { useState, type FormEvent } from 'react'
import { Button, Field, Input, LabelCard, Notice } from '../../components/ui'
import { businessErrorMessage, shopQuotaMessage } from '../../lib/businessErrors'
import { supabase } from '../../lib/supabase'
import type { Shop } from '../../lib/types'
import { AuthPage } from './AuthPage'
import { authError } from './authErrors'

/** Adding a shop to an account that already has one (multi-shop subscription). */
export type AddingShop = {
  /** Shops already on the account: `create_my_shop` returns one of them when the quota is 1. */
  existingIds: readonly string[]
  shopLimit: number | null
  onCancel: () => void
}

/**
 * First sign-in: creates the owner's shop (currency fixed to XAF). With `adding`: another shop
 * for the same account, within the quota of the subscription (checked by `create_my_shop`).
 */
export function CreateShopForm({
  message,
  onMessage,
  onCreated,
  adding,
}: {
  message: string
  onMessage: (message: string) => void
  onCreated: (shop: Shop) => void
  adding?: AddingShop
}) {
  const [name, setName] = useState('')
  const [city, setCity] = useState('')
  const [busy, setBusy] = useState(false)

  async function createShop(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    onMessage('')
    const f = new FormData(e.currentTarget)
    setBusy(true)
    try {
      const { data, error } = await supabase.rpc('create_my_shop', {
        p_name: String(f.get('name')).trim(),
        p_city: String(f.get('city') || '').trim(),
        p_country: String(f.get('country') || 'Congo').trim(),
        p_currency: 'XAF',
      })
      if (error)
        onMessage(businessErrorMessage(error, { shopLimit: adding?.shopLimit }) ?? authError(error))
      // A V1 account (quota 1) gets its existing shop back instead of « Shop quota reached ».
      else if (adding?.existingIds.includes(data.id))
        onMessage(shopQuotaMessage(adding.shopLimit ?? adding.existingIds.length))
      else onCreated(data)
    } finally {
      setBusy(false)
    }
  }

  // The notebook label fills in as the name is typed.
  const preview = (
    <figure className="auth__preview">
      <LabelCard>
        <p className="sommaire__shop-kicker">Cahier de caisse</p>
        <p className="sommaire__shop-name">{name.trim() || 'Votre boutique'}</p>
        <p className="sommaire__shop-place">{city.trim() || 'Votre ville'}</p>
      </LabelCard>
      <figcaption className="hand auth__preview-note">
        votre étiquette, en haut du cahier
      </figcaption>
    </figure>
  )

  return (
    <AuthPage
      title={adding ? 'Ajouter une boutique' : 'Comment s’appelle votre boutique ?'}
      lead={
        adding
          ? 'Elle aura son propre cahier : son stock, ses ventes et ses charges, séparés des autres.'
          : 'Ce nom s’affichera en haut de l’écran. Vous pourrez le changer plus tard.'
      }
      aside={preview}
    >
      <form className="auth__form" onSubmit={createShop}>
        <Field label="Nom de la boutique">
          {(control) => (
            <Input
              {...control}
              name="name"
              required
              placeholder="Ex. Chez Mama Grâce"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          )}
        </Field>
        <Field label="Ville">
          {(control) => (
            <Input
              {...control}
              name="city"
              placeholder="Ex. Brazzaville, Pointe-Noire"
              value={city}
              onChange={(e) => setCity(e.target.value)}
            />
          )}
        </Field>
        <Field label="Pays">
          {(control) => <Input {...control} name="country" defaultValue="Congo" />}
        </Field>
        {message && (
          <Notice tone="danger">
            <p>{message}</p>
          </Notice>
        )}
        <Button variant="primary" size="lg" block type="submit" busy={busy}>
          {adding ? 'Créer cette boutique' : 'Créer ma boutique'}
        </Button>
        {adding && (
          <button type="button" className="btn btn--ghost auth__cancel" onClick={adding.onCancel}>
            Annuler
          </button>
        )}
      </form>
    </AuthPage>
  )
}
