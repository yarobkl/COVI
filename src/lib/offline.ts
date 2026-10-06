import{recordSale}from'./covi'
export type PendingSale={id:string;shopId:string;productId:string;quantity:number;soldUnitPrice:number;paymentLabel:string;createdAt:string;attempts:number;lastError?:string}
const KEY='covi:pending-sales:v1'
const read=():PendingSale[]=>{try{return JSON.parse(localStorage.getItem(KEY)||'[]')}catch{return[]}}
const write=(x:PendingSale[])=>localStorage.setItem(KEY,JSON.stringify(x))
export const pendingSales=()=>read()
export const pendingCount=()=>read().length
export function queueSale(input:Omit<PendingSale,'id'|'createdAt'|'attempts'>){const x:PendingSale={...input,id:crypto.randomUUID(),createdAt:new Date().toISOString(),attempts:0};write([...read(),x]);window.dispatchEvent(new Event('covi-sync'));return x}
export async function syncPendingSales(){if(!navigator.onLine)return{synced:0,pending:read().length};let q=read(),synced=0;for(const item of[...q]){try{await recordSale(item.shopId,item.productId,item.quantity,item.soldUnitPrice,item.paymentLabel,item.id);q=q.filter(x=>x.id!==item.id);write(q);synced++}catch(e:any){q=q.map(x=>x.id===item.id?{...x,attempts:x.attempts+1,lastError:e?.message||'Erreur de synchronisation'}:x);write(q);break}}window.dispatchEvent(new Event('covi-sync'));return{synced,pending:q.length}}
export async function resilientSale(input:{shopId:string;productId:string;quantity:number;soldUnitPrice:number;paymentLabel:string}){if(!navigator.onLine){queueSale(input);return{offline:true}}try{const operationId=crypto.randomUUID();await recordSale(input.shopId,input.productId,input.quantity,input.soldUnitPrice,input.paymentLabel,operationId);return{offline:false}}catch(e:any){const network=/fetch|network|offline|failed to fetch/i.test(String(e?.message||e));if(!network)throw e;queueSale(input);return{offline:true}}}
