// COVI Restaurant guest write gateway — must remain OFF by default.
// QR alone cannot join a group: Turnstile + rotating 8-digit session code required.
// Guests never receive JWTs, shop IDs, staff information or service-role credentials.
const QR=/^[a-f0-9]{64}$/
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const jsonHeaders={ 'content-type':'application/json; charset=utf-8',
  'cache-control':'no-store','x-content-type-options':'nosniff','vary':'Origin' }
function reply(status,body,origin) {
  return new Response(JSON.stringify(body),{status,
    headers:{...jsonHeaders,...(origin?{'access-control-allow-origin':origin}:{})}})
}
function origins(value) {
 return String(value??'').split(',').map(x=>x.trim()).filter(x=>{
  try {const u=new URL(x);return u.origin===x && (u.protocol==='https:' || u.hostname==='localhost')}
  catch {return false}
 })
}
function sourceAddress(req) {
 const v=req.headers.get('cf-connecting-ip')||req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()
 return v && v.length<=64 && /^[0-9a-f:.]+$/i.test(v)?v:'unknown'
}
async function digest(pepper,info) {
 const k=await crypto.subtle.importKey('raw',new TextEncoder().encode(pepper),
   {name:'HMAC',hash:'SHA-256'},false,['sign'])
 const b=await crypto.subtle.sign('HMAC',k,new TextEncoder().encode(info))
 return Array.from(new Uint8Array(b)).map(x=>x.toString(16).padStart(2,'0')).join('')
}
function headers(env) {
 const k=env.SUPABASE_SERVICE_ROLE_KEY
 return {apikey:k,'content-type':'application/json',
  ...(k.startsWith('eyJ')?{authorization:'Bearer '+k}:{})}
}
async function rpc(env,fetcher,name,body) {
 const res=await fetcher(new URL('/rest/v1/rpc/'+name,env.SUPABASE_URL),
  {method:'POST',headers:headers(env),body:JSON.stringify(body)})
 if (!res.ok) {
  let detail=''
  try { const result=await res.json(); detail=String(result?.message??'') }catch{}
  const e=new Error(detail||'Backend unavailable')
  e.httpStatus=res.status
  throw e
 }
 return res.json()
}
async function jsonLimited(request) {
 const size=Number(request.headers.get('content-length'))
 if(Number.isFinite(size)&&size>4096) throw new Error('Invalid payload')
 const reader=request.body?.getReader()
 if(!reader)throw new Error('Invalid payload')
 let sizeRead=0;const parts=[]
 while(true){
  const {done,value}=await reader.read()
  if(done)break
  sizeRead+=value.byteLength
  if(sizeRead>4096){await reader.cancel();throw new Error('Invalid payload')}
  parts.push(value)
 }
 const data=new Uint8Array(sizeRead)
 let offset=0;for(const part of parts){data.set(part,offset);offset+=part.length}
 const body=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(data))
 if(!body||typeof body!=='object'||Array.isArray(body))throw new Error('Invalid payload')
 return body
}
async function verifyChallenge(env,fetcher,token,hosts) {
 const r=await fetcher('https://challenges.cloudflare.com/turnstile/v0/siteverify',{
  method:'POST',
  body:new URLSearchParams({secret:env.COVI_TURNSTILE_SECRET,response:token}),
 })
 if(!r.ok)return false
 const d=await r.json()
 return d?.success===true && hosts.includes(d.hostname) &&
  d.action==='covi_restaurant_join'
}
function safeGuestResult(action,data){
 if(action==='join'){
  if(!QR.test(data?.participantToken)||!UUID.test(data?.participantId))return null
  return {participantToken:data.participantToken,
    participantId:data.participantId,isLeader:false,ready:false}
 }
 if(action==='choice'){
  if(data?.saved!==true||data?.ready!==false)return null
  return {saved:true,ready:false}
 }
 if(action==='ready'){
  if(typeof data?.isLeader!=='boolean'||data?.ready!==true||
     !Number.isInteger(data?.participants)||!Number.isInteger(data?.readyParticipants))
   return null
  return {isLeader:data.isLeader,ready:true,
   participants:data.participants,readyParticipants:data.readyParticipants}
 }
 if(action==='status'){
  if(!data)return {expired:true}
  if(typeof data.isLeader!=='boolean'||typeof data.ready!=='boolean'||
     !Number.isInteger(data.participants)||!Number.isInteger(data.readyParticipants)||
     !Array.isArray(data.lines)||data.lines.length>300)return null
  for(const l of data.lines)if(!UUID.test(l.itemId)||typeof l.name!=='string'||
   !Number.isInteger(l.quantity)||!Number.isSafeInteger(l.unitPriceXaf)||
   typeof l.mine!=='boolean')return null
  if (!['collecting','submitted'].includes(data.groupStatus) ||
      (data.orderReference !== null &&
       (typeof data.orderReference !== 'string' || !/^CMD-[0-9]{6,20}$/.test(data.orderReference))))return null
  return {groupStatus:data.groupStatus,orderReference:data.orderReference,
   isLeader:data.isLeader,ready:data.ready,
   participants:data.participants,readyParticipants:data.readyParticipants,
   lines:data.lines.map(l=>({itemId:l.itemId,name:l.name,quantity:l.quantity,
    unitPriceXaf:l.unitPriceXaf,mine:l.mine}))}
 }
 if(action==='submit'){
  if(typeof data!=='string'||!/^CMD-[0-9]{6,20}$/.test(data))return null
  return {reference:data,submitted:true}
 }
 return null
}
export function createRestaurantGuestGateway(env,fetcher=fetch) {
 const allowed=origins(env.COVI_PUBLIC_ORIGIN)
 let apiOk=false
 try{const u=new URL(env.SUPABASE_URL);apiOk=u.protocol==='https:'&&u.pathname==='/'}catch{}
 const enabled=env.COVI_RESTAURANT_GUEST_ENABLED==='true'&&
  apiOk&&allowed.length>0&&String(env.SUPABASE_SERVICE_ROLE_KEY??'').length>30&&
  String(env.COVI_GATEWAY_PEPPER??'').length>=32&&
  String(env.COVI_TURNSTILE_SECRET??'').length>=16
 const hosts=allowed.map(x=>new URL(x).hostname)
 return async(request)=>{
  const inputOrigin=request.headers.get('origin')
  const origin=inputOrigin&&allowed.includes(inputOrigin)?inputOrigin:null
  if(!origin)return reply(403,{error:'Origine interdite.'},null)
  if(request.method==='OPTIONS')
   return new Response(null,{status:204,headers:{
    'access-control-allow-origin':origin,
    'access-control-allow-methods':'POST, OPTIONS',
    'access-control-allow-headers':'content-type, apikey, authorization, x-client-info',
    'access-control-max-age':'600',vary:'Origin'}})
  if(request.method!=='POST')return reply(405,{error:'Méthode interdite.'},origin)
  if(!enabled)return reply(503,{error:'Le panier collectif n’est pas encore activé.'},origin)
  try {
   const body=await jsonLimited(request)
   const action=body.action
   const qr=body.table
   if(!['join','choice','ready','status','submit'].includes(action)||
    typeof qr!=='string'||!QR.test(qr))
    return reply(400,{error:'Demande invalide.'},origin)
   const isJoin=action==='join'
   if(isJoin){
    if(typeof body.code!=='string'||!(/^[A-F0-9]{8}$/).test(body.code)||
       typeof body.challenge!=='string'||body.challenge.length<10||
       body.challenge.length>4096)return reply(400,{error:'Code ou vérification invalide.'},origin)
   } else if(typeof body.participantToken!=='string'||!QR.test(body.participantToken)){
    return reply(400,{error:'Session expirée. Demandez l’aide du personnel.'},origin)
   }
   if(action==='choice'&&
      (!UUID.test(body.itemId??'')||
       !Number.isSafeInteger(body.quantity)||body.quantity<0||body.quantity>100))
    return reply(400,{error:'Article ou quantité invalide.'},origin)
   // Separate, committed backend RPC: failed guesses consume quota too.
   const limited=await rpc(env,fetcher,'restaurant_guest_rate_gate',{
    p_source_hmac:await digest(env.COVI_GATEWAY_PEPPER,'src:'+sourceAddress(request)),
    p_qr_hmac:await digest(env.COVI_GATEWAY_PEPPER,'qr:'+qr),
    p_operation:isJoin?'join':'guest',
   })
   if(limited!==true)return reply(429,{error:'Trop de tentatives. Réessayez plus tard.'},origin)
   if(isJoin&&!(await verifyChallenge(env,fetcher,body.challenge,hosts)))
    return reply(403,{error:'Vérification anti-robot refusée.'},origin)
   const params= isJoin?{p_qr:qr,p_join_code:body.code}:
    action==='choice'?{p_qr:qr,p_secret:body.participantToken,p_item:body.itemId,p_quantity:body.quantity}:
    {p_qr:qr,p_secret:body.participantToken}
   const rpcName={
    join:'restaurant_guest_join',choice:'restaurant_guest_choose_item',
    ready:'restaurant_guest_mark_ready',status:'restaurant_guest_status',
    submit:'restaurant_guest_submit',
   }[action]
   const data=await rpc(env,fetcher,rpcName,params)
   const result=safeGuestResult(action,data)
   return result?reply(200,result,origin):
    reply(503,{error:'Réponse du restaurant momentanément indisponible.'},origin)
  }catch(e){
   if(e?.message==='Invalid payload'||e instanceof SyntaxError)
    return reply(400,{error:'Demande invalide.'},origin)
   const reason=String(e?.message??'')
   const status=/limit|Too many|Too many actions/i.test(reason)?429:
    /Invalid|expired|Only the group leader|participant|Waiting|Item unavailable|Drink unavailable|Empty order|Session|Table|Group already/i.test(reason)?409:503
   return reply(status,{error:status===429?'Trop de tentatives. Réessayez plus tard.':
    status===409?'La commande a changé ou l’accès au groupe a expiré. Actualisez la page.':
    'Le service restaurant est momentanément indisponible.'},origin)
  }
 }
}
