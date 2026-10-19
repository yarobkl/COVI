import { useEffect, useState } from 'react'
import { Button, Notice } from '../../components/ui'
import {
  createWebsiteConnection,
  listWebsiteConnections,
  revokeWebsiteConnection,
  websiteConnectUrl,
  type WebsiteConnection
} from '../../lib/websiteConnect'

/** Website connector credentials: generated once, server-side only. */
export function WebsiteConnectPanel({ shopId }: { shopId: string }) {
  const [connections, setConnections] = useState<WebsiteConnection[]>([])
  const [label, setLabel] = useState('')
  const [siteUrl, setSiteUrl] = useState('')
  const [secret, setSecret] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')

  useEffect(() => {
    let mounted = true
    listWebsiteConnections(shopId).then(items => {
      if (mounted) setConnections(items)
    }).catch(() => {
      if (mounted) setError('Impossible de charger les sites connectés.')
    })
    return () => { mounted = false }
  }, [shopId])

  const refresh = async () => setConnections(await listWebsiteConnections(shopId))

  const create = async () => {
    setBusy(true)
    setError('')
    setMessage('')
    setSecret('')
    try {
      const result = await createWebsiteConnection(shopId, label.trim(), siteUrl.trim())
      setSecret(result.secret)
      setLabel('')
      setSiteUrl('')
      await refresh()
      setMessage('Accès créé. Copiez sa clé maintenant : elle ne sera plus affichée.')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Connexion impossible.')
    } finally { setBusy(false) }
  }

  const revoke = async (connectionId: string) => {
    if (!window.confirm('Déconnecter ce site ? Sa clé cessera immédiatement de fonctionner.')) return
    setBusy(true)
    setError('')
    setMessage('')
    setSecret('')
    try {
      await revokeWebsiteConnection(connectionId)
      await refresh()
      setMessage('Connexion révoquée.')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Déconnexion impossible.')
    } finally { setBusy(false) }
  }

  return (
    <section className="page-stack" aria-label="COVI Connect — sites internet">
      <div className="sheet">
        <h2 className="section-title">COVI Connect — Sites internet</h2>
        <p className="muted">
          Reliez un site e-commerce à cette boutique. Le site peut consulter vos quantités et
          envoyer des commandes dans « Commandes reçues ». Le commerçant confirme toujours
          le règlement dans COVI avant qu’une vente diminue le stock.
        </p>
        <p className="muted">
          Chaque site possède une clé secrète indépendante. Elle doit rester sur son serveur,
          jamais dans une page visible par les visiteurs.
        </p>
        <label htmlFor="site-connect-label">Nom de cette connexion</label>
        <input id="site-connect-label" className="input" value={label} maxLength={80}
          placeholder="Ex. Ma boutique WooCommerce"
          onChange={e => setLabel(e.target.value)} />
        <label htmlFor="site-connect-url">Adresse du site</label>
        <input id="site-connect-url" className="input" value={siteUrl} type="url"
          placeholder="https://maboutique.com" maxLength={255}
          onChange={e => setSiteUrl(e.target.value)} />
        <div className="order-channel__actions">
          <Button variant="primary" busy={busy}
            disabled={!label.trim() || !/^https:\/\//.test(siteUrl.trim())}
            onClick={() => void create()}>
            Générer une clé de connexion
          </Button>
        </div>
        {error && <Notice tone="danger"><p>{error}</p></Notice>}
        {message && <Notice tone="success"><p>{message}</p></Notice>}
        {secret && (
          <div className="sheet" role="status">
            <strong>Clé secrète — affichée une seule fois</strong>
            <p className="muted">Ne la communiquez qu’au développeur ou au serveur de votre site.</p>
            <input className="input" aria-label="Clé secrète créée" value={secret}
              readOnly onFocus={e => e.currentTarget.select()} />
            <Button variant="secondary" onClick={() => void navigator.clipboard.writeText(secret)}>
              Copier la clé
            </Button>
            <Button variant="secondary" onClick={() => setSecret('')}>
              J’ai sauvegardé la clé
            </Button>
          </div>
        )}
      </div>

      <div className="sheet">
        <h3>Mes sites connectés</h3>
        {!connections.length ? <p className="muted">Aucun site connecté pour le moment.</p> : (
          <ul className="page-stack">
            {connections.map(c => (
              <li key={c.id} className="sheet">
                <strong>{c.label}</strong>
                <p className="muted">{c.siteUrl}</p>
                <p className="muted">
                  {c.active ? 'Clé active' : 'Accès révoqué'} ·
                  {c.lastUsedAt ? ` Dernier appel : ${new Date(c.lastUsedAt).toLocaleString('fr-FR')}` :
                    ' Aucun appel enregistré'}
                </p>
                {c.active && <Button variant="secondary" busy={busy} onClick={() => void revoke(c.id)}>
                  Révoquer la connexion
                </Button>}
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="sheet">
        <h3>À transmettre au développeur du site</h3>
        <p className="muted">Adresse de l’API : {websiteConnectUrl}</p>
        <p className="muted">Requêtes serveur uniquement avec l’en-tête
          <code> x-covi-key </code>. Le catalogue se lit via
          <code> GET /products </code> et les commandes se déposent via
          <code> POST /orders </code>. Une connexion spécifique du site est nécessaire.
        </p>
      </div>
    </section>
  )
}
