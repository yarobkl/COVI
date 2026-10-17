import { useEffect, useId, useState } from 'react'
import { Button, Notice } from '../../components/ui'
import {
  getOpenPaySettings,
  openPayCallbackUrl,
  saveOpenPayKey,
  setOpenPayEnabled,
  type OpenPaySettings,
} from '../../lib/mobilePayments'

/**
 * « Paiement Mobile Money » dans QR & liens : la boutique colle SA clé API OpenPay (envoyée une
 * fois au serveur, jamais réaffichée) et copie l'URL de callback dans son tableau de bord OpenPay.
 * L'argent arrive sur le compte OpenPay de la boutique, jamais sur celui de COVI.
 */
export function OpenPaySettingsPanel({ shopId }: { shopId: string }) {
  const keyId = useId()
  const [settings, setSettings] = useState<OpenPaySettings | null>(null)
  const [apiKey, setApiKey] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')

  useEffect(() => {
    getOpenPaySettings(shopId)
      .then(setSettings)
      .catch(() => setSettings({ configured: false, enabled: false, keyHint: null }))
  }, [shopId])

  const run = async (action: () => Promise<OpenPaySettings>, done: string) => {
    setBusy(true)
    setError('')
    setMessage('')
    try {
      setSettings(await action())
      setMessage(done)
    } catch (e) {
      const text = (e as { message?: string }).message ?? ''
      setError(
        text.includes('Invalid OpenPay key')
          ? 'Clé invalide : copiez la clé API complète depuis votre tableau de bord OpenPay.'
          : 'Enregistrement impossible. Vérifiez la connexion et réessayez.',
      )
    } finally {
      setBusy(false)
    }
  }

  return (
    <section className="order-channel" aria-labelledby={`${keyId}-title`}>
      <h2 className="section-title" id={`${keyId}-title`}>
        Paiement Mobile Money (OpenPay)
      </h2>
      <p className="muted">
        Demandez le paiement d’une commande directement sur le téléphone du client (MTN MoMo ou
        Airtel Money). L’argent arrive sur le compte OpenPay de votre boutique ; COVI ne le touche
        jamais.
      </p>
      {settings === null ? (
        <p role="status">Chargement…</p>
      ) : settings.configured ? (
        <p role="status">
          Clé enregistrée (se termine par <b>{settings.keyHint}</b>) ·{' '}
          <b>{settings.enabled ? 'Actif' : 'Coupé'}</b>
        </p>
      ) : (
        <p role="status">Pas encore configuré.</p>
      )}
      <ol className="order-channel__steps">
        <li>
          Créez votre compte sur{' '}
          <a href="https://www.openpay.cg" target="_blank" rel="noreferrer">
            openpay.cg
          </a>{' '}
          et copiez votre clé API.
        </li>
        <li>
          Dans votre tableau de bord OpenPay (onglet Callback URL), collez cette adresse :
          <br />
          <code className="order-channel__callback">{openPayCallbackUrl}</code>{' '}
          <Button
            variant="ghost"
            onClick={() => void navigator.clipboard?.writeText(openPayCallbackUrl)}
          >
            Copier
          </Button>
        </li>
        <li>Collez votre clé API ci-dessous.</li>
      </ol>
      <label htmlFor={keyId}>
        {settings?.configured ? 'Remplacer la clé API OpenPay' : 'Clé API OpenPay'}
      </label>
      <input
        id={keyId}
        className="input"
        type="password"
        autoComplete="off"
        spellCheck={false}
        value={apiKey}
        maxLength={300}
        onChange={(e) => setApiKey(e.target.value.trim())}
      />
      <div className="order-channel__actions">
        <Button
          variant="primary"
          busy={busy}
          disabled={apiKey.length < 12}
          onClick={() =>
            void run(async () => {
              const next = await saveOpenPayKey(shopId, apiKey)
              setApiKey('')
              return next
            }, 'Clé enregistrée. Elle ne sera plus jamais affichée.')
          }
        >
          Enregistrer la clé
        </Button>
        {settings?.configured && (
          <Button
            variant="secondary"
            disabled={busy}
            onClick={() =>
              void run(
                () => setOpenPayEnabled(shopId, !settings.enabled),
                settings.enabled ? 'Paiement Mobile Money coupé.' : 'Paiement Mobile Money activé.',
              )
            }
          >
            {settings.enabled ? 'Couper le paiement Mobile Money' : 'Réactiver'}
          </Button>
        )}
      </div>
      {message && (
        <Notice tone="success">
          <p>{message}</p>
        </Notice>
      )}
      {error && (
        <Notice tone="danger">
          <p>{error}</p>
        </Notice>
      )}
    </section>
  )
}
