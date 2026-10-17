import { useCallback, useEffect, useState } from 'react'
import { Button, Notice, Sheet } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import type { Tables } from '../../lib/database.types'

type Event = Tables<'restaurant_staff_events'>
type Staff = Tables<'restaurant_staff_members'>

const eventLabels: Record<string,string> = {
  member_joined:'Employé inscrit',
  member_disabled:'Accès désactivé',
  table_opened:'Table ouverte',
  group_code_issued:'Code de groupe généré',
  line_added:'Article ajouté',
  line_served:'Article servi',
  payment_confirmed:'Encaissement confirmé',
}
const pageSize=50

/** Complete paginated private audit; every page is authorized by server RLS. */
export function RestaurantStaffAudit({ shopId }: { shopId: string }) {
  const [events,setEvents]=useState<Event[]>([])
  const [staff,setStaff]=useState<Staff[]>([])
  const [more,setMore]=useState(false)
  const [loading,setLoading]=useState(true)
  const [busy,setBusy]=useState(false)
  const [error,setError]=useState('')
  const [search,setSearch]=useState('')

  const fetchPage=useCallback(async(start:number)=>{
    const {data,error:fetchError}=await supabase.from('restaurant_staff_events')
      .select('*').eq('shop_id',shopId)
      .order('id',{ascending:false}).range(start,start+pageSize-1)
    if(fetchError)throw fetchError
    return data??[]
  },[shopId])
  useEffect(()=>{
    let active=true
    void Promise.all([
      fetchPage(0),
      supabase.from('restaurant_staff_members').select('*')
        .eq('shop_id',shopId).order('created_at').limit(500),
    ]).then(([history,members])=>{
      if(!active)return
      if(members.error || (members.data?.length??0)>=500)
        setError('Annuaire incomplet : identité des intervenants non vérifiable.')
      else setStaff(members.data??[])
      setEvents(history)
      setMore(history.length===pageSize)
    }).catch(()=>{
      if(active)setError('Historique indisponible. Réessayez ultérieurement.')
    }).finally(()=>{if(active)setLoading(false)})
    return ()=>{active=false}
  },[fetchPage,shopId])

  async function next(){
    if(busy||!more)return
    setBusy(true);setError('')
    try{
      const rows=await fetchPage(events.length)
      setEvents(prev=>[...prev,...rows])
      setMore(rows.length===pageSize)
    }catch{setError('Page suivante indisponible.')}
    finally{setBusy(false)}
  }
  const visible=events.filter(event=>{
    const q=search.trim().toLowerCase()
    if(!q)return true
    const name=staff.find(m=>m.user_id===event.actor_user_id)?.display_name??''
    return name.toLowerCase().includes(q) ||
      event.event_type.toLowerCase().includes(q) ||
      (event.session_id??'').toLowerCase().includes(q)
  })
  return <Sheet aria-label="Historique privé du restaurant">
    <h2 className="section-title">Historique des interventions</h2>
    <p className="muted">Visible uniquement par le propriétaire. Chaque événement est lié au compte réel qui l’a effectué.</p>
    <label>Filtrer les événements déjà chargés
      <input value={search} onChange={e=>setSearch(e.target.value)}
        placeholder="Nom, opération ou identifiant de session"/>
    </label>
    {error&&<Notice tone="danger"><p>{error}</p></Notice>}
    {loading?<p>Lecture du journal…</p>:visible.length===0?
      <p className="muted">Aucun événement pour ce filtre.</p>:
      <ul className="team-invites">{visible.map(event=>{
        const actor=staff.find(m=>m.user_id===event.actor_user_id)
        return <li key={event.id}>
          <div>
            <strong>{eventLabels[event.event_type]??event.event_type}</strong>
            <p className="muted">{actor?.display_name??'Propriétaire ou intervenant non répertorié'}
              {' · '}{new Date(event.occurred_at).toLocaleString('fr-FR')}</p>
            {event.session_id&&<p className="muted">Session : {event.session_id}</p>}
          </div>
        </li>
      })}</ul>}
    {more&&<Button disabled={busy} onClick={()=>void next()}>Charger 50 interventions supplémentaires</Button>}
  </Sheet>
}
