import { useMemo, useState } from 'react'
import { ArrowLeft, ChartNoAxesCombined, History, Home, Package, ReceiptText, Ship } from 'lucide-react'

type Line = { name: string; category: string; arrival: string; initial: number; sold: number; quantity: number }
type Ticket = { id: string; date: Date; payment: string; lines: Line[]; total: number }
type Unit = Omit<Line, 'quantity'>

const money = (n: number) => new Intl.NumberFormat('fr-FR').format(n) + ' FCFA'
const paymentMethods = ['Espèces', 'Mobile Money', 'Carte', 'Virement']

function monthlyUnits(month: number): Unit[] {
  const counts: Record<number, Array<[string, string, string, number, number, number]>> = {
    6: [
      ['Robe modèle A', 'Robes', 'CHN-001', 18000, 18000, 8],
      ['Jean modèle B', 'Jeans', 'CHN-001', 22000, 22000, 5],
      ['Chemise modèle C', 'Chemises', 'CHN-001', 12000, 12000, 10],
      ['Pièce ballon', 'Lot mixte', 'BAL-001', 15000, 10000, 12],
    ],
    7: [
      ['Robe modèle A', 'Robes', 'CHN-001', 18000, 18000, 7],
      ['Jean modèle B', 'Jeans', 'CHN-001', 22000, 22000, 5],
      ['Chemise modèle C', 'Chemises', 'CHN-001', 12000, 12000, 10],
      ['Pièce ballon', 'Lot mixte', 'BAL-001', 15000, 15000, 22],
      ['Article modèle D', 'Vêtements', 'IND-002', 20000, 20000, 15],
    ],
    8: [
      ['Robe modèle A', 'Robes', 'CHN-001', 18000, 18000, 5],
      ['Jean modèle B', 'Jeans', 'CHN-001', 22000, 22000, 4],
      ['Chemise modèle C', 'Chemises', 'CHN-001', 12000, 12000, 8],
      ['Pièce ballon', 'Lot mixte', 'BAL-001', 15000, 15000, 12],
      ['Article modèle D', 'Vêtements', 'IND-002', 20000, 20000, 20],
    ],
  }
  const rows = counts[month] ?? []
  return rows.flatMap(([name, category, arrival, initial, sold, quantity]) => Array.from({ length: quantity }, () => ({ name, category, arrival, initial, sold })))
}

function makeTickets(): Ticket[] {
  const plan = [{ month: 6, customers: 25, firstDay: 6 }, { month: 7, customers: 42, firstDay: 1 }, { month: 8, customers: 38, firstDay: 1 }]
  let sequence = 0
  return plan.flatMap(({ month, customers, firstDay }) => {
    const units = monthlyUnits(month)
    const tickets: Ticket[] = Array.from({ length: customers }, (_, i) => {
      const daysInMonth = new Date(2026, month + 1, 0).getDate()
      const day = Math.min(daysInMonth, firstDay + Math.floor(i * (daysInMonth - firstDay) / customers))
      sequence += 1
      return { id: `V-${String(sequence).padStart(3, '0')}`, date: new Date(2026, month, day, 9 + (i * 3) % 9, (i * 17) % 60), payment: paymentMethods[(i + month) % paymentMethods.length], lines: [], total: 0 }
    })
    units.forEach((unit, index) => {
      const firstSellDay = unit.arrival === 'BAL-001' && month === 6 ? 18 : unit.arrival === 'IND-002' && month === 7 ? 15 : firstDay
      const eligibleTickets = tickets.filter(ticket => ticket.date.getDate() >= firstSellDay)
      const ticket = eligibleTickets[index % eligibleTickets.length]
      const same = ticket.lines.find(line => line.name === unit.name && line.arrival === unit.arrival)
      if (same) same.quantity += 1
      else ticket.lines.push({ ...unit, quantity: 1 })
    })
    tickets.forEach(ticket => { ticket.total = ticket.lines.reduce((sum, line) => sum + line.sold * line.quantity, 0) })
    return tickets
  })
}

const tickets = makeTickets()
const arrivals = [
  { code: 'CHN-001', kind: 'Commande fournisseur', origin: 'Chine', supplier: 'Fournisseur textile', received: '5 juillet 2026', items: 65, sold: 62, remaining: 3, cost: 620000, revenue: 1004000 },
  { code: 'BAL-001', kind: 'Ballon / lot mixte', origin: 'Brazzaville', supplier: 'Lot mixte', received: '18 juillet 2026', items: 50, sold: 46, remaining: 4, cost: 250000, revenue: 630000 },
  { code: 'IND-002', kind: 'Commande fournisseur', origin: 'Inde', supplier: 'Fournisseur textile', received: '15 août 2026', items: 40, sold: 35, remaining: 5, cost: 360000, revenue: 700000 },
]
const months = [
  { name: 'Juillet', buyers: 25, units: 35, sales: 494000, arrivals: 870000, expenses: 110000, stock: 50 },
  { name: 'Août', buyers: 42, units: 59, sales: 986000, arrivals: 360000, expenses: 130000, stock: 53 },
  { name: 'Septembre', buyers: 38, units: 49, sales: 854000, arrivals: 0, expenses: 140000, stock: 12 },
]

export function DemoMode({ onExit }: { onExit: () => void }) {
  const [page, setPage] = useState('Tableau de bord')
  const [query, setQuery] = useState('')
  const [selectedArrival, setSelectedArrival] = useState<string | null>(null)
  const visibleTickets = useMemo(() => tickets.filter(t => `${t.id} ${t.lines.map(l => `${l.name} ${l.arrival}`).join(' ')}`.toLowerCase().includes(query.toLowerCase())), [query])
  const nav = [['Tableau de bord', Home], ['Produits vendus', History], ['Mon stock', Package], ['Mes arrivages', Ship], ['Statistiques', ChartNoAxesCombined], ['Charges de la boutique', ReceiptText]] as const
  const content = page === 'Produits vendus' ? <section className="card"><div className="demo-history-head"><div><h2>Historique des ventes simulées</h2><p>105 tickets clients · 143 articles vendus</p></div><input className="demo-search" value={query} onChange={e => setQuery(e.target.value)} placeholder="Rechercher un produit ou un ticket…"/></div><div className="demo-table-wrap"><table className="demo-table"><thead><tr><th>Ticket / date</th><th>Produit</th><th>Arrivage</th><th>Qté</th><th>Prix initial</th><th>Prix vendu</th><th>Paiement</th><th>Total ticket</th></tr></thead><tbody>{visibleTickets.flatMap(ticket => ticket.lines.filter(line => !query || ticket.id.toLowerCase().includes(query.toLowerCase()) || `${line.name} ${line.category} ${line.arrival}`.toLowerCase().includes(query.toLowerCase())).map((line, i) => <tr key={ticket.id + line.arrival + i}><td>{ticket.id}<small>{ticket.date.toLocaleString('fr-FR')}</small></td><td>{line.name}<small>{line.category}</small></td><td>{line.arrival}</td><td>{line.quantity}</td><td>{money(line.initial)}</td><td>{money(line.sold)}</td><td>{ticket.payment}</td><td>{money(ticket.total)}</td></tr>))}</tbody></table></div>{visibleTickets.length === 0 && <p>Aucun résultat pour cette recherche.</p>}</section> : page === 'Mon stock' ? <section className="card"><h2>Stock au 30 septembre</h2><p>12 produits enregistrés encore disponibles dans cette simulation.</p><div className="demo-table-wrap"><table className="demo-table"><thead><tr><th>Produit</th><th>Arrivage</th><th>Qté restante</th><th>Prix de vente</th></tr></thead><tbody>{[['Jean modèle B','CHN-001',1,22000],['Chemise modèle C','CHN-001',2,12000],['Pièce ballon','BAL-001',4,15000],['Article modèle D','IND-002',5,20000]].map(row=><tr key={row[1]+'-'+row[0]}><td>{row[0]}</td><td>{row[1]}</td><td>{row[2]}</td><td>{money(Number(row[3]))}</td></tr>)}</tbody></table></div></section> : page === 'Mes arrivages' ? <section className="card"><h2>Arrivages et rentabilité</h2><div className="demo-arrivals">{arrivals.map(a=><article key={a.code}><button className="demo-arrival-button" onClick={()=>setSelectedArrival(selectedArrival===a.code?null:a.code)}><span><b>{a.code} · {a.kind}</b><small>{a.origin} · Reçu le {a.received}</small></span><span><b>{money(a.revenue-a.cost)}</b><small>{Math.round(a.revenue/a.cost*100)} % récupérés</small></span></button>{selectedArrival===a.code&&<div className="demo-arrival-detail"><span>{a.supplier}</span><span>{a.items} enregistrés · {a.sold} vendus · {a.remaining} restants</span><span>Coût {money(a.cost)} · Ventes {money(a.revenue)}</span>{a.code==='BAL-001'&&<b className="demo-profitable">BALLON RENTABILISÉ</b>}</div>}</article>)}</div></section> : page === 'Statistiques' ? <section className="card"><h2>Statistiques des trois mois</h2><div className="demo-kpis">{[['Tickets clients','105'],['Articles vendus','143'],['Ventes encaissées',money(2334000)],['Stock restant','12 articles']].map(([label,value])=><div className="kpi" key={label}><span>{label}</span><b>{value}</b></div>)}</div><h3>Articles les plus vendus</h3><ol className="demo-ranking"><li>Article modèle D <b>35 vendus</b></li><li>Chemise modèle C <b>28 vendues</b></li><li>Robe modèle A <b>20 vendues</b></li></ol></section> : page === 'Charges de la boutique' ? <section className="card"><h2>Charges de la boutique</h2><p>Simulation des charges ponctuelles et récurrentes sur la période.</p><div className="demo-table-wrap"><table className="demo-table"><thead><tr><th>Mois</th><th>Loyer</th><th>Autres charges</th><th>Total</th></tr></thead><tbody><tr><td>Juillet</td><td>{money(70000)}</td><td>{money(40000)}</td><td>{money(110000)}</td></tr><tr><td>Août</td><td>{money(70000)}</td><td>{money(60000)}</td><td>{money(130000)}</td></tr><tr><td>Septembre</td><td>{money(70000)}</td><td>{money(70000)}</td><td>{money(140000)}</td></tr></tbody></table></div></section> : <>
    <div className="demo-month-grid">{months.map(m=><article className="card" key={m.name}><span>{m.name} 2026</span><b>{money(m.sales)}</b><small>Ventes encaissées · {m.buyers} clients · {m.units} articles</small><small>{m.stock} produits disponibles en fin de mois</small></article>)}</div>
    <div className="demo-kpis"><article className="kpi"><span>Ventes encaissées</span><b>{money(2334000)}</b><small>sur trois mois</small></article><article className="kpi"><span>Investissements en arrivages</span><b>{money(1230000)}</b><small>3 arrivages reçus</small></article><article className="kpi"><span>Charges de la boutique</span><b>{money(380000)}</b><small>sur trois mois</small></article><article className="kpi"><span>Bénéfice final estimé</span><b>{money(724000)}</b><small>pilotage simulé, non comptable</small></article></div>
    <section className="card"><h2>Résultat de pilotage par mois</h2><div className="demo-table-wrap"><table className="demo-table"><thead><tr><th>Mois</th><th>Ventes</th><th>Arrivages payés</th><th>Charges</th><th>Résultat du mois</th><th>Stock disponible</th></tr></thead><tbody>{months.map(m=><tr key={m.name}><td>{m.name} 2026</td><td>{money(m.sales)}</td><td>{money(m.arrivals)}</td><td>{money(m.expenses)}</td><td className={m.sales-m.arrivals-m.expenses<0?'demo-negative':'demo-profitable'}>{money(m.sales-m.arrivals-m.expenses)}</td><td>{m.stock} pièces</td></tr>)}</tbody><tfoot><tr><th>Total</th><th>{money(2334000)}</th><th>{money(1230000)}</th><th>{money(380000)}</th><th>{money(724000)}</th><th>12 pièces</th></tr></tfoot></table></div><p className="demo-footnote">Calcul de pilotage de trésorerie : ventes encaissées − arrivages payés − charges. Les stocks restants ne sont pas valorisés dans ce résultat. Ce chiffre n’est pas une comptabilité officielle.</p></section>
    <section className="card"><h2>Progression des arrivages</h2><div className="demo-arrivals">{arrivals.map(a=><button className="demo-arrival-button" key={a.code} onClick={()=>{setPage('Mes arrivages');setSelectedArrival(a.code)}}><span><b>{a.code}</b><small>{a.origin} · {a.sold} vendus / {a.items}</small></span><span><b>{money(a.revenue-a.cost)}</b><small>{Math.round(a.revenue/a.cost*100)} % récupérés</small></span></button>)}</div></section>
  </>
  return <div className="app demo-app"><aside><div className="brand"><span>C</span><b>O</b><span>VI</span><i/></div><p className="tag">Le système d’exploitation<br/>de votre commerce.</p><nav>{nav.map(([name, Icon])=><button className={page===name?'active':''} key={name} onClick={()=>setPage(name)}><Icon/>{name}</button>)}</nav><div className="shop"><span>BOUTIQUE DE SIMULATION</span><b>Élégance Brazzaville</b><small>Brazzaville · XAF</small></div></aside><main><div className="demo-banner"><b>SIMULATION</b><span>Données fictives du 1er juillet au 30 septembre 2026. Rien n’est enregistré dans ta boutique.</span><button onClick={onExit}><ArrowLeft/>Quitter</button></div><header><div className="demo-top-label">{page} · données de simulation</div><select className="demo-page-select" aria-label="Choisir une page de simulation" value={page} onChange={e=>setPage(e.target.value)}>{nav.map(([name])=><option key={name} value={name}>{name}</option>)}</select></header><div className="content"><div className="hello"><div><h1>{page}</h1><span>Scénario de gestion d’une boutique sur trois mois.</span></div></div>{content}</div></main><div className="bottom">{[['Accueil',Home,'Tableau de bord'],['Ventes',History,'Produits vendus'],['Stock',Package,'Mon stock'],['Arrivages',Ship,'Mes arrivages']].map(([name,Icon,target]:any)=><button className={page===target?'active':''} key={name} onClick={()=>setPage(target)}><Icon/>{name}</button>)}</div></div>
}
