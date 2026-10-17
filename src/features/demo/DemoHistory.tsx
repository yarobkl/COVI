import { useMemo } from 'react'
import { Ledger, LedgerRow, SearchField, Sheet } from '../../components/ui'
import { money } from '../../lib/format'
import { tickets } from './demoData'

/** Simulated sales, searchable by ticket, product or arrival, one notebook line per article. */
export function DemoHistory({
  query,
  onQueryChange,
}: {
  query: string
  onQueryChange: (query: string) => void
}) {
  const q = query.toLowerCase()
  const lines = useMemo(
    () =>
      tickets.flatMap((ticket) =>
        ticket.lines
          .filter(
            (line) =>
              !q ||
              ticket.id.toLowerCase().includes(q) ||
              `${line.name} ${line.category} ${line.arrival}`.toLowerCase().includes(q),
          )
          .map((line, i) => ({ ticket, line, key: ticket.id + line.arrival + i })),
      ),
    [q],
  )
  return (
    <Sheet aria-labelledby="demo-history-title">
      <h2 className="section-title" id="demo-history-title">
        Ventes simulées
      </h2>
      <p className="muted">105 tickets clients · 143 articles vendus</p>
      <SearchField
        label="Rechercher un produit ou un ticket"
        placeholder="Rechercher un produit ou un ticket…"
        value={query}
        onChange={onQueryChange}
      />
      {lines.length === 0 ? (
        <p className="muted">Aucun résultat pour cette recherche.</p>
      ) : (
        <Ledger label="Ventes simulées">
          {lines.map(({ ticket, line, key }) => (
            <LedgerRow
              key={key}
              className="sold-row"
              label={
                <>
                  {line.quantity > 1 && <span className="figures">{line.quantity} × </span>}
                  {line.name}
                </>
              }
              meta={`${ticket.id} · ${ticket.date.toLocaleDateString('fr-FR')} · ${ticket.payment} · ${line.arrival}`}
              value={
                <span className="sold-row__price">
                  {line.initial !== line.sold && (
                    <s className="figures sold-row__initial">{money(line.initial)}</s>
                  )}
                  <span className="figures">{money(line.sold)}</span>
                </span>
              }
            />
          ))}
        </Ledger>
      )}
    </Sheet>
  )
}
