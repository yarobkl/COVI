import { Ticket, TicketLine } from '../../components/ui'
import { localDay, ticketClock, ticketDay } from '../../lib/dates'
import { fcfa, paymentLabel, plural } from '../../lib/format'
import type { Dashboard } from '../../lib/operations'
import type { Shop } from '../../lib/types'

const weekday = (d: Date) => d.toLocaleDateString('fr-FR', { weekday: 'long' })

/** The last sales, printed like the till receipt. */
export function LastSales({
  sales,
  shop,
  todayCount,
}: {
  sales: Dashboard['recentSales']
  shop: Shop
  todayCount: number
}) {
  const now = new Date()
  const shownToday = sales.filter((s) => localDay(new Date(s.soldAt)) === localDay(now)).length
  const earlier = todayCount - shownToday
  return (
    <section className="home-sales" aria-labelledby="home-sales">
      <h2 className="section-title" id="home-sales">
        Dernières ventes
      </h2>
      {sales.length === 0 ? (
        <p className="muted">Pas encore de vente. La première apparaîtra ici.</p>
      ) : (
        <Ticket
          tilt
          head={shop.name}
          sub={[shop.city?.split(',')[0], `${weekday(now)} ${ticketDay(now)}`]
            .filter(Boolean)
            .join(' · ')}
        >
          <ol className="home-sales__list">
            {sales.map((s) => {
              const at = new Date(s.soldAt)
              const sameDay = localDay(at) === localDay(now)
              const what = s.lines
                .map((l) => (l.quantity > 1 ? `${l.quantity} × ${l.name}` : l.name))
                .join(', ')
              const balloon = s.lines.some((l) => l.balloon)
              return (
                <li key={s.id}>
                  <TicketLine
                    left={
                      <>
                        <span className="home-sales__time">
                          {sameDay ? '' : `${ticketDay(at)} `}
                          {ticketClock(at)}
                        </span>{' '}
                        {what}
                      </>
                    }
                    right={fcfa(s.total)}
                  />
                  <p className="ticket__note">
                    {balloon && 'pièce de ballon · '}
                    {paymentLabel(s.paymentMethod)}
                  </p>
                </li>
              )
            })}
          </ol>
          {earlier > 0 && (
            <>
              <hr className="ticket__cut" />
              <p className="home-sales__more">+ {plural(earlier, 'vente')} plus tôt aujourd’hui</p>
            </>
          )}
          <p className="home-sales__link">
            <a href="#/ventes">Toutes les ventes</a>
          </p>
        </Ticket>
      )}
    </section>
  )
}
