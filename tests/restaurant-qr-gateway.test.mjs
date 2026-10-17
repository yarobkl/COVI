import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createRestaurantQrGateway } from '../supabase/functions/restaurant-qr/gateway.mjs'

const qr='a'.repeat(64)
const env={ COVI_RESTAURANT_QR_ENABLED:'true',
  COVI_PUBLIC_ORIGIN:'https://covi-snowy.vercel.app',
  SUPABASE_URL:'https://test.supabase.co/',
  SUPABASE_SERVICE_ROLE_KEY:'sb_secret_'+'a'.repeat(40) }
const req=(query,method='GET',origin='https://covi-snowy.vercel.app')=>
  new Request('https://example.com/restaurant-qr'+query,{method,headers:{origin}})
const data={ restaurantName:'Restaurant du fleuve',tableName:'04',capacity:4,
  tableState:'collecting', menu:[
    {id:'d1',name:'Poisson',category:'Plats',kind:'dish',priceXaf:6000,available:true},
    {id:'b1',name:'Jus',category:'Boissons',kind:'drink',priceXaf:1000,available:false},
  ],privatePhone:'+242000000000',shop_id:'shop-secret' }
test('QR restaurant refuses access when explicitly disabled', async()=>{
  const res=await createRestaurantQrGateway({...env,COVI_RESTAURANT_QR_ENABLED:'false'})(req('?table='+qr))
  assert.equal(res.status,503)
})
test('QR restaurant forbids untrusted origin, mutations and malformed token', async()=>{
  const fetcher=async()=>{throw new Error('backend unexpectedly called')}
  const handler=createRestaurantQrGateway(env,fetcher)
  assert.equal((await handler(req('?table='+qr,'GET','https://evil.example'))).status,403)
  assert.equal((await handler(req('?table='+qr,'POST'))).status,405)
  assert.equal((await handler(req('?table=x'))).status,400)
})
test('QR projects only one table, no private shop/customer data', async()=>{
  let called=0
  const handler=createRestaurantQrGateway(env,async(url,options)=>{
    called++
    assert.equal(new URL(url).pathname,'/rest/v1/rpc/restaurant_qr_catalog')
    assert.equal(JSON.parse(options.body).p_qr_token,qr)
    assert.equal(options.method,'POST')
    return Response.json(data)
  })
  const r=await handler(req('?table='+qr))
  assert.equal(r.status,200)
  const body=await r.json()
  assert.equal(body.restaurantName,'Restaurant du fleuve')
  assert.equal(body.tableState,'collecting')
  assert.equal(body.orderingOpen,false)
  assert.equal(body.menu.length,2)
  assert.equal(body.privatePhone,undefined)
  assert.equal(body.shop_id,undefined)
  assert.equal(JSON.stringify(body).includes('shop-secret'),false)
  assert.equal(r.headers.get('cache-control'),'no-store')
  assert.equal(called,1)
})
test('QR unknown or disabled table returns 404 without leaking it',async()=>{
  const h=createRestaurantQrGateway(env,async()=>Response.json(null))
  assert.equal((await h(req('?table='+qr))).status,404)
})
test('QR fails closed on backend error or malformed data',async()=>{
  const h=createRestaurantQrGateway(env,async()=>Response.json({...data,menu:[{name:'raw'}]}))
  assert.equal((await h(req('?table='+qr))).status,503)
  const failure=createRestaurantQrGateway(env,async()=>{throw new Error('down')})
  assert.equal((await failure(req('?table='+qr))).status,503)
})
