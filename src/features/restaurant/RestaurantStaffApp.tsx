import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from 'react'
import { Button, Notice, Sheet } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import type { RestaurantStaffSpace } from '../../lib/restaurantStaff'

type RoomTable = { id: string; name: string; capacity: number }
type RoomSession = {
  id: string
  tableId: string
  state: 'collecting' | 'submitted'
  orderReference: string | null
  guests: number
}
type RoomLine = {
  id: string
  sessionId: string
  itemId: string
  name: string
  quantity: number
  state: 'draft' | 'ordered' | 'served'
  unitPriceXaf: number | null
}
type RoomMenu = { id: string; name: string; priceXaf: number | null; available: boolean; kind: string }
type RoomPayment = { sessionId: string; amountXaf: number }
type Room = {
  role: 'owner' | 'waiter' | 'kitchen' | 'cashier'
  tables: RoomTable[]
  sessions: RoomSession[]
  lines: RoomLine[]
  menu: RoomMenu[]
  payments: RoomPayment[]
}
const money = (amount: bigint) =>
  new Intl.NumberFormat('fr-FR').format(amount) + ' FCFA'
const safe = (n: unknown): n is number => typeof n === 'number' && Number.isSafeInteger(n) && n >= 0
const uuid = (s: unknown): s is string => typeof s === 'string' &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s)

/** Fail closed: an incomplete response must never produce a payable bill. */
function readRoom(data: unknown): Room {
  if (!data || typeof data !== 'object' || Array.isArray(data)) throw Error('Réponse de salle invalide.')
  const x = data as Partial<Room>
  if (!['waiter', 'kitchen', 'cashier', 'owner'].includes(String(x.role)) ||
      !Array.isArray(x.tables) || !Array.isArray(x.sessions) ||
      !Array.isArray(x.lines) || !Array.isArray(x.menu) || !Array.isArray(x.payments) ||
      x.tables.length>500 || x.sessions.length>500 ||
      x.lines.length>5000 || x.menu.length>5000 || x.payments.length>5000)
    throw Error('Données incomplètes : opérations désactivées.')
  if (x.tables.some(t=>!uuid(t.id)||typeof t.name!=='string'||!safe(t.capacity)) ||
      x.sessions.some(s=>!uuid(s.id)||!uuid(s.tableId)||!['collecting','submitted'].includes(s.state) ||
        (s.orderReference!==null&&typeof s.orderReference!=='string')||!safe(s.guests)) ||
      x.lines.some(l=>!uuid(l.id)||!uuid(l.sessionId)||!uuid(l.itemId)||
        typeof l.name!=='string'||!safe(l.quantity)||!['draft','ordered','served'].includes(l.state)||
        (l.unitPriceXaf!==null&&!safe(l.unitPriceXaf))) ||
      x.menu.some(m=>!uuid(m.id)||typeof m.name!=='string'||typeof m.available!=='boolean'||
        (m.priceXaf!==null&&!safe(m.priceXaf))) ||
      x.payments.some(p=>!uuid(p.sessionId)||!safe(p.amountXaf)))
    throw Error('Données financières non vérifiables : opérations désactivées.')
  return x as Room
}

const roleName = { waiter:'Service en salle', kitchen:'Cuisine', cashier:'Caisse' } as const

/** Separate application for employees: no owner settings, salaries, or audit access. */
export function RestaurantStaffApp({
  space,
  signOut,
  onSwitch,
  onLostAccess,
}: {
  space: RestaurantStaffSpace
  signOut: () => Promise<void>
  onSwitch?: () => void
  onLostAccess: () => void
}) {
  const [room,setRoom]=useState<Room|null>(null)
  const [tableId,setTableId]=useState('')
  const [sessionId,setSessionId]=useState('')
  const [menuId,setMenuId]=useState('')
  const [people,setPeople]=useState(2)
  const [qty,setQty]=useState(1)
  const [received,setReceived]=useState('')
  const [cashConfirmed,setCashConfirmed]=useState(false)
  const [joiningCode,setJoiningCode]=useState('')
  const [busy,setBusy]=useState(false)
  const [error,setError]=useState('')
  const [notice,setNotice]=useState('')
  const [loading,setLoading]=useState(true)
  const paymentId=useRef(crypto.randomUUID())
  const shopId=space.shop_id

  const refresh=useCallback(async()=>{
    const {data,error:rpcError}=await supabase.rpc('restaurant_staff_room',{p_shop:shopId})
    if(rpcError)throw rpcError
    const valid=readRoom(data)
    if(valid.role!==space.staff_role)throw Error('Autorisation modifiée. Reconnectez-vous.')
    setRoom(valid)
    setSessionId(prev=>valid.sessions.some(s=>s.id===prev)?prev:valid.sessions[0]?.id??'')
    setTableId(prev=>valid.tables.some(t=>t.id===prev)?prev:valid.tables[0]?.id??'')
    setMenuId(prev=>valid.menu.some(m=>m.id===prev)?prev:valid.menu[0]?.id??'')
    setLoading(false)
  },[shopId,space.staff_role])
  useEffect(()=>{
    let active=true
    const sync=async()=>{
      try{await refresh();if(active)setError('')}
      catch{
        if(active){setRoom(null);setLoading(false);setError('Accès ou données indisponibles. Aucune opération n’est autorisée.')}
      }
    }
    void Promise.resolve().then(sync)
    const timer=window.setInterval(()=>{void sync()},10000)
    return()=>{active=false;window.clearInterval(timer)}
  },[refresh])
  async function run(action:()=>Promise<unknown>,success:string) {
    if(busy || !room)return
    setBusy(true);setError('');setNotice('')
    try {
      await action()
      try{await refresh();setNotice(success)}
      catch {
        setRoom(null)
        setNotice('Action enregistrée, mais affichage non actualisé.')
        setError('Vérifiez l’historique auprès du responsable avant de répéter une opération.')
      }
    }catch(e){
      setError(e instanceof Error ? e.message : 'Opération refusée.')
      const value=e as {code?:string}
      if(value?.code==='42501')onLostAccess()
    }finally{setBusy(false)}
  }
  const active=room?.sessions.find(s=>s.id===sessionId)
  const current=useMemo(()=>room?.lines.filter(l=>l.sessionId===sessionId)??[],[room,sessionId])
  const total=current.filter(l=>l.state!=='draft').reduce((n,l)=>
    n+BigInt(l.quantity)*BigInt(l.unitPriceXaf??0),0n)
  const paid=(room?.payments.filter(p=>p.sessionId===sessionId)??[])
    .reduce((n,p)=>n+BigInt(p.amountXaf),0n)
  const remaining=total-paid
  const cashAmount=Number(received)
  const canCash=room?.role==='cashier'&&active?.state==='submitted'&&remaining>0n &&
    Number.isSafeInteger(cashAmount)&&cashAmount>0&&BigInt(cashAmount)<=remaining
  async function openTable(e:FormEvent<HTMLFormElement>){
    e.preventDefault()
    if(!tableId || !Number.isInteger(people)||people<1||people>50)return
    await run(async()=>{
      const {error:rpcError}=await supabase.rpc('restaurant_open_table',{
        p_shop:shopId,p_table:tableId,p_guest_count:people,
      })
      if(rpcError)throw rpcError
    },'Table ouverte pour ce groupe.')
  }
  async function issueCode(){
    if(!active)return
    await run(async()=>{
      const {data,error:rpcError}=await supabase.rpc('restaurant_issue_group_code',{
        p_shop:shopId,p_session:active.id,
      })
      if(rpcError)throw rpcError
      setJoiningCode(data??'')
    },'Code de groupe généré. Donnez-le seulement aux clients présents.')
  }
  async function addItem(e:FormEvent<HTMLFormElement>){
    e.preventDefault()
    if(!active||!menuId||!Number.isInteger(qty)||qty<1||qty>100)return
    await run(async()=>{
      const {error:rpcError}=await supabase.rpc('restaurant_staff_add_item',{
        p_shop:shopId,p_session:active.id,p_item:menuId,p_quantity:qty,
      })
      if(rpcError)throw rpcError
    },'Complément ajouté à la même addition.')
  }
  async function served(lineId:string){
    await run(async()=>{
      const {error:rpcError}=await supabase.rpc('restaurant_mark_served',{
        p_shop:shopId,p_line:lineId,
      })
      if(rpcError)throw rpcError
    },'Service enregistré. L’administrateur retrouvera votre intervention.')
  }
  async function cash(e:FormEvent<HTMLFormElement>){
    e.preventDefault()
    if(!cashConfirmed||!canCash||!active)return
    await run(async()=>{
      const {error:rpcError}=await supabase.rpc('restaurant_capture_cash',{
        p_shop:shopId,p_session:active.id,p_amount:cashAmount,p_operation_id:paymentId.current,
      })
      if(rpcError)throw rpcError
      paymentId.current=crypto.randomUUID()
      setCashConfirmed(false);setReceived('')
    },'Espèces enregistrées. La table est libérée seulement après règlement intégral.')
  }

  return <div className="cashier">
    <header className="cashier__top">
      <div><p className="cashier__shop">{space.shop_name}</p>
        <p className="cashier__who">{roleName[space.staff_role]} · <b>{space.display_name}</b></p>
      </div>
      {onSwitch&&<Button onClick={onSwitch}>Changer d’espace</Button>}
      <Button variant="ghost" onClick={()=>void signOut()}>Se déconnecter</Button>
    </header>
    <main className="cashier__page seyes margin-rule" id="contenu">
      <h1 className="section-title">Service du restaurant</h1>
      {error&&<Notice tone="danger"><p>{error}</p></Notice>}
      {notice&&<Notice tone="success"><p>{notice}</p></Notice>}
      {loading?<p role="status">Vérification de votre accès…</p>:room&&<>
        <Sheet>
          <h2 className="section-title">Tables en cours</h2>
          {room.sessions.length===0?<p>Aucune addition ouverte.</p>:
            <label>Choisir la table
              <select value={sessionId} onChange={e=>{setSessionId(e.target.value);setJoiningCode('');setReceived('');setCashConfirmed(false)}}>
                {room.sessions.map(s=><option key={s.id} value={s.id}>
                  Table {room.tables.find(t=>t.id===s.tableId)?.name??'—'}
                  {' · '}{s.orderReference??'Choix en cours'}
                </option>)}
              </select>
            </label>}
        </Sheet>
        {space.staff_role==='waiter'&&<Sheet>
          <h2 className="section-title">Service en salle</h2>
          <form className="form-grid" onSubmit={e=>void openTable(e)}>
            <label>Table disponible
              <select value={tableId} onChange={e=>setTableId(e.target.value)}>
                {room.tables.filter(t=>!room.sessions.some(s=>s.tableId===t.id)).map(t=>
                  <option key={t.id} value={t.id}>Table {t.name} · {t.capacity} places</option>)}
              </select>
            </label>
            <label>Personnes présentes
              <input type="number" min={1} max={50} value={people} onChange={e=>setPeople(Number(e.target.value))}/>
            </label>
            <Button type="submit" variant="primary" busy={busy}>Ouvrir la table</Button>
          </form>
          {active?.state==='collecting'&&<>
            <Button disabled={busy} onClick={()=>void issueCode()}>Code temporaire pour ce groupe</Button>
            {joiningCode&&<Notice tone="calm"><p>Code à communiquer : <strong>{joiningCode}</strong></p>
              <p>Code réservé aux clients présents. Il ne remplace pas le QR imprimé.</p></Notice>}
          </>}
          {active?.state==='submitted'&&<form className="form-grid" onSubmit={e=>void addItem(e)}>
            <h3 className="section-title">Ajouter à l’addition</h3>
            <label>Article
              <select value={menuId} onChange={e=>setMenuId(e.target.value)}>
                {room.menu.map(m=><option key={m.id} value={m.id}>{m.name}
                  {' · '}{money(BigInt(m.priceXaf??0))}</option>)}
              </select>
            </label>
            <label>Quantité
              <input type="number" min={1} max={100} value={qty} onChange={e=>setQty(Number(e.target.value))}/>
            </label>
            <Button type="submit" disabled={busy} variant="primary">Ajouter</Button>
          </form>}
        </Sheet>}
        {(space.staff_role==='waiter'||space.staff_role==='kitchen')&&<Sheet>
          <h2 className="section-title">Préparation et service</h2>
          {current.length===0?<p className="muted">Aucun plat sur cette table.</p>:
            <ul className="team-invites">{current.filter(l=>l.state!=='draft').map(l=>
              <li key={l.id}>
                <div><strong>{l.quantity} × {l.name}</strong><p className="muted">{l.state==='served'?'Servi':'À préparer / servir'}</p></div>
                {l.state==='ordered'&&<Button disabled={busy} onClick={()=>void served(l.id)}>Marquer servi</Button>}
              </li>)}</ul>}
        </Sheet>}
        {space.staff_role==='cashier'&&<Sheet>
          <h2 className="section-title">Caisse</h2>
          {active?.state!=='submitted'?<p>Attendez la commande validée.</p>:<>
            <p>Commande : <strong>{active.orderReference}</strong></p>
            <p>Total : <strong>{money(total)}</strong></p>
            <p>Déjà encaissé : {money(paid)}</p>
            <p>Reste à encaisser : <strong>{money(remaining)}</strong></p>
            <form className="form-grid" onSubmit={e=>void cash(e)}>
              <label>Espèces réellement reçues (FCFA)
                <input type="number" required min={1} step={1} value={received}
                  onChange={e=>{setReceived(e.target.value);setCashConfirmed(false)}}/>
              </label>
              <label><input type="checkbox" checked={cashConfirmed}
                onChange={e=>setCashConfirmed(e.target.checked)}/>
                Je confirme avoir reçu ce montant en espèces
              </label>
              <Button variant="primary" type="submit" busy={busy} disabled={!canCash||!cashConfirmed}>
                Enregistrer l’encaissement
              </Button>
            </form>
          </>}
        </Sheet>}
      </>}
    </main>
  </div>
}
