import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { Button, PageHead, Sheet, Notice } from '../../components/ui'
import { money } from '../../lib/format'
import { supabase } from '../../lib/supabase'
import type { Tables } from '../../lib/database.types'

type Item = Tables<'restaurant_menu_items'>
type Kind = 'dish' | 'drink' | 'dessert'
const labels: Record<Kind, string> = { dish: 'Plat', drink: 'Boisson', dessert: 'Dessert' }

/** Real restaurant catalog (own shop only), distinct from clothes products. */
export function RestaurantMenuPage({ shopId }: { shopId: string }) {
  const [items, setItems] = useState<Item[]>([])
  const [showForm, setShowForm] = useState(false)
  const [kind, setKind] = useState<Kind>('dish')
  const [busy, setBusy] = useState(false)
  const [loading, setLoading] = useState(true)
  const [message, setMessage] = useState('')
  const [isError, setIsError] = useState(false)

  const reload = useCallback(async () => {
    const { data, error } = await supabase
      .from('restaurant_menu_items')
      .select('*')
      .eq('shop_id', shopId)
      .order('name')
    if (error) throw error
    setItems(data ?? [])
  }, [shopId])
  useEffect(() => {
    let alive = true
    void supabase
      .from('restaurant_menu_items')
      .select('*')
      .eq('shop_id', shopId)
      .order('name')
      .then(({ data, error }) => {
        if (!alive) return
        setLoading(false)
        if (error) {
          setIsError(true)
          setMessage('Impossible de charger la carte. Vérifiez la configuration de la base.')
        } else setItems(data ?? [])
      })
    return () => {
      alive = false
    }
  }, [shopId])

  async function add(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    if (busy) return
    const f = new FormData(e.currentTarget)
    const name = String(f.get('name') ?? '').trim()
    const category = String(f.get('category') ?? '').trim()
    const price = Number(f.get('price'))
    const initialStock = Number(f.get('drink_stock') ?? '0')
    if (
      name.length < 2 ||
      category.length < 2 ||
      !Number.isSafeInteger(price) ||
      price < 0 ||
      price > 1000000000 ||
      !Number.isSafeInteger(initialStock) ||
      initialStock < 0 ||
      initialStock > 1000000
    ) {
      setIsError(true)
      setMessage('Vérifiez le nom, la catégorie, le prix et le stock.')
      return
    }
    setBusy(true)
    try {
      const { error } = await supabase.from('restaurant_menu_items').insert({
        shop_id: shopId,
        name,
        category,
        kind,
        price_xaf: price,
        drink_stock: kind === 'drink' ? initialStock : null,
      })
      if (error) throw error
      await reload()
      setShowForm(false)
      setIsError(false)
      setMessage('Article ajouté à la carte.')
    } catch {
      setIsError(true)
      setMessage('Article non enregistré. Réessayez après vérification de vos données.')
    } finally {
      setBusy(false)
    }
  }

  async function toggle(item: Item) {
    if (busy) return
    setBusy(true)
    try {
      const { error } = await supabase
        .from('restaurant_menu_items')
        .update({ available: !item.available })
        .eq('id', item.id)
        .eq('shop_id', shopId)
      if (error) throw error
      await reload()
      setIsError(false)
      setMessage(item.available ? 'Article masqué.' : 'Article réactivé.')
    } catch {
      setIsError(true)
      setMessage('Modification impossible.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="page-stack">
      <PageHead
        title="Carte & boissons"
        sub="Votre menu, vos prix en FCFA et les quantités disponibles."
        action={
          <Button onClick={() => setShowForm(!showForm)}>
            {showForm ? 'Fermer' : 'Ajouter un article'}
          </Button>
        }
      />
      {showForm && (
        <Sheet>
          <form className="form-grid" onSubmit={(e) => void add(e)}>
            <label>
              Type de produit
              <select value={kind} onChange={(e) => setKind(e.target.value as Kind)}>
                {Object.entries(labels).map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Nom
              <input name="name" maxLength={120} required placeholder="Ex. Poisson braisé" />
            </label>
            <label>
              Catégorie
              <input name="category" maxLength={60} required placeholder="Ex. Plats du jour" />
            </label>
            <label>
              Prix en FCFA
              <input type="number" name="price" min={0} max={1000000000} step={1} required />
            </label>
            {kind === 'drink' && (
              <label>
                Quantité initiale en stock
                <input
                  type="number"
                  name="drink_stock"
                  min={0}
                  max={1000000}
                  step={1}
                  defaultValue={0}
                  required
                />
              </label>
            )}
            <Button type="submit" variant="primary" busy={busy}>
              Enregistrer dans ma carte
            </Button>
          </form>
        </Sheet>
      )}
      {message && (
        <Notice tone={isError ? 'danger' : 'success'}>
          <p>{message}</p>
        </Notice>
      )}
      <Sheet aria-label="Carte de votre restaurant">
        {loading ? (
          <p>Chargement de la carte…</p>
        ) : items.length === 0 ? (
          <p className="muted">
            Votre carte est vide. Ajoutez votre premier plat ou votre première boisson.
          </p>
        ) : (
          <ul className="team-invites">
            {items.map((item) => (
              <li key={item.id}>
                <div>
                  <strong>{item.name}</strong>
                  <p className="muted">
                    {labels[item.kind as Kind] ?? item.kind} · {item.category} ·{' '}
                    {money(item.price_xaf)}
                    {item.kind === 'drink' && ` · stock : ${item.drink_stock ?? 0}`}
                    {!item.available && ' · Indisponible'}
                  </p>
                </div>
                <Button disabled={busy} onClick={() => void toggle(item)}>
                  {item.available ? 'Masquer' : 'Réactiver'}
                </Button>
              </li>
            ))}
          </ul>
        )}
      </Sheet>
      <p className="muted">
        Les mouvements de stock, la commande collective et la déduction au service seront raccordés
        à la caisse dans un prochain lot. Le stock n'est pas encore décrémenté par une commande
        client.
      </p>
    </div>
  )
}
