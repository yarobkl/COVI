import { useMemo, useState } from 'react'
import { Amount, Button, Ledger, LedgerRow } from '../../components/ui'
import { MonthNav } from '../../components/ui/MonthNav'
import { fcfa, plural } from '../../lib/format'
import { ExpenseLedger, ExpensesHero } from '../expenses/ExpenseLedger'
import { expensesOfMonth, monthSteps, monthTitle } from '../expenses/expenseMonths'
import { SalesJournal } from '../history/SalesJournal'
import { ArrivalResults } from '../statistics/ArrivalResults'
import { bilanTotal } from '../statistics/bilanMath'
import { MonthBars } from '../statistics/MonthBars'
import { MonthTable } from '../statistics/MonthTable'
import { arrivals, months, remainingStock } from './demoData'
import {
  demoArrivals,
  demoBilan,
  demoCategories,
  demoCounts,
  demoExpenses,
  demoJournal,
  demoNow,
} from './demoViews'

export type DemoPageId = 'accueil' | 'ventes' | 'stock' | 'arrivages' | 'bilan' | 'charges'

const arrivalsPaid = arrivals.reduce((n, a) => n + a.cost, 0)

function Head({ title, sub }: { title: string; sub?: string }) {
  return (
    <header className="page-head">
      <div>
        <h1>{title}</h1>
        {sub && <p className="page-head__sub">{sub}</p>}
      </div>
    </header>
  )
}

/** Accueil of the example: the three months in one figure, then month by month. */
export function DemoHome({ go }: { go: (page: DemoPageId) => void }) {
  const counts = demoCounts()
  const charges = months.reduce((n, m) => n + m.expenses, 0)
  const stockLeft = remainingStock.reduce((n, r) => n + r[2], 0)
  return (
    <div className="demo-page">
      <Head title="Trois mois à Poto-Poto" />
      <section className="bilan-hero" aria-labelledby="demo-hero">
        <h2 className="bilan-hero__lead" id="demo-hero">
          De juillet à septembre, la caisse a reçu
        </h2>
        <p className="amount amount--hero">
          {fcfa(counts.total)}
          <span className="amount__unit">FCFA</span>
        </p>
        <p className="bilan-hero__count">
          en <strong>{plural(counts.sales, 'vente')}</strong>, {plural(counts.pieces, 'pièce')}{' '}
          vendues. {stockLeft} restent en boutique.
        </p>
      </section>

      <section className="demo-months" aria-labelledby="demo-months">
        <h2 className="section-title" id="demo-months">
          Mois par mois
        </h2>
        <div className="demo-months__grid">
          {months.map((m) => {
            const rest = m.sales - m.arrivals - m.expenses
            return (
              <div className="demo-month" key={m.name}>
                <h3 className="demo-month__title">
                  {m.name}{' '}
                  <span className="demo-month__sub">
                    {plural(m.buyers, 'vente')} · {m.units} pièces
                  </span>
                </h3>
                <Ledger>
                  <LedgerRow variant="head" label="Ventes" value={<Amount value={m.sales} />} />
                  <LedgerRow
                    variant="sub"
                    label="Arrivages payés"
                    value={
                      <Amount value={-m.arrivals} tone={m.arrivals ? 'out' : undefined} regular />
                    }
                  />
                  <LedgerRow
                    variant="sub"
                    label="Charges"
                    value={<Amount value={-m.expenses} tone="out" regular />}
                  />
                  <LedgerRow
                    variant="total"
                    label="Reste du mois"
                    value={<Amount value={rest} tone={rest < 0 ? 'out' : undefined} />}
                  />
                </Ledger>
                <p className="muted demo-month__stock">
                  {m.stock} pièces restaient en fin de mois.
                </p>
              </div>
            )
          })}
        </div>
        <Ledger className="demo-total">
          <LedgerRow label="Ventes encaissées" value={<Amount value={counts.total} />} />
          <LedgerRow
            label={`Payé pour ${arrivals.length} arrivages`}
            value={<Amount value={-arrivalsPaid} tone="out" regular />}
          />
          <LedgerRow label="Charges" value={<Amount value={-charges} tone="out" regular />} />
          <LedgerRow
            variant="total"
            label="Reste après tout payé"
            value={<Amount value={counts.total - arrivalsPaid - charges} />}
          />
        </Ledger>
        <p className="bilan-note">
          Reste = ventes encaissées − arrivages payés − charges. Les pièces encore en stock ne sont
          pas comptées. C’est un repère pour vous, pas une comptabilité officielle.
        </p>
      </section>

      <section className="bilan-arrivals" aria-labelledby="demo-arrivals">
        <h2 className="section-title" id="demo-arrivals">
          Où en sont les arrivages
        </h2>
        <ArrivalResults arrivals={demoArrivals()} />
        <p>
          <Button variant="ghost" onClick={() => go('ventes')}>
            Voir les ventes, jour par jour
          </Button>
        </p>
      </section>
    </div>
  )
}

export function DemoSales() {
  const lines = useMemo(() => demoJournal(), [])
  const counts = demoCounts()
  return (
    <div className="sales-page">
      <Head
        title="Ventes"
        sub={`De juillet à septembre : ${plural(counts.sales, 'vente')}, ${counts.pieces} pièces.`}
      />
      <SalesJournal lines={lines} now={demoNow} empty={null} />
    </div>
  )
}

export function DemoStock() {
  const left = remainingStock.reduce((n, r) => n + r[2], 0)
  return (
    <div className="demo-page">
      <Head title="Stock au 30 septembre" sub={`${left} pièces restent en boutique.`} />
      <Ledger className="demo-stock">
        {remainingStock.map(([name, code, quantity, price, unique]) => (
          <LedgerRow
            key={name}
            label={name}
            meta={
              <>
                <span className="figures">{code}</span>
                {' · '}
                {unique ? (
                  'pièce unique'
                ) : quantity <= 2 ? (
                  <mark>plus que {quantity}</mark>
                ) : (
                  `restent ${quantity}`
                )}
              </>
            }
            value={<Amount value={price} />}
          />
        ))}
      </Ledger>
      <p className="muted">Prix affichés, en FCFA.</p>
    </div>
  )
}

export function DemoArrivals() {
  return (
    <div className="demo-page">
      <Head title="Arrivages" sub="Ce que vous avez acheté, et ce que ça a déjà rapporté." />
      <ArrivalResults arrivals={demoArrivals()} />
    </div>
  )
}

export function DemoBilan() {
  const bilan = demoBilan()
  const total = bilanTotal(bilan)
  const categories = demoCategories()
  return (
    <div className="bilan">
      <Head title="Bilan de juillet à septembre" />
      <section className="bilan-hero" aria-labelledby="demo-bilan-hero">
        <h2 className="bilan-hero__lead" id="demo-bilan-hero">
          De juillet à septembre, la caisse a reçu
        </h2>
        <p className="amount amount--hero">
          {fcfa(total.sales)}
          <span className="amount__unit">FCFA</span>
        </p>
        <p className="bilan-hero__count">
          en <strong>{plural(total.count, 'vente')}</strong>.
        </p>
      </section>
      <div className="bilan-grid">
        <section className="bilan-months" aria-labelledby="demo-bilan-months">
          <h2 className="section-title" id="demo-bilan-months">
            Ventes par mois
          </h2>
          <MonthBars months={bilan.map((m) => ({ key: m.key, label: m.label, amount: m.sales }))} />
          <MonthTable months={bilan} total={total} />
          <p className="bilan-note">
            <strong>Reste après charges</strong> = ventes encaissées − charges du mois. Ce que vous
            avez payé pour la marchandise n’est pas retiré : voyez plus bas ce que chaque arrivage a
            rapporté. C’est un repère pour vous, pas une comptabilité officielle.
          </p>
        </section>
        <section className="bilan-categories" aria-labelledby="demo-bilan-categories">
          <h2 className="section-title" id="demo-bilan-categories">
            Ce qui part le mieux
          </h2>
          <Ledger>
            {categories.map((c) => (
              <LedgerRow
                key={c.category}
                label={c.category}
                value={
                  <span className="bilan-categories__count">
                    <span className="figures">{c.pieces}</span> pièces vendues
                  </span>
                }
              />
            ))}
          </Ledger>
        </section>
      </div>
      <section className="bilan-arrivals" aria-labelledby="demo-bilan-arrivals">
        <h2 className="section-title" id="demo-bilan-arrivals">
          Ce que chaque arrivage a rapporté
        </h2>
        <ArrivalResults arrivals={demoArrivals()} />
      </section>
    </div>
  )
}

const range = { first: '2026-07', last: '2026-09' }

export function DemoCharges() {
  const rows = useMemo(() => demoExpenses(), [])
  const [month, setMonth] = useState(range.last)
  const steps = monthSteps(month, range)
  const visible = expensesOfMonth(rows, month)
  const step = (key: string | null) =>
    key ? { label: monthTitle(key, demoNow), onClick: () => setMonth(key) } : undefined
  return (
    <div className="charges-page">
      <Head title="Charges de la boutique" sub="Loyer et autres charges, mois par mois." />
      <MonthNav
        current={monthTitle(month, demoNow)}
        previous={step(steps.previous)}
        next={step(steps.next)}
      />
      <ExpensesHero view="month" month={month} now={demoNow} rows={visible} />
      <ExpenseLedger totalLabel={`Total de ${monthTitle(month, demoNow)}`} expenses={visible} />
    </div>
  )
}
