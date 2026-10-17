import { useCallback, useEffect, useRef, useState, type FormEvent } from 'react'
import { Button, Notice, Sheet } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import type { Tables } from '../../lib/database.types'

type Incident = Tables<'restaurant_served_incidents'>
type Refund = Tables<'restaurant_cash_refunds'>
type Quote = {
  incidentId: string
  orderReference: string | null
  state: string
  paidXaf: string
  refundedXaf: string
  linePriceXaf: string
  lineRefundedXaf: string
  maximumXaf: string
  alreadyRefunded: boolean
  method: 'cash'
}
const isAmount = (v: unknown): v is string => typeof v === 'string' &&
  /^\d{1,19}$/.test(v)
const xaf = (n: string | bigint) =>
  new Intl.NumberFormat('fr-FR').format(BigInt(n)) + ' FCFA'
function readQuote(raw: unknown): Quote {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw))
    throw Error('Devis de remboursement invalide.')
  const q = raw as Partial<Quote>
  if (typeof q.incidentId !== 'string' ||
    typeof q.state !== 'string' || q.method !== 'cash' ||
    typeof q.alreadyRefunded !== 'boolean' ||
    !isAmount(q.paidXaf) || !isAmount(q.refundedXaf) ||
    !isAmount(q.linePriceXaf) || !isAmount(q.lineRefundedXaf) ||
    !isAmount(q.maximumXaf)) throw Error('Montants impossibles à vérifier.')
  if (BigInt(q.refundedXaf)>BigInt(q.paidXaf) ||
      BigInt(q.lineRefundedXaf)>BigInt(q.linePriceXaf) ||
      BigInt(q.maximumXaf)>BigInt(q.paidXaf)-BigInt(q.refundedXaf) ||
      BigInt(q.maximumXaf)>BigInt(q.linePriceXaf)-BigInt(q.lineRefundedXaf))
    throw Error('Montants incohérents. Encaissement interdit.')
  return q as Quote
}

/** Owner only. Cash refund requires REAL cash handed to customer, never intent. */
export function RestaurantCashRefundsPanel({ shopId }: { shopId: string }) {
  const [approved, setApproved] = useState<Incident[]>([])
  const [refunds, setRefunds] = useState<Refund[]>([])
  const [ticket, setTicket] = useState('')
  const [quote, setQuote] = useState<Quote | null>(null)
  const [amount, setAmount] = useState('')
  const [reason, setReason] = useState('')
  const [cashHanded, setCashHanded] = useState(false)
  const [busy, setBusy] = useState(false)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const operation = useRef(crypto.randomUUID())

  const reload = useCallback(async () => {
    const [inc, ledger] = await Promise.all([
      supabase.from('restaurant_served_incidents').select('*')
        .eq('shop_id',shopId).eq('state','requires_refund_review')
        .order('created_at',{ascending:false}).limit(100),
      supabase.from('restaurant_cash_refunds').select('*')
        .eq('shop_id',shopId).order('confirmed_at',{ascending:false}).limit(30),
    ])
    if (inc.error || ledger.error)
      throw Error('Impossible de charger les sorties de caisse du restaurant.')
    if ((inc.data?.length ?? 0)>=100)
      throw Error('Trop de demandes en attente : liste tronquée. Enregistrement suspendu.')
    setApproved(inc.data ?? [])
    setRefunds(ledger.data ?? [])
    setTicket(old=>(inc.data ?? []).some(i=>i.id===old)?old:(inc.data?.[0]?.id??''))
  },[shopId])
  useEffect(()=>{
    let live=true
    void Promise.resolve().then(reload).catch(()=>{
      if (live) setError('Registre des remboursements indisponible.')
    }).finally(()=>{if(live)setLoading(false)})
    return ()=>{live=false}
  },[reload])
  useEffect(()=>{
    let live=true
    if(!ticket){void Promise.resolve().then(()=>{if(live)setQuote(null)});return ()=>{live=false}}
    void Promise.resolve().then(async()=>{
      const {data,error:fault}=await supabase.rpc('restaurant_cash_refund_quote',{
        p_shop:shopId,p_incident:ticket,
      })
      if(fault)throw fault
      if(live)setQuote(readQuote(data))
    }).catch(()=>{
      if(live){setQuote(null);setError('Plafond de remboursement non vérifiable : sortie interdite.')}
    })
    return ()=>{live=false}
  },[shopId,ticket,refunds])

  const eligible = approved.filter(i=>!refunds.some(r=>r.incident_id===i.id))
  const amountValid = /^\d{1,12}$/.test(amount) && BigInt(amount)>0n &&
    quote?.incidentId===ticket && BigInt(amount)<=BigInt(quote.maximumXaf)
  const canConfirm = amountValid && !busy && !loading && cashHanded &&
    reason.trim().length>=12 && reason.trim().length<=500 &&
    quote?.alreadyRefunded===false

  function resetForm() {
    setQuote(null);setAmount('');setReason('');setCashHanded(false)
    operation.current=crypto.randomUUID()
  }
  async function confirm(e:FormEvent<HTMLFormElement>) {
    e.preventDefault()
    if(!canConfirm||!quote)return
    setBusy(true);setError('');setNotice('')
    try{
      // Refresh the server-authoritative ceiling immediately before confirmation.
      const response=await supabase.rpc('restaurant_cash_refund_quote',{
        p_shop:shopId,p_incident:ticket,
      })
      if(response.error)throw response.error
      const fresh=readQuote(response.data)
      if(fresh.alreadyRefunded || BigInt(amount)>BigInt(fresh.maximumXaf) ||
        fresh.state!=='requires_refund_review')
        throw Error('Remboursement déjà enregistré ou plafond modifié.')
      const {data,error:fault}=await supabase.rpc('restaurant_confirm_cash_refund',{
        p_shop:shopId,p_incident:ticket,p_amount:Number(amount),
        p_reason:reason.trim(),p_operation_id:operation.current,p_cash_handed_over:true,
      })
      if(fault)throw fault
      if(!data || typeof data!=='object' || Array.isArray(data) ||
        data.confirmed!==true || typeof data.refundId!=='string')
        throw Error('Réponse inconnue : contrôlez le registre avant de recommencer.')
      // DB has confirmed cash handover. Reconciliation could still fail; don't reissue.
      resetForm()
      setNotice('Sortie de caisse en espèces confirmée dans le registre. Le paiement original est conservé.')
      try{await reload()}catch{
        setError('Remboursement enregistré, mais historique non actualisé. Ne recommencez pas.')
      }
    }catch(err){
      setError(err instanceof Error?err.message:'Opération refusée. Vérifiez le registre.')
    }finally{setBusy(false)}
  }
  const current=eligible.find(i=>i.id===ticket)
  return (
    <Sheet aria-label="Remboursements en espèces du restaurant">
      <h2 className="section-title">Remboursements en espèces</h2>
      <Notice tone="calm">
        <p>Réservé au propriétaire. Confirmez uniquement une somme <strong>déjà remise physiquement au client</strong>. Ce formulaire ne déclenche aucun virement, paiement mobile ou retour bancaire.</p>
        <p>La recette initiale reste enregistrée. Le remboursement apparaît séparément comme sortie d’espèces.</p>
      </Notice>
      {error&&<Notice tone="danger"><p>{error}</p></Notice>}
      {notice&&<Notice tone="success"><p>{notice}</p></Notice>}
      {loading?<p>Vérification du registre…</p>:eligible.length===0?
        <p className="muted">Aucun incident approuvé disponible pour un remboursement en espèces.</p>:
        <>
          <form className="form-grid" onSubmit={e=>void confirm(e)}>
            <label>Incident approuvé
              <select value={ticket} onChange={e=>{setTicket(e.target.value);resetForm()}}>
                {eligible.map(i=><option value={i.id} key={i.id}>
                  {i.description.slice(0,80)}</option>)}
              </select>
            </label>
            {current&&<p className="muted">{current.owner_note}</p>}
            {quote?.incidentId===ticket&&<>
              <p>Commande : <strong>{quote.orderReference??'—'}</strong></p>
              <p>Espèces encaissées : {xaf(quote.paidXaf)}</p>
              <p>Espèces déjà remboursées : {xaf(quote.refundedXaf)}</p>
              <p>Plafond encore autorisé pour cet incident : <strong>{xaf(quote.maximumXaf)}</strong></p>
            </>}
            <label>Montant réellement remis (FCFA)
              <input required type="text" inputMode="numeric" pattern="[0-9]*"
                value={amount} maxLength={12}
                onChange={e=>{setAmount(e.target.value.replace(/[^0-9]/g,''));setCashHanded(false);operation.current=crypto.randomUUID()}}
                placeholder="Ex. 1500"/>
            </label>
            <label>Justification de la sortie
              <textarea required minLength={12} maxLength={500} value={reason}
                onChange={e=>{setReason(e.target.value);setCashHanded(false);operation.current=crypto.randomUUID()}}
                placeholder="Montant remis au client, raison, personne présente"/>
            </label>
            <label>
              <input type="checkbox" checked={cashHanded}
                onChange={e=>setCashHanded(e.target.checked)}/>
              J’atteste avoir effectivement rendu ce montant en espèces au client.
            </label>
            <Button variant="primary" type="submit" busy={busy} disabled={!canConfirm}>
              Enregistrer l’argent déjà remboursé
            </Button>
          </form>
        </>}
      <h3 className="section-title">Dernières sorties enregistrées</h3>
      <p className="muted">Les 30 plus récentes. Ce tableau n’est pas un total comptable exhaustif.</p>
      {refunds.length===0?<p className="muted">Aucune sortie enregistrée.</p>:
        <ul className="team-invites">{refunds.map(r=><li key={r.id}>
          <div><strong>{xaf(String(r.amount_xaf))} — Espèces</strong>
            <p className="muted">{new Date(r.confirmed_at).toLocaleString('fr-FR')} · {r.reason}</p>
          </div>
        </li>)}</ul>}
    </Sheet>
  )
}
