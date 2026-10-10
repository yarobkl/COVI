import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import './admin.css'

type SubscriptionRow = {
  subscription_id: string
  owner_user_id: string
  status: string
  shop_limit: number
  period_end: string | null
  monthly_price_xaf: number
}

type RpcResult<T> = Promise<{ data: T | null; error: { message: string } | null }>
const adminRpc = supabase.rpc as unknown as (
  name: string,
  args?: Record<string, unknown>,
) => RpcResult<unknown>

const money = (value: number) => new Intl.NumberFormat('fr-FR').format(value) + ' FCFA'
const shortId = (id: string) => id.slice(0, 8) + '…'

export function AdminPage() {
  const [loading, setLoading] = useState(true)
  const [authorized, setAuthorized] = useState(false)
  const [signedIn, setSignedIn] = useState(false)
  const [rows, setRows] = useState<SubscriptionRow[]>([])
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [invoiceNumber, setInvoiceNumber] = useState('')
  const [ownerId, setOwnerId] = useState('')
  const [quota, setQuota] = useState('1')
  const [periodStart, setPeriodStart] = useState('')
  const [periodEnd, setPeriodEnd] = useState('')
  const [invoiceId, setInvoiceId] = useState('')
  const [provider, setProvider] = useState('MTN Mobile Money')
  const [reference, setReference] = useState('')
  const [amount, setAmount] = useState('')
  const [notice, setNotice] = useState('')

  const load = useCallback(async () => {
    setLoading(true)
    setError('')
    const { data: session } = await supabase.auth.getSession()
    setSignedIn(Boolean(session.session))
    if (!session.session) {
      setAuthorized(false)
      setLoading(false)
      return
    }
    const auth = await adminRpc('covi_is_platform_admin')
    if (auth.error || auth.data !== true) {
      setAuthorized(false)
      setError(auth.error?.message ?? '')
      setLoading(false)
      return
    }
    setAuthorized(true)
    const result = await adminRpc('covi_admin_subscription_overview')
    if (result.error) setError(result.error.message)
    else setRows((result.data ?? []) as SubscriptionRow[])
    setLoading(false)
  }, [])

  useEffect(() => {
    void load()
    const { data } = supabase.auth.onAuthStateChange(() => void load())
    return () => data.subscription.unsubscribe()
  }, [load])

  async function issueInvoice(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setBusy(true)
    setError('')
    setNotice('')
    try {
      const result = await adminRpc('covi_admin_issue_subscription_invoice', {
        p_owner_user_id: ownerId.trim(),
        p_invoice_number: invoiceNumber.trim(),
        p_shop_limit: Number(quota),
        p_period_start: new Date(periodStart).toISOString(),
        p_period_end: new Date(periodEnd).toISOString(),
      })
      if (result.error) throw new Error(result.error.message)
      setInvoiceId(String(result.data))
      setNotice('Facture créée. Identifiant reporté dans le formulaire de paiement.')
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Impossible de créer la facture.')
    } finally {
      setBusy(false)
    }
  }

  async function confirmPayment(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!window.confirm('Avez-vous personnellement vérifié la réception effective des fonds ?')) return
    setBusy(true)
    setError('')
    setNotice('')
    try {
      const result = await adminRpc('covi_admin_confirm_mobile_payment', {
        p_invoice_id: invoiceId.trim(),
        p_provider: provider.trim(),
        p_provider_reference: reference.trim(),
        p_amount_xaf: Number(amount),
      })
      if (result.error) throw new Error(result.error.message)
      setNotice('Paiement enregistré et abonnement activé par le serveur.')
      setReference('')
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Impossible de confirmer le paiement.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <main className="covi-admin">
      <header className="covi-admin__top">
        <a className="covi-admin__brand" href="/">COVI<span> / Administration</span></a>
        <a className="covi-admin__back" href="/">Retour au commerce ↗</a>
      </header>
      <div className="covi-admin__layout">
        <aside className="covi-admin__side" aria-label="Navigation administration">
          <span className="covi-admin__eyebrow">LE CAHIER · PILOTAGE</span>
          <strong>Super Admin</strong>
          <p>La gestion des commerçants, sans toucher à leurs caisses.</p>
          <nav><a href="#abonnements">01 · Abonnements</a><a href="#factures">02 · Facturation</a><a href="#paiements">03 · Mobile Money</a></nav>
          <small>Accès réservé aux administrateurs autorisés.</small>
        </aside>
        <div className="covi-admin__main">
          <p className="covi-admin__eyebrow">COVI / VUE GÉNÉRALE</p>
          <h1>Le registre des <em>abonnements.</em></h1>
          <p className="covi-admin__intro">Suivez les comptes commerçants, préparez les factures et confirmez uniquement les paiements réellement reçus.</p>
          {loading && <p role="status">Vérification des autorisations…</p>}
          {!loading && !signedIn && <section className="covi-admin__panel"><h2>Connexion nécessaire</h2><p>Connectez-vous à COVI avec votre compte administrateur avant de revenir ici.</p><a href="/">Aller à la connexion →</a></section>}
          {!loading && signedIn && !authorized && <section className="covi-admin__panel"><h2>Accès réservé</h2><p>Votre compte ne possède pas les droits Super Admin.</p></section>}
          {error && <p className="covi-admin__error" role="alert">{error}</p>}
          {notice && <p className="covi-admin__success" role="status">{notice}</p>}
          {!loading && authorized && <>
            <div className="covi-admin__stats">
              <div><span>Abonnements</span><strong>{rows.length}</strong></div>
              <div><span>Actifs</span><strong>{rows.filter((r) => r.status === 'active').length}</strong></div>
              <div><span>Mensuel actif</span><strong>{money(rows.filter((r) => r.status === 'active').reduce((sum, r) => sum + r.monthly_price_xaf, 0))}</strong></div>
            </div>
            <section className="covi-admin__panel" id="abonnements">
              <div className="covi-admin__sectionhead"><div><span className="covi-admin__eyebrow">01 / RÉPERTOIRE</span><h2>Comptes commerçants</h2></div><button type="button" onClick={() => void load()}>Actualiser ↻</button></div>
              <div className="covi-admin__tablewrap"><table><thead><tr><th>Compte</th><th>État</th><th>Boutiques</th><th>Mensualité</th><th>Échéance</th></tr></thead><tbody>
                {rows.map((r) => <tr key={r.subscription_id}><td title={r.owner_user_id}>{shortId(r.owner_user_id)}</td><td><span className={'covi-admin__status covi-admin__status--' + r.status}>{r.status}</span></td><td>{r.shop_limit}</td><td>{money(r.monthly_price_xaf)}</td><td>{r.period_end ? new Date(r.period_end).toLocaleDateString('fr-FR') : '—'}</td></tr>)}
                {rows.length === 0 && <tr><td colSpan={5}>Aucun abonnement enregistré.</td></tr>}
              </tbody></table></div>
            </section>
            <div className="covi-admin__forms">
              <section className="covi-admin__panel" id="factures"><span className="covi-admin__eyebrow">02 / PRÉPARATION</span><h2>Émettre une facture</h2><p>Pour un compte Supabase Auth existant. Un paiement n'est pas encore confirmé.</p>
                <form onSubmit={(e) => void issueInvoice(e)}>
                  <label>Identifiant utilisateur (UUID)<input required value={ownerId} onChange={(e) => setOwnerId(e.target.value)} placeholder="UUID du commerçant" /></label>
                  <label>Numéro de facture<input required value={invoiceNumber} onChange={(e) => setInvoiceNumber(e.target.value)} placeholder="COVI-2026-0001" /></label>
                  <label>Nombre de boutiques<input type="number" min="1" max="10000" required value={quota} onChange={(e) => setQuota(e.target.value)} /></label>
                  <label>Début de période<input type="datetime-local" required value={periodStart} onChange={(e) => setPeriodStart(e.target.value)} /></label>
                  <label>Fin de période<input type="datetime-local" required value={periodEnd} onChange={(e) => setPeriodEnd(e.target.value)} /></label>
                  <p className="covi-admin__amount">Montant prévu : {Number.isSafeInteger(Number(quota)) && Number(quota) >= 1 ? money(10000 + (Number(quota) - 1) * 5000) : '—'}</p>
                  <button disabled={busy} type="submit">Créer la facture →</button>
                </form>
              </section>
              <section className="covi-admin__panel" id="paiements"><span className="covi-admin__eyebrow">03 / ENCAISSEMENT</span><h2>Confirmer Mobile Money</h2><p>Vérifiez d'abord les fonds sur votre compte de réception. Cette action active l'abonnement.</p>
                <form onSubmit={(e) => void confirmPayment(e)}>
                  <label>Identifiant facture (UUID)<input required value={invoiceId} onChange={(e) => setInvoiceId(e.target.value)} placeholder="UUID de la facture" /></label>
                  <label>Opérateur<select value={provider} onChange={(e) => setProvider(e.target.value)}><option>MTN Mobile Money</option><option>Airtel Money</option><option>Autre</option></select></label>
                  <label>Référence du transfert<input required value={reference} onChange={(e) => setReference(e.target.value)} placeholder="Référence vérifiée" /></label>
                  <label>Montant reçu (FCFA)<input type="number" min="1" required value={amount} onChange={(e) => setAmount(e.target.value)} /></label>
                  <button disabled={busy} type="submit">Confirmer et activer →</button>
                </form>
                <p className="covi-admin__warning">Ne confirmez jamais un paiement à partir d'une simple capture d'écran.</p>
              </section>
            </div>
          </>}
        </div>
      </div>
    </main>
  )
}
