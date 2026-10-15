import { Ledger, LedgerRow, Sheet } from '../../components/ui'
import { fcfa, money } from '../../lib/format'
import { arrivals, months } from './demoData'

/** Three-month overview; an arrival opens the « Arrivages » page on its detail. */
export function DemoDashboard({ onOpenArrival }: { onOpenArrival: (code: string) => void }) {
  return (
    <>
      <section className="home-hero" aria-labelledby="demo-hero">
        <h2 className="home-hero__lead" id="demo-hero">
          En trois mois, la caisse a reçu
        </h2>
        <p className="amount amount--hero">
          {fcfa(2334000)}
          <span className="amount__unit">FCFA</span>
        </p>
        <p className="home-hero__count">
          en <strong>105 tickets</strong>, pour 143 articles vendus.
        </p>
      </section>
      <div className="page-pair">
        <Sheet aria-labelledby="demo-result">
          <h2 className="section-title" id="demo-result">
            Résultat de pilotage
          </h2>
          {months.map((m) => (
            <Ledger key={m.name} label={`${m.name} 2026`}>
              <LedgerRow
                variant="head"
                label={`${m.name} 2026`}
                meta={`${m.buyers} clients · ${m.units} articles · ${m.stock} pièces en stock`}
                value={<span className="figures">{money(m.sales)}</span>}
              />
              <LedgerRow
                variant="sub"
                label="Arrivages payés"
                value={<span className="figures amount-out">− {money(m.arrivals)}</span>}
              />
              <LedgerRow
                variant="sub"
                label="Charges"
                value={<span className="figures amount-out">− {money(m.expenses)}</span>}
              />
              <LedgerRow
                variant="total"
                label="Résultat du mois"
                value={
                  <span
                    className={
                      'figures' + (m.sales - m.arrivals - m.expenses < 0 ? ' amount-out' : '')
                    }
                  >
                    {money(m.sales - m.arrivals - m.expenses)}
                  </span>
                }
              />
            </Ledger>
          ))}
          <p className="muted demo-footnote">
            Ventes encaissées − arrivages payés − charges. Les stocks restants ne sont pas valorisés
            ; ce n’est pas une comptabilité officielle.
          </p>
        </Sheet>
        <Sheet aria-labelledby="demo-arrivals">
          <h2 className="section-title" id="demo-arrivals">
            Arrivages
          </h2>
          <Ledger label="Arrivages de la simulation">
            {arrivals.map((a) => (
              <LedgerRow
                key={a.code}
                variant="link"
                label={
                  <a
                    href={`#arrivage-${a.code}`}
                    onClick={(e) => {
                      e.preventDefault()
                      onOpenArrival(a.code)
                    }}
                  >
                    {a.code}
                  </a>
                }
                meta={`${a.origin} · ${a.sold} vendus sur ${a.items} · ${Math.round((a.revenue / a.cost) * 100)} % récupérés`}
                value={<span className="figures">{money(a.revenue - a.cost)}</span>}
              />
            ))}
          </Ledger>
        </Sheet>
      </div>
    </>
  )
}
