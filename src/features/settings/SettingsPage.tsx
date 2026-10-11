import { useEffect, useState, type FormEvent } from 'react'
import { version } from '../../../package.json'
import { CheckIcon } from '../../components/icons'
import { Button, Field, Input, Ledger, LedgerRow, Notice } from '../../components/ui'
import { plural } from '../../lib/format'
import { cachedStock, pendingCount, rejectedSaleCount, stockCacheDate } from '../../lib/offline'
import type { Shop } from '../../lib/types'
import '../../styles/app/boutique.css'
import { useCurrentUser } from '../auth/useCurrentUser'
import { copyDate, readShopDraft, saveShop, type ShopDraft } from './shopSettings'

type Device = {
  pieces: number
  models: number
  copiedAt: string | null
  pending: number
  refused: number
}

function readDevice(shopId: string): Device {
  const stock = cachedStock<{ quantity_on_hand: number; status: string }>(shopId).filter(
    (p) => p.status === 'active',
  )
  return {
    pieces: stock.reduce((n, p) => n + Number(p.quantity_on_hand), 0),
    models: stock.length,
    copiedAt: stockCacheDate(shopId),
    pending: pendingCount(),
    refused: rejectedSaleCount(),
  }
}

/** What this device keeps to sell without network, refreshed when the sales queue moves. */
function useDevice(shopId: string) {
  const [device, setDevice] = useState(() => readDevice(shopId))
  useEffect(() => {
    const update = () => setDevice(readDevice(shopId))
    window.addEventListener('covi-sync', update)
    window.addEventListener('online', update)
    return () => {
      window.removeEventListener('covi-sync', update)
      window.removeEventListener('online', update)
    }
  }, [shopId])
  return device
}

/**
 * Ma boutique: name, city and country; the currency (FCFA, fixed); the account and signing out
 * (the shell asks for confirmation); what this device keeps for selling without network.
 */
export function SettingsPage({
  shop,
  onShopUpdated,
  onSignOut,
}: {
  shop: Shop
  onShopUpdated: (shop: Shop) => void
  /** Opens the shell’s « Se déconnecter de … ? » confirmation. */
  onSignOut: () => void
}) {
  const user = useCurrentUser()
  const device = useDevice(shop.id)
  const [draft, setDraft] = useState<ShopDraft>({
    name: shop.name,
    city: shop.city ?? '',
    country: shop.country || 'Congo',
  })
  const [error, setError] = useState('')
  const [status, setStatus] = useState<'idle' | 'busy' | 'saved' | 'failed'>('idle')
  const set = (key: keyof ShopDraft) => (value: string) => {
    setDraft((d) => ({ ...d, [key]: value }))
    if (status !== 'busy') setStatus('idle')
  }

  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const read = readShopDraft(draft)
    if ('error' in read) {
      setError(read.error)
      return
    }
    setError('')
    setStatus('busy')
    try {
      onShopUpdated(await saveShop(shop, read.values))
      setStatus('saved')
    } catch {
      setStatus('failed')
    }
  }

  const copied = copyDate(device.copiedAt)

  return (
    <div className="boutique-page">
      <header className="page-head">
        <div>
          <h1>Ma boutique</h1>
          <p className="page-head__sub">Le nom et la ville affichés dans COVI.</p>
        </div>
      </header>

      <form className="boutique-form" onSubmit={(e) => void submit(e)} noValidate>
        <Field label="Nom de la boutique" error={error}>
          {(control) => (
            <Input
              {...control}
              value={draft.name}
              autoComplete="organization"
              placeholder="Ex. Chez Mama Grâce"
              onChange={(e) => set('name')(e.target.value)}
            />
          )}
        </Field>
        <div className="boutique-form__pair">
          <Field label="Ville">
            {(control) => (
              <Input
                {...control}
                value={draft.city}
                placeholder="Ex. Brazzaville, Pointe-Noire"
                onChange={(e) => set('city')(e.target.value)}
              />
            )}
          </Field>
          <Field label="Pays">
            {(control) => (
              <Input
                {...control}
                value={draft.country}
                onChange={(e) => set('country')(e.target.value)}
              />
            )}
          </Field>
        </div>
        <div className="boutique-currency">
          <p className="field__label">Monnaie</p>
          <p className="boutique-currency__value">FCFA (francs CFA)</p>
          <p className="field__hint">
            Tous les montants sont en francs CFA (code bancaire XAF). La monnaie ne se change pas :
            ventes, charges et arrivages sont tous comptés en FCFA.
          </p>
        </div>
        {status === 'failed' && (
          <p className="field__error" role="alert">
            Pas enregistré : le réseau ne répond pas. Réessayez.
          </p>
        )}
        <div className="boutique-form__actions">
          <Button write variant="primary" type="submit" busy={status === 'busy'}>
            Enregistrer
          </Button>
          {status === 'saved' && (
            <p className="boutique-form__saved" role="status">
              <CheckIcon />
              C’est enregistré.
            </p>
          )}
        </div>
      </form>

      <section className="boutique-section" aria-labelledby="boutique-compte">
        <h2 className="section-title" id="boutique-compte">
          Votre compte
        </h2>
        {user?.email && (
          <p>
            Adresse : <strong className="boutique-email">{user.email}</strong>
          </p>
        )}
        <p className="boutique-section__text">
          Tout est gardé sur votre compte. Sur un autre téléphone ou ordinateur, connectez-vous avec
          la même adresse : vous retrouvez tout.
        </p>
        <div>
          <Button variant="danger" onClick={onSignOut}>
            Se déconnecter
          </Button>
        </div>
      </section>

      <section className="boutique-section" aria-labelledby="boutique-appareil">
        <h2 className="section-title" id="boutique-appareil">
          Sur cet appareil
        </h2>
        <p className="boutique-section__text">
          Pour vendre même sans réseau, COVI garde une copie du stock sur cet appareil.
        </p>
        <Ledger>
          <LedgerRow
            label="Stock gardé"
            meta={copied ? `copie faite ${copied}` : 'pas encore de copie : ouvrez Stock ou Vendre'}
            value={
              <span className="boutique-device__value">
                {device.models > 0 ? plural(device.pieces, 'pièce') : 'aucun'}
              </span>
            }
          />
          <LedgerRow
            label="Ventes à envoyer"
            meta={device.pending > 0 ? 'elles partiront dès que le réseau revient' : undefined}
            value={
              <span className="boutique-device__value">
                {device.pending > 0 ? device.pending : 'aucune, tout est envoyé'}
              </span>
            }
          />
          {device.refused > 0 && (
            <LedgerRow
              variant="link"
              label={<a href="#/ventes">Ventes non enregistrées</a>}
              meta="à voir dans Ventes"
              value={<span className="boutique-device__value">{device.refused}</span>}
            />
          )}
        </Ledger>
        {device.pending > 0 && (
          <Notice live={false}>
            <p>Ne désinstallez pas l’application et ne vous déconnectez pas avant l’envoi.</p>
          </Notice>
        )}
      </section>

      <p className="boutique-version">COVI {version}</p>
    </div>
  )
}
