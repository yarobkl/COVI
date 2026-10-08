
export type PendingSale={id:string;shopId:string;productId:string;quantity:number;soldUnitPrice:number;paymentLabel:string;createdAt:string;attempts:number;lastError?:string}
const KEY='covi:pending-sales:v1'
const REJECTED_KEY='covi:rejected-sales:v1'
export const rejectedSaleCount=()=>Number(localStorage.getItem(REJECTED_KEY)||0)
export function clearRejectedSaleCount(){localStorage.removeItem(REJECTED_KEY);window.dispatchEvent(new Event('covi-sync'))}
const read=():PendingSale[]=>{try{return JSON.parse(localStorage.getItem(KEY)||'[]')}catch{return[]}}
const write=(x:PendingSale[])=>localStorage.setItem(KEY,JSON.stringify(x))
export const pendingSales=()=>read()
export const pendingCount=()=>read().length
export function queueSale(input:Omit<PendingSale,'id'|'createdAt'|'attempts'>,operationId=crypto.randomUUID()){const x:PendingSale={...input,id:operationId,createdAt:new Date().toISOString(),attempts:0};write([...read(),x]);reserveOfflineStock(input.shopId,input.productId,input.quantity);window.dispatchEvent(new Event('covi-sync'));return x}
let syncInProgress=false,retryDelay=0,retryAt=0,retryTimer:ReturnType<typeof setTimeout>|undefined
// Network-like failures (server down, expired JWT while navigator.onLine is true) back off exponentially: 5 s, 10 s, 20 s… capped at 5 min, with a single pending retry timer.
const RETRY_BASE_MS=5000,RETRY_MAX_MS=300000
export const nextSyncRetryAt=()=>retryAt
function resetSyncBackoff(){retryDelay=0;retryAt=0;if(retryTimer!==undefined){clearTimeout(retryTimer);retryTimer=undefined}}
function scheduleSyncRetry(){retryDelay=retryDelay?Math.min(retryDelay*2,RETRY_MAX_MS):RETRY_BASE_MS;retryAt=Date.now()+retryDelay;if(retryTimer!==undefined)clearTimeout(retryTimer);retryTimer=setTimeout(()=>{retryTimer=undefined;void syncPendingSales()},retryDelay)}
if(typeof window!=='undefined')window.addEventListener('online',resetSyncBackoff)
export async function syncPendingSales(){if(!navigator.onLine||syncInProgress||Date.now()<retryAt)return{synced:0,pending:read().length,rejected:0};syncInProgress=true;let q=read(),synced=0,rejected=0,failed=false;try{for(const item of[...q]){try{const{recordSale}=await import('./covi');await recordSale(item.shopId,item.productId,item.quantity,item.soldUnitPrice,item.paymentLabel,item.id);q=q.filter(x=>x.id!==item.id);write(q);synced++}catch(e:any){const message=String(e?.message||'Erreur de synchronisation'),network=/fetch|network|offline|failed to fetch|timeout|jwt|token|unauthorized|401|not authenticated/i.test(message);if(network){q=q.map(x=>x.id===item.id?{...x,attempts:x.attempts+1,lastError:message}:x);write(q);failed=true;break}q=q.filter(x=>x.id!==item.id);write(q);restoreOfflineStock(item.shopId,item.productId,item.quantity);rejected++;localStorage.setItem(REJECTED_KEY,String(rejectedSaleCount()+1));}}}finally{syncInProgress=false;if(failed)scheduleSyncRetry();else resetSyncBackoff();if(synced||rejected)window.dispatchEvent(new Event('covi-sync'))}return{synced,pending:q.length,rejected}}
export async function resilientSale(input:{shopId:string;productId:string;quantity:number;soldUnitPrice:number;paymentLabel:string}){const operationId=crypto.randomUUID();if(!navigator.onLine){assertOfflineStock(input.shopId,input.productId,input.quantity);queueSale(input,operationId);return{offline:true}}try{const{recordSale}=await import('./covi');await recordSale(input.shopId,input.productId,input.quantity,input.soldUnitPrice,input.paymentLabel,operationId);return{offline:false}}catch(e:any){const network=/fetch|network|offline|failed to fetch/i.test(String(e?.message||e));if(!network)throw e;assertOfflineStock(input.shopId,input.productId,input.quantity);queueSale(input,operationId);return{offline:true}}}

const stockKey=(shopId:string)=>'covi:stock:'+shopId
export function cachedStock<T>(shopId:string):T[]{try{return JSON.parse(localStorage.getItem(stockKey(shopId))||'[]')}catch{return[]}}
export function cacheStock<T>(shopId:string,products:T[]){localStorage.setItem(stockKey(shopId),JSON.stringify(products));localStorage.setItem(stockKey(shopId)+':at',new Date().toISOString())}
export function stockCacheDate(shopId:string){return localStorage.getItem(stockKey(shopId)+':at')}

function assertOfflineStock(shopId:string,productId:string,quantity:number){const p=cachedStock<any>(shopId).find(x=>x.id===productId);if(!p)throw new Error('Produit absent du stock hors connexion. Reconnectez-vous pour actualiser le stock.');if(Number(p.quantity_on_hand)<quantity)throw new Error('Stock hors connexion insuffisant pour cette vente.')}
function reserveOfflineStock(shopId:string,productId:string,quantity:number){const rows=cachedStock<any>(shopId),next=rows.map(p=>p.id===productId?{...p,quantity_on_hand:Math.max(0,Number(p.quantity_on_hand)-quantity),status:Number(p.quantity_on_hand)-quantity<=0?'sold':p.status}:p);cacheStock(shopId,next)}

function restoreOfflineStock(shopId:string,productId:string,quantity:number){const rows=cachedStock<any>(shopId);cacheStock(shopId,rows.map(p=>p.id===productId?{...p,quantity_on_hand:Number(p.quantity_on_hand)+quantity,status:'active'}:p))}
