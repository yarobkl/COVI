
export type PendingSale={id:string;shopId:string;productId:string;quantity:number;soldUnitPrice:number;paymentLabel:string;createdAt:string;attempts:number;lastError?:string}
const KEY='covi:pending-sales:v1'
const read=():PendingSale[]=>{try{return JSON.parse(localStorage.getItem(KEY)||'[]')}catch{return[]}}
const write=(x:PendingSale[])=>localStorage.setItem(KEY,JSON.stringify(x))
export const pendingSales=()=>read()
export const pendingCount=()=>read().length
export function queueSale(input:Omit<PendingSale,'id'|'createdAt'|'attempts'>,operationId=crypto.randomUUID()){const x:PendingSale={...input,id:operationId,createdAt:new Date().toISOString(),attempts:0};write([...read(),x]);reserveOfflineStock(input.shopId,input.productId,input.quantity);window.dispatchEvent(new Event('covi-sync'));return x}
export async function syncPendingSales(){if(!navigator.onLine)return{synced:0,pending:read().length};let q=read(),synced=0;for(const item of[...q]){try{const{recordSale}=await import('./covi');await recordSale(item.shopId,item.productId,item.quantity,item.soldUnitPrice,item.paymentLabel,item.id);q=q.filter(x=>x.id!==item.id);write(q);synced++}catch(e:any){q=q.map(x=>x.id===item.id?{...x,attempts:x.attempts+1,lastError:e?.message||'Erreur de synchronisation'}:x);write(q);break}}window.dispatchEvent(new Event('covi-sync'));return{synced,pending:q.length}}
export async function resilientSale(input:{shopId:string;productId:string;quantity:number;soldUnitPrice:number;paymentLabel:string}){const operationId=crypto.randomUUID();if(!navigator.onLine){assertOfflineStock(input.shopId,input.productId,input.quantity);queueSale(input,operationId);return{offline:true}}try{const{recordSale}=await import('./covi');await recordSale(input.shopId,input.productId,input.quantity,input.soldUnitPrice,input.paymentLabel,operationId);return{offline:false}}catch(e:any){const network=/fetch|network|offline|failed to fetch/i.test(String(e?.message||e));if(!network)throw e;assertOfflineStock(input.shopId,input.productId,input.quantity);queueSale(input,operationId);return{offline:true}}}

const stockKey=(shopId:string)=>'covi:stock:'+shopId
export function cachedStock<T>(shopId:string):T[]{try{return JSON.parse(localStorage.getItem(stockKey(shopId))||'[]')}catch{return[]}}
export function cacheStock<T>(shopId:string,products:T[]){localStorage.setItem(stockKey(shopId),JSON.stringify(products));localStorage.setItem(stockKey(shopId)+':at',new Date().toISOString())}
export function stockCacheDate(shopId:string){return localStorage.getItem(stockKey(shopId)+':at')}

function assertOfflineStock(shopId:string,productId:string,quantity:number){const p=cachedStock<any>(shopId).find(x=>x.id===productId);if(!p)throw new Error('Produit absent du stock hors connexion. Reconnectez-vous pour actualiser le stock.');if(Number(p.quantity_on_hand)<quantity)throw new Error('Stock hors connexion insuffisant pour cette vente.')}
function reserveOfflineStock(shopId:string,productId:string,quantity:number){const rows=cachedStock<any>(shopId),next=rows.map(p=>p.id===productId?{...p,quantity_on_hand:Math.max(0,Number(p.quantity_on_hand)-quantity),status:Number(p.quantity_on_hand)-quantity<=0?'sold':p.status}:p).filter(p=>p.status==='active');cacheStock(shopId,next)}
