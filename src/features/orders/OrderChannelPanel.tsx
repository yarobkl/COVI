import { useEffect, useId, useMemo, useState } from 'react'
import { Button, Notice } from '../../components/ui'
import { localQrSvgDataUrl } from '../../lib/localQr'
import { DEFAULT_ARTICLE_TYPES, uniqueArticleTypes } from '../../lib/articleTypes'
import {
  configureOrderChannel,
  getOrderChannel,
  orderErrorMessage,
  orderLink,
  rotateOrderChannel,
  saveOrderArticleTypes,
  type OrderChannelSettings,
} from '../../lib/publicOrders'

/**
 * « QR & liens » : le propriétaire active le canal client de sa boutique, imprime le QR code,
 * copie ou partage le lien pour WhatsApp / TikTok, et peut couper ou renouveler le lien à tout
 * moment (désactivation immédiate en cas d'abus).
 */
export function OrderChannelPanel({ shopId, shopName }: { shopId: string; shopName: string }) {
  const [channel, setChannel] = useState<OrderChannelSettings | null | undefined>(undefined)
  const [message, setMessage] = useState('')
  const [showCatalog, setShowCatalog] = useState(true)
  const [articleTypes, setArticleTypes] = useState<string[]>([...DEFAULT_ARTICLE_TYPES])
  const [suggestedType, setSuggestedType] = useState('')
  const [customType, setCustomType] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [copied, setCopied] = useState('')
  const ids = useId()
  const origin = window.location.origin

  useEffect(() => {
    getOrderChannel(shopId)
      .then((c) => {
        setChannel(c)
        if (c) {
          setMessage(c.message ?? '')
          setShowCatalog(c.showCatalog)
          setArticleTypes(c.articleTypes?.length ? c.articleTypes : [...DEFAULT_ARTICLE_TYPES])
        }
      })
      .catch((e) => setError(orderErrorMessage(e)))
  }, [shopId])

  const qrLink = channel ? orderLink(origin, channel.token, 'qr') : ''
  const socialLink = channel ? orderLink(origin, channel.token, 'social') : ''
  const qrImage = useMemo(() => (qrLink ? localQrSvgDataUrl(qrLink) : ''), [qrLink])

  const save = async (enabled: boolean) => {
    setBusy(true)
    setError('')
    try {
      if (!articleTypes.length) throw new Error('Choisissez au moins un type d’article.')
      await configureOrderChannel(shopId, {
        enabled,
        showCatalog,
        message: message.trim() || null,
      })
      setChannel(await saveOrderArticleTypes(shopId, uniqueArticleTypes(articleTypes)))
    } catch (e) {
      setError(orderErrorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  const addArticleType = (type: string) => {
    const name = type.trim()
    if (!name || name.length > 50) {
      setError('Le type d’article doit contenir 1 à 50 caractères.')
      return
    }
    setError('')
    setArticleTypes((current) => uniqueArticleTypes([...current, name]))
    setSuggestedType('')
    setCustomType('')
  }

  const copy = async (text: string, what: string) => {
    try {
      await navigator.clipboard.writeText(text)
      setCopied(what)
    } catch {
      setCopied('')
      window.prompt('Copiez le lien :', text)
    }
  }

  const share = async () => {
    const text = `Commandez chez ${shopName} : ${socialLink}`
    if (navigator.share) {
      try {
        await navigator.share({ title: shopName, text, url: socialLink })
        return
      } catch {
        // Partage annulé : rien à faire.
        return
      }
    }
    window.open(`https://wa.me/?text=${encodeURIComponent(text)}`, '_blank', 'noopener')
  }

  if (channel === undefined && !error) return <p role="status">Chargement…</p>

  return (
    <section className="order-channel" aria-label="QR code et liens de commande">
      <h2 className="section-title">QR code et liens de commande</h2>
      <p className="muted">
        Vos clients scannent le QR code ou ouvrent le lien reçu sur WhatsApp ou TikTok, choisissent
        leurs articles et envoient une demande, sans créer de compte. Les demandes arrivent dans «
        Commandes reçues ». Rien n’est vendu ni retiré du stock avant que le règlement soit confirmé
        en caisse.
      </p>

      <label className="order-confirm__check">
        <input
          type="checkbox"
          checked={showCatalog}
          onChange={(e) => setShowCatalog(e.target.checked)}
        />
        Afficher aux clients les types d’articles vendus (indépendamment du stock)
      </label>
      <div className="sheet order-channel__types" aria-label="Types d’articles vendus">
        <h3>Les articles que vend cette boutique</h3>
        <p className="muted">
          Le client pourra choisir parmi ces types même lorsque le stock est à zéro. Ajoutez ou
          retirez des types selon votre activité.
        </p>
        <div className="order-channel__actions">
          {articleTypes.map((type) => (
            <Button
              key={type}
              variant="secondary"
              disabled={busy}
              aria-label={`Retirer ${type}`}
              onClick={() => setArticleTypes((types) => types.filter((item) => item !== type))}
            >
              {type} ×
            </Button>
          ))}
        </div>
        <label>
          Ajouter un type courant
          <select
            className="select"
            value={suggestedType}
            onChange={(event) => setSuggestedType(event.target.value)}
          >
            <option value="">Choisir un type d’article…</option>
            {DEFAULT_ARTICLE_TYPES.filter(
              (type) => !articleTypes.some((item) => item.toLowerCase() === type.toLowerCase()),
            ).map((type) => (
              <option key={type} value={type}>
                {type}
              </option>
            ))}
          </select>
        </label>
        <Button
          variant="secondary"
          disabled={!suggestedType || busy}
          onClick={() => addArticleType(suggestedType)}
        >
          Ajouter à la liste
        </Button>
        <label>
          Autre type d’article
          <input
            className="input"
            value={customType}
            maxLength={50}
            placeholder="Ex. Boubou, pagne, foulard"
            onChange={(event) => setCustomType(event.target.value)}
          />
        </label>
        <Button
          variant="secondary"
          disabled={!customType.trim() || busy}
          onClick={() => addArticleType(customType)}
        >
          Ajouter ce type
        </Button>
        <p className="muted">Enregistrez ensuite les réglages pour publier cette liste.</p>
      </div>
      <label htmlFor={`${ids}-msg`}>Message affiché aux clients (facultatif)</label>
      <textarea
        id={`${ids}-msg`}
        className="input"
        rows={2}
        maxLength={500}
        value={message}
        placeholder="Ex. Retrait au marché Total, livraison à Brazzaville sous 24 h"
        onChange={(e) => setMessage(e.target.value)}
      />

      {error && (
        <Notice tone="danger">
          <p>{error}</p>
        </Notice>
      )}

      {!channel?.enabled ? (
        <Button variant="primary" busy={busy} onClick={() => void save(true)}>
          {channel ? 'Réactiver les commandes en ligne' : 'Activer les commandes en ligne'}
        </Button>
      ) : (
        <>
          <Notice tone="success" title="Commandes en ligne actives">
            <p>Le QR code et les liens ci-dessous sont utilisables par vos clients.</p>
          </Notice>
          <Button variant="secondary" busy={busy} onClick={() => void save(true)}>
            Enregistrer les réglages
          </Button>
        </>
      )}

      {channel && (
        <>
          <figure className="order-channel__qr">
            <img
              src={qrImage}
              width={240}
              height={240}
              alt={`QR code de commande de ${shopName}`}
            />
            <figcaption>
              <b>{shopName}</b>
              <br />
              Scannez pour commander
            </figcaption>
          </figure>
          {!channel.enabled && (
            <Notice tone="danger">
              <p>
                Canal désactivé : ce QR code et ces liens affichent « lien inactif » aux clients.
              </p>
            </Notice>
          )}
          <div className="order-channel__actions">
            <Button variant="secondary" onClick={() => window.print()}>
              Imprimer le QR code
            </Button>
            <Button variant="secondary" onClick={() => void copy(qrLink, 'qr')}>
              {copied === 'qr' ? 'Lien du QR copié' : 'Copier le lien du QR'}
            </Button>
            <Button variant="secondary" onClick={() => void copy(socialLink, 'social')}>
              {copied === 'social' ? 'Lien copié' : 'Copier le lien WhatsApp / TikTok'}
            </Button>
            <Button variant="secondary" onClick={() => void share()}>
              Partager
            </Button>
            <a className="btn btn--ghost" href={socialLink} target="_blank" rel="noreferrer">
              Voir la page client
            </a>
          </div>
          <p className="order-channel__url">
            <code>{socialLink}</code>
          </p>
          <div className="order-channel__danger">
            {channel.enabled && (
              <Button variant="ghost" busy={busy} onClick={() => void save(false)}>
                Couper les commandes en ligne
              </Button>
            )}
            <Button
              variant="ghost"
              busy={busy}
              onClick={async () => {
                if (
                  !window.confirm(
                    'Renouveler le lien ? L’ancien QR code et les anciens liens ne fonctionneront plus.',
                  )
                )
                  return
                setBusy(true)
                try {
                  setChannel(await rotateOrderChannel(shopId))
                } catch (e) {
                  setError(orderErrorMessage(e))
                } finally {
                  setBusy(false)
                }
              }}
            >
              Renouveler le lien (invalide l’ancien QR)
            </Button>
          </div>
        </>
      )}
    </section>
  )
}
