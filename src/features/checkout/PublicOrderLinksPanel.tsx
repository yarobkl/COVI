import { useEffect, useState } from 'react'
import { LocalQRCode } from './LocalQRCode'
import { Button, Notice, Sheet } from '../../components/ui'
import {
  configurePublicOrderLink,
  getPublicOrderLink,
  publicOrderUrl,
  rotatePublicOrderLink,
  type PublicOrderLink,
} from '../../lib/publicOrders'

/** The permanent URL is owned by the merchant. It allows requests, NOT sales.
 * No third-party QR image service is called or given the bearer token.
 */
export function PublicOrderLinksPanel({ shopId, shopName }: { shopId: string; shopName: string }) {
  const [link, setLink] = useState<PublicOrderLink | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    let alive = true
    getPublicOrderLink(shopId).then(
      result => { if (alive) setLink(result) },
      reason => { if (alive) setError(reason instanceof Error ? reason.message : 'Lien indisponible.') },
    ).finally(() => { if (alive) setLoading(false) })
    return () => { alive = false }
  }, [shopId])

  async function configure(enabled: boolean) {
    setBusy(true)
    setError('')
    setNotice('')
    try {
      const result = await configurePublicOrderLink(shopId, enabled)
      setLink(result)
      setNotice(enabled ? 'Le lien de commandes est maintenant actif.' :
        'Le lien est désactivé : les clients ne peuvent plus envoyer de demandes.')
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Modification impossible.')
    } finally { setBusy(false) }
  }

  async function rotate() {
    // Invalidate old printed QR codes and shared links only after confirmation.
    if (!window.confirm(
      'Créer un nouveau lien ? Les anciens liens et QR codes ne fonctionneront plus.',
    )) return
    setBusy(true)
    setError('')
    setNotice('')
    try {
      setLink(await rotatePublicOrderLink(shopId))
      setNotice('Nouveau lien créé. Les anciens liens sont invalides.')
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Renouvellement impossible.')
    } finally { setBusy(false) }
  }

  async function copy(channel: 'qr' | 'social') {
    if (!link?.enabled) return
    try {
      await navigator.clipboard.writeText(publicOrderUrl(
        window.location.href, link.publicToken, channel,
      ))
      setNotice('Lien copié. Partagez-le uniquement lorsque vous le souhaitez.')
    } catch {
      setError('Copie impossible sur cet appareil. Sélectionnez le lien affiché.')
    }
  }

  const socialUrl = link?.enabled
    ? publicOrderUrl(window.location.href, link.publicToken, 'social') : null
  const qrUrl = link?.enabled
    ? publicOrderUrl(window.location.href, link.publicToken, 'qr') : null

  return (
    <Sheet className="checkout-share" aria-label="Commandes par QR code et réseaux sociaux">
      <p className="hand">La porte de la boutique.</p>
      <h2>Mes liens de commande</h2>
      <p>
        Le lien permanent sert à recevoir les demandes des clients depuis
        TikTok, WhatsApp, Instagram, Facebook ou votre boutique.
      </p>
      <p className="checkout-share__caution">
        Recevoir une demande ne valide aucun paiement et ne retire rien du stock.
        Seul le commerçant confirme la vente après réception de l'argent.
      </p>

      {loading && <p role="status">Vérification du lien de la boutique…</p>}
      {error && <Notice tone="danger"><p>{error}</p></Notice>}
      {notice && <p role="status" className="checkout-share__success">{notice}</p>}

      {!loading && (
        <div className="checkout-share__actions">
          <p>
            État : <strong>{link?.enabled ? 'Actif' : 'Désactivé'}</strong>
          </p>
          <Button variant={link?.enabled ? 'secondary' : 'sale'}
            disabled={busy} busy={busy}
            onClick={() => { void configure(!link?.enabled) }}>
            {link?.enabled ? 'Désactiver les demandes' : 'Activer mes liens de commande'}
          </Button>
          {link?.enabled && socialUrl && qrUrl && (
            <>
              <label className="field">
                <span className="field__label">Lien à partager sur les réseaux</span>
                <input className="input checkout-share__url" readOnly
                  aria-label="Lien de commande réseaux sociaux" value={socialUrl}
                  onFocus={e => e.target.select()} />
              </label>
              <Button variant="tactile" block disabled={busy}
                onClick={() => { void copy('social') }}>Copier le lien TikTok / WhatsApp</Button>
              <label className="field">
                <span className="field__label">Lien permanent pour le QR en boutique</span>
                <input className="input checkout-share__url" readOnly
                  aria-label="Lien de commande QR" value={qrUrl}
                  onFocus={e => e.target.select()} />
              </label>
              <Button variant="tactile" block disabled={busy}
                onClick={() => { void copy('qr') }}>Copier le lien pour QR code</Button>
              <LocalQRCode value={qrUrl} shopName={shopName} />
              <Button variant="ghost" disabled={busy}
                onClick={() => { void rotate() }}>
                Remplacer les liens actuels
              </Button>
            </>
          )}
        </div>
      )}
    </Sheet>
  )
}
