import { useEffect, useRef } from 'react'
import { CloudUpIcon } from '../../components/icons'
import { Button, ButtonLink, Notice, Stamp, Ticket, TicketLine } from '../../components/ui'
import { ticketClock, ticketDay } from '../../lib/dates'
import { fcfa, money, paidWith, plural } from '../../lib/format'
import { soldTotal, type SoldLine, type SoldSale } from './cart'

/** What is left of the article after this sale, said simply. */
function leftAfter(line: SoldLine) {
  const left = Number(line.product.quantity_on_hand) - line.quantity
  if (line.product.is_unique_piece) return 'c’était la dernière'
  if (left <= 0) return 'il n’en reste plus'
  return `il en reste ${left}`
}

/**
 * « Vendu. »: the one celebration of the sale. The receipt comes out, the PAYÉ stamp falls, the
 * amount is highlighted — and « Vente suivante » can be touched at once.
 */
export function SaleDone({
  sale,
  shopName,
  today,
  onNext,
}: {
  sale: SoldSale
  shopName: string
  /** Today's sales including this one, when known. */
  today: { count: number; total: number } | null
  onNext: () => void
}) {
  const next = useRef<HTMLButtonElement>(null)
  useEffect(() => next.current?.focus({ preventScroll: true }), [])

  const total = soldTotal(sale)
  const pieces = sale.lines.reduce((n, line) => n + line.quantity, 0)
  const displayedTotal = (line: SoldLine) => Number(line.product.initial_sale_price) * line.quantity
  // Only reductions count as a discount; a line sold above its displayed price is shown as sold.
  const discount = sale.lines.reduce(
    (sum, line) => sum + Math.max(0, displayedTotal(line) - line.price * line.quantity),
    0,
  )
  const change = sale.received !== null && sale.received > total ? sale.received - total : null
  const how = paidWith(sale.payment)

  return (
    <div className="sale-done">
      <p className="visually-hidden" role="status">
        Vente validée, {money(total).replace('FCFA', 'francs CFA')} {how}.
      </p>
      <h2 className="sale-done__title">Vendu.</h2>
      <p className="amount amount--xl">
        <span className="sale-done__amount">{fcfa(total)}</span>
        <span className="amount__unit">FCFA</span>
      </p>
      <p className="sale-done__how">{how}</p>
      {sale.lines.length === 1 ? (
        <p className="sale-done__what">
          {sale.lines[0].product.name} · {leftAfter(sale.lines[0])}
        </p>
      ) : (
        <p className="sale-done__what">{plural(pieces, 'article')} dans cette vente</p>
      )}

      <div className="sale-done__slot">
        <div className="sale-done__ticket">
          <Ticket head={shopName} sub={`${ticketDay(sale.at)} · ${ticketClock(sale.at)}`}>
            {sale.lines.map((line) => {
              const lineTotal = line.price * line.quantity
              return (
                <TicketLine
                  key={line.product.id}
                  left={
                    line.quantity > 1
                      ? `${line.quantity} × ${line.product.name}`
                      : line.product.name
                  }
                  right={fcfa(Math.max(lineTotal, displayedTotal(line)))}
                />
              )
            })}
            {discount > 0 && (
              <TicketLine className="ticket__line--out" left="Remise" right={fcfa(-discount)} />
            )}
            <hr className="ticket__cut" />
            <TicketLine className="ticket__total" left="TOTAL" right={fcfa(total)} />
            <p className="ticket__note ticket__note--flush">Payé {how}</p>
          </Ticket>
        </div>
        <div className="sale-done__mark" aria-hidden="true">
          <svg className="sale-done__burst" viewBox="0 0 180 104">
            <path d="M6 52h14" />
            <path d="M174 52h-14" />
            <path d="M22 14l10 10" />
            <path d="M158 90l-10-10" />
            <path d="M22 90l10-10" />
            <path d="M158 14l-10 10" />
          </svg>
          <Stamp kind="paid" size="lg" drop>
            Payé
          </Stamp>
        </div>
      </div>

      <p className="hand sale-done__note" aria-hidden="true">
        c’est noté, merci !
      </p>
      {change !== null && (
        <p className="sale-done__change">
          Monnaie rendue : <span className="figures">{fcfa(change)}</span>&nbsp;FCFA
        </p>
      )}
      {today && today.count > 0 && (
        <p className="sale-done__day">
          {today.count}
          <sup>{today.count === 1 ? 're' : 'e'}</sup> vente aujourd’hui ·{' '}
          <span className="figures">{fcfa(today.total)}</span>&nbsp;FCFA
        </p>
      )}
      {sale.offline && (
        <Notice icon={CloudUpIcon}>
          <p>Vente gardée sur ce téléphone. Elle partira dès que le réseau revient.</p>
        </Notice>
      )}
      <div className="sale-done__actions">
        <Button ref={next} variant="sale" size="xl" block onClick={onNext}>
          Vente suivante
        </Button>
        <ButtonLink variant="ghost" href="#/ventes">
          Voir les ventes
        </ButtonLink>
      </div>
    </div>
  )
}
