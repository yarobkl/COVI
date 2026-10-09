import { FormEvent, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
type Shop = {
  id: string
  name: string
  city: string | null
  country: string | null
  currency: string
}
export function LiveSettings({
  shopId,
  onShopUpdated,
}: {
  shopId: string
  onShopUpdated: (shop: Shop) => void
}) {
  const [shop, setShop] = useState<Shop | null>(null),
    [msg, setMsg] = useState('')
  async function load() {
    const { data, error } = await supabase
      .from('shops')
      .select('id,name,city,country,currency')
      .eq('id', shopId)
      .single()
    if (error) setMsg(error.message)
    else setShop(data as Shop)
  }
  useEffect(() => {
    void load()
  }, [shopId])
  async function save(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const f = new FormData(e.currentTarget),
      payload = {
        name: String(f.get('name') || '').trim(),
        city: String(f.get('city') || '').trim(),
        country: String(f.get('country') || '').trim(),
      }
    if (!payload.name) {
      setMsg('Le nom de la boutique est obligatoire.')
      return
    }
    const { error } = await supabase.from('shops').update(payload).eq('id', shopId)
    if (error)
      setMsg('Impossible d’enregistrer les paramètres. Vérifiez votre connexion puis réessayez.')
    else {
      const next: Shop = { ...shop!, ...payload }
      setShop(next)
      onShopUpdated(next)
      setMsg('✓ Paramètres enregistrés.')
    }
  }
  if (!shop) return <p>Chargement des paramètres…</p>
  return (
    <div>
      <div className="hello">
        <div>
          <h1>Paramètres</h1>
          <span>Identité et informations principales de votre commerce.</span>
        </div>
      </div>
      <form className="card formgrid" onSubmit={save}>
        <label>
          Nom de la boutique
          <input name="name" required defaultValue={shop.name} />
        </label>
        <label>
          Ville
          <input name="city" defaultValue={shop.city || ''} />
        </label>
        <label>
          Pays
          <input name="country" defaultValue={shop.country || 'Congo'} />
        </label>
        <label>
          Devise
          <input value={shop.currency} disabled />
          <small>La devise du commerce reste XAF pour cette version.</small>
        </label>
        <button className="primary span2">Enregistrer les paramètres</button>
      </form>
      {msg && <p className="successmsg">{msg}</p>}
      <section className="card">
        <small>COVI V1</small>
        <h2>Commerce connecté</h2>
        <p>
          Vos données sont protégées par votre compte COVI et synchronisées avec votre espace
          Supabase.
        </p>
      </section>
    </div>
  )
}
