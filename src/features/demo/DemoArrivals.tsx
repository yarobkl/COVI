import { Badge, Button, Ledger, LedgerRow, Ruler, Sheet } from '../../components/ui'
import { fcfa, money } from '../../lib/format'
import { arrivals } from './demoData'

/** Simulated arrivals written as notebook entries; « Voir le détail » opens the figures. */
export function DemoArrivals({
  selectedArrival,
  onSelectArrival,
}: {
  selectedArrival: string | null
  onSelectArrival: (code: string | null) => void
}) {
  return (
    <Sheet aria-label="Arrivages et rentabilité">
      {arrivals.map((a) => {
        const recovery = Math.round((a.revenue / a.cost) * 100)
        const open = selectedArrival === a.code
        return (
          <article className="entry" key={a.code} aria-labelledby={`demo-${a.code}`}>
            <div className="entry__head">
              <h3 className="entry__title" id={`demo-${a.code}`}>
                {a.code} · {a.kind}
              </h3>
              <Badge tone={recovery >= 100 ? 'success' : 'waiting'}>
                {recovery >= 100 ? 'Rentabilisé' : `${recovery} % récupéré`}
              </Badge>
            </div>
            <p className="entry__meta">
              {a.origin} · reçu le {a.received}
            </p>
            <Ledger label={`Chiffres de ${a.code}`}>
              <LedgerRow label="Coût" value={<span className="figures">{money(a.cost)}</span>} />
              <LedgerRow
                label="Ventes"
                value={<span className="figures">{money(a.revenue)}</span>}
              />
              <LedgerRow
                variant="total"
                label="Résultat"
                value={
                  <span className={'figures' + (a.revenue < a.cost ? ' amount-out' : '')}>
                    {money(a.revenue - a.cost)}
                  </span>
                }
              />
            </Ledger>
            <Ruler
              value={recovery}
              label={`${fcfa(a.revenue)} FCFA récupérés sur ${fcfa(a.cost)}, soit ${recovery} %`}
            />
            <div className="row-actions">
              <Button
                variant="ghost"
                aria-expanded={open}
                onClick={() => onSelectArrival(open ? null : a.code)}
              >
                {open ? 'Fermer le détail' : 'Voir le détail'}
              </Button>
            </div>
            {open && (
              <p className="entry__detail">
                {a.supplier} · {a.items} enregistrés · {a.sold} vendus · {a.remaining} restants
              </p>
            )}
          </article>
        )
      })}
    </Sheet>
  )
}
