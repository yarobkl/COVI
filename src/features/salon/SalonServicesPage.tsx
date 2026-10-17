import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { Button, PageHead, Sheet, Notice } from '../../components/ui'
import { money } from '../../lib/format'
import { supabase } from '../../lib/supabase'
import type { Tables } from '../../lib/database.types'

type Service = Tables<'salon_services'>

/** Services of this salon only; no clothing stock reused for appointment services. */
export function SalonServicesPage({ shopId }: { shopId: string }) {
  const [rows, setRows] = useState<Service[]>([])
  const [showForm, setShowForm] = useState(false)
  const [busy, setBusy] = useState(false)
  const [loading, setLoading] = useState(true)
  const [message, setMessage] = useState('')
  const [isError, setIsError] = useState(false)
  const reload = useCallback(async () => {
    const { data, error } = await supabase.from('salon_services')
      .select('*').eq('shop_id', shopId).order('name')
    if (error) throw error
    setRows(data ?? [])
  }, [shopId])
  useEffect(() => {
    let alive = true
    void supabase.from('salon_services').select('*').eq('shop_id', shopId).order('name')
      .then(({ data, error })=>{
        if(!alive) return
        setLoading(false)
        if(error) {setIsError(true);setMessage('Chargement impossible. La migration de la base est peut-être en attente.')}
        else setRows(data ?? [])
      })
    return ()=>{alive=false}
  }, [shopId])
  async function add(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const form=new FormData(e.currentTarget)
    const name=String(form.get('name')??'').trim()
    const price=Number(form.get('price'))
    const duration=Number(form.get('duration'))
    if(name.length<2 || !Number.isSafeInteger(price) || price<0 || price>1000000000
      || !Number.isInteger(duration) || duration<5 || duration>720) {
      setMessage('Vérifiez la prestation, son tarif et la durée.');setIsError(true);return
    }
    setBusy(true)
    try{
      const {error}=await supabase.from('salon_services').insert({
        shop_id:shopId,name,price_xaf:price,duration_minutes:duration
      })
      if(error)throw error
      await reload()
      setShowForm(false);setIsError(false);setMessage('Prestation ajoutée.')
    }catch{
      setIsError(true);setMessage('Enregistrement impossible.')
    }finally{setBusy(false)}
  }
  async function toggle(row: Service){
    if(busy)return
    setBusy(true)
    try{
      const {error}=await supabase.from('salon_services')
        .update({active:!row.active}).eq('id',row.id).eq('shop_id',shopId)
      if(error)throw error
      await reload();setIsError(false);setMessage('Prestation mise à jour.')
    }catch{setIsError(true);setMessage('Modification impossible.')}
    finally{setBusy(false)}
  }
  return <div className="page-stack">
    <PageHead title="Prestations" sub="Chaque salon choisit ses propres services, durées et prix."
      action={<Button onClick={()=>setShowForm(!showForm)}>{showForm?'Fermer':'Ajouter une prestation'}</Button>} />
    {showForm && <Sheet>
      <form className="form-grid" onSubmit={e=>void add(e)}>
        <label>Prestation<input name="name" required minLength={2} maxLength={120} placeholder="Ex. Tresses" /></label>
        <label>Prix en FCFA<input name="price" type="number" required min={0} step={1} max={1000000000}/></label>
        <label>Durée estimée en minutes<input name="duration" type="number" required min={5} max={720} step={5} defaultValue={45}/></label>
        <Button type="submit" variant="primary" busy={busy}>Enregistrer</Button>
      </form>
    </Sheet>}
    {message && <Notice tone={isError?'danger':'success'}><p>{message}</p></Notice>}
    <Sheet aria-label="Liste des prestations">
      {loading?<p>Chargement des prestations…</p>:rows.length===0?<p className="muted">Aucune prestation enregistrée.</p>:
        <ul className="team-invites">{rows.map(s=><li key={s.id}>
          <div><strong>{s.name}</strong><p className="muted">{money(s.price_xaf)} · {s.duration_minutes} min {!s.active&&'· indisponible'}</p></div>
          <Button disabled={busy} onClick={()=>void toggle(s)}>{s.active?'Masquer':'Réactiver'}</Button>
        </li>)}</ul>}
    </Sheet>
  </div>
}
