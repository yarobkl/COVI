import { useCallback, useEffect, useState } from 'react'
import { Button, Notice } from '../../components/ui'
import { GuestSheet } from '../orders/GuestSheet'
import { RestaurantGuestBasket } from './RestaurantGuestBasket'
import { restaurantGuestEnabled } from '../../lib/restaurantGuests'
import {
  fetchRestaurantQr,
  type RestaurantQrCatalog,
  type RestaurantQrMenuItem,
} from '../../lib/restaurantQr'

const formatXaf = (value: number) =>
  new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 0 }).format(value) + ' FCFA'

const statusLabels = {
  free: 'Table disponible',
  collecting: 'Choix du groupe en cours',
  occupied: 'Table occupée — commande déjà envoyée',
} as const

/**
 * Public QR page: read-only by design until guest admission and server authorization
 * are tested. The UI cannot take payment or pretend an order was submitted.
 */
export function PublicRestaurantTablePage({ token }: { token: string }) {
  const [catalog, setCatalog] = useState<RestaurantQrCatalog | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  const load = useCallback(async () => {
    setLoading(true)
    setError('')
    try {
      setCatalog(await fetchRestaurantQr(token))
    } catch (err) {
      setCatalog(null)
      setError(err instanceof Error ? err.message : 'Impossible de consulter cette table.')
    } finally {
      setLoading(false)
    }
  }, [token])

  useEffect(() => {
    // Schedule after effect setup: loading updates should not cascade synchronously.
    void Promise.resolve().then(load)
  }, [load])
  useEffect(() => {
    document.title = catalog ? `Carte — ${catalog.restaurantName}` : 'Carte Restaurant — COVI'
  }, [catalog])

  const groups =
    catalog?.menu.reduce<Record<string, RestaurantQrMenuItem[]>>((result, item) => {
      ;(result[item.category] ??= []).push(item)
      return result
    }, {}) ?? {}

  return (
    <GuestSheet shop={catalog?.restaurantName}>
      <section className="order-guest__part">
        <h1 className="section-title">Carte du restaurant</h1>
        {loading ? (
          <p role="status">Chargement de la table…</p>
        ) : error ? (
          <Notice tone="danger">
            <p>{error}</p>
          </Notice>
        ) : catalog ? (
          <>
            <p>
              <strong>Table {catalog.tableName}</strong> · {catalog.capacity} places
            </p>
            <Notice tone="calm">
              <p>{statusLabels[catalog.tableState]}</p>
              <p>
                {restaurantGuestEnabled
                  ? 'Chaque participant rejoint le groupe avec son code temporaire. La commande part uniquement après validation du responsable.'
                  : 'La consultation de la carte est disponible. La commande collective par QR sera activée après validation des tests de sécurité. Pour commander, adressez-vous au personnel.'}
              </p>
            </Notice>
            {restaurantGuestEnabled && <RestaurantGuestBasket table={token} catalog={catalog} />}
            {Object.entries(groups).length === 0 ? (
              <p>Aucun article publié par le restaurant pour l’instant.</p>
            ) : (
              Object.entries(groups).map(([category, items]) => (
                <section className="order-guest__part" key={category}>
                  <h2 className="section-title">{category}</h2>
                  <ul className="team-invites">
                    {items.map((item) => (
                      <li key={item.id}>
                        <div>
                          <strong>{item.name}</strong>
                          <p className="muted">
                            {item.kind === 'drink'
                              ? 'Boisson'
                              : item.kind === 'dessert'
                                ? 'Dessert'
                                : 'Plat'}
                          </p>
                          {!item.available && <p className="muted">Épuisé</p>}
                        </div>
                        <strong>{formatXaf(item.priceXaf)}</strong>
                      </li>
                    ))}
                  </ul>
                </section>
              ))
            )}
          </>
        ) : null}
        {!loading && <Button onClick={() => void load()}>Actualiser la carte</Button>}
      </section>
    </GuestSheet>
  )
}
