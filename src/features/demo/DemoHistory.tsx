import { useMemo } from 'react'
import { money } from '../../lib/format'
import { tickets } from './demoData'

/** Simulated sales, searchable by ticket, product or arrival. */
export function DemoHistory({
  query,
  onQueryChange,
}: {
  query: string
  onQueryChange: (query: string) => void
}) {
  const visibleTickets = useMemo(
    () =>
      tickets.filter((t) =>
        `${t.id} ${t.lines.map((l) => `${l.name} ${l.arrival}`).join(' ')}`
          .toLowerCase()
          .includes(query.toLowerCase()),
      ),
    [query],
  )
  return (
    <section className="card">
      <div className="demo-history-head">
        <div>
          <h2>Historique des ventes simulées</h2>
          <p>105 tickets clients · 143 articles vendus</p>
        </div>
        <input
          className="demo-search"
          value={query}
          onChange={(e) => onQueryChange(e.target.value)}
          placeholder="Rechercher un produit ou un ticket…"
        />
      </div>
      <div className="demo-table-wrap">
        <table className="demo-table">
          <thead>
            <tr>
              <th>Ticket / date</th>
              <th>Produit</th>
              <th>Arrivage</th>
              <th>Qté</th>
              <th>Prix initial</th>
              <th>Prix vendu</th>
              <th>Paiement</th>
              <th>Total ticket</th>
            </tr>
          </thead>
          <tbody>
            {visibleTickets.flatMap((ticket) =>
              ticket.lines
                .filter(
                  (line) =>
                    !query ||
                    ticket.id.toLowerCase().includes(query.toLowerCase()) ||
                    `${line.name} ${line.category} ${line.arrival}`
                      .toLowerCase()
                      .includes(query.toLowerCase()),
                )
                .map((line, i) => (
                  <tr key={ticket.id + line.arrival + i}>
                    <td>
                      {ticket.id}
                      <small>{ticket.date.toLocaleString('fr-FR')}</small>
                    </td>
                    <td>
                      {line.name}
                      <small>{line.category}</small>
                    </td>
                    <td>{line.arrival}</td>
                    <td>{line.quantity}</td>
                    <td>{money(line.initial)}</td>
                    <td>{money(line.sold)}</td>
                    <td>{ticket.payment}</td>
                    <td>{money(ticket.total)}</td>
                  </tr>
                )),
            )}
          </tbody>
        </table>
      </div>
      {visibleTickets.length === 0 && <p>Aucun résultat pour cette recherche.</p>}
    </section>
  )
}
