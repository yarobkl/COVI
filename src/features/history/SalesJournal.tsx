import { useMemo, useState, type ReactNode } from 'react'
import { Amount, Badge, Button, EmptyState, SearchField } from '../../components/ui'
import { FilterChips } from '../../components/ui/FilterChips'
import { ticketClock } from '../../lib/dates'
import { fcfa, money, paymentLabel, plural } from '../../lib/format'
import '../../styles/app/ventes.css'
import {
  filterLines,
  firstLines,
  groupByDay,
  methodsIn,
  periods,
  type JournalDay,
  type JournalLine,
  type Period,
} from './journal'

/** Lines shown at first, then added by « Voir plus ». */
const PAGE_SIZE = 40

const ALL = 'all'

/**
 * The sales journal: filters (period, payment, search), then one notebook page per day
 * (« Aujourd’hui · 7 ventes · 126 000 ») and its lines. Shared by Ventes and the example shop.
 */
export function SalesJournal({
  lines,
  now,
  initialPeriod = 'all',
  empty,
  footer,
}: {
  lines: JournalLine[]
  /** « Aujourd’hui » and the periods are counted from here. */
  now: Date
  initialPeriod?: Period
  /** Shown when there is no sale at all. */
  empty: ReactNode
  /** Under the last line (e.g. the 500-sales limit). */
  footer?: ReactNode
}) {
  const [period, setPeriod] = useState<Period>(initialPeriod)
  const [method, setMethod] = useState<string>(ALL)
  const [query, setQuery] = useState('')
  const [limit, setLimit] = useState(PAGE_SIZE)

  const methods = useMemo(() => methodsIn(lines), [lines])
  const filtered = useMemo(
    () => filterLines(lines, { period, method: method === ALL ? null : method, query, now }),
    [lines, period, method, query, now],
  )
  const days = useMemo(() => groupByDay(filtered, now), [filtered, now])
  const shown = firstLines(days, limit)
  const shownCount = Math.min(limit, filtered.length)
  const hasExamples = filtered.some((l) => l.example)

  // A new filter starts again from the top of the journal.
  const refilter =
    <T,>(set: (v: T) => void) =>
    (v: T) => {
      set(v)
      setLimit(PAGE_SIZE)
    }

  if (lines.length === 0) return <>{empty}</>

  return (
    <div className="journal">
      <div className="journal__filters">
        <SearchField
          className="journal__search"
          label="Chercher une vente"
          placeholder="Chercher : robe, jean, BAL-003…"
          value={query}
          onChange={refilter(setQuery)}
        />
        <FilterChips
          legend="Période"
          hideLegend
          options={periods}
          value={period}
          onChange={refilter(setPeriod)}
        />
        {methods.length > 1 && (
          <FilterChips
            legend="Payé en"
            options={[
              { value: ALL, label: 'Tous' },
              ...methods.map((m) => ({ value: m, label: paymentLabel(m) })),
            ]}
            value={method}
            onChange={refilter(setMethod)}
            className="journal__methods"
          />
        )}
      </div>

      {filtered.length === 0 ? (
        <p className="journal__none" role="status">
          {query.trim()
            ? `Rien ne correspond à « ${query.trim()} ».`
            : period === 'today'
              ? 'Pas encore de vente aujourd’hui.'
              : 'Aucune vente sur cette période.'}
        </p>
      ) : (
        <>
          {hasExamples && (
            <p className="journal__examples">
              Les ventes marquées « Exemple » viennent de la boutique d’exemple : elles ne comptent
              pas dans les totaux.
            </p>
          )}
          {shown.map((day) => (
            <JournalPage key={day.key} day={day} />
          ))}
          {shownCount < filtered.length && (
            <div className="journal__more">
              <Button variant="secondary" onClick={() => setLimit((n) => n + PAGE_SIZE)}>
                Voir plus
              </Button>
              <p className="muted">
                {shownCount} lignes sur {filtered.length}
              </p>
            </div>
          )}
        </>
      )}
      {footer}
    </div>
  )
}

/** One day of the journal: its heading (count and total), then its lines. */
function JournalPage({ day }: { day: JournalDay }) {
  return (
    <section className="jday" aria-label={day.label}>
      <h2 className="jday__head">
        <span className="jday__label">{day.label}</span>
        <span className="jday__count">
          {day.count > 0 ? ` · ${plural(day.count, 'vente')} · ` : ' · exemples seulement'}
        </span>
        {day.count > 0 && (
          <span className="jday__total figures">
            {fcfa(day.total)}
            <span className="visually-hidden"> FCFA</span>
          </span>
        )}
      </h2>
      <ol className="jday__lines">
        {day.lines.map((line) => (
          <JournalRow key={line.key} line={line} />
        ))}
      </ol>
    </section>
  )
}

/** « 14:32 · 2 × Chemise lin modèle C · Espèces · CHN-001 · 24 000 ». */
function JournalRow({ line }: { line: JournalLine }) {
  const sold = line.soldUnit * line.quantity
  const shown = line.shownUnit * line.quantity
  const discount = shown > sold
  return (
    <li className={line.example ? 'jline jline--example' : 'jline'}>
      <time className="jline__time" dateTime={line.soldAt.toISOString()}>
        {ticketClock(line.soldAt)}
      </time>
      <div className="jline__what">
        <p className="jline__name">
          {line.quantity > 1 && <span className="jline__qty">{line.quantity} × </span>}
          {line.name}
        </p>
        <p className="jline__meta">
          {paymentLabel(line.method)}
          {line.arrivalCode && (
            <>
              {' · '}
              <span className="figures">{line.arrivalCode}</span>
              {line.balloon && ' (ballon)'}
            </>
          )}
          {line.quantity > 1 && (
            <>
              {' · '}
              <span className="figures">{fcfa(line.soldUnit)}</span> pièce
            </>
          )}
          {line.example && (
            <>
              {' '}
              <Badge>Exemple</Badge>
            </>
          )}
        </p>
      </div>
      <p className="jline__price">
        {discount && (
          <span className="jline__shown">
            <span className="visually-hidden">Prix affiché </span>
            <Amount value={shown} size="sm" struck regular />
            <span className="visually-hidden">, vendu </span>
          </span>
        )}
        <Amount value={sold} className="jline__sold" />
        {discount && (
          <span className="visually-hidden">, soit {money(shown - sold)} de remise</span>
        )}
      </p>
    </li>
  )
}

/** The default empty journal: no sale yet. */
export function NoSaleYet({ actions }: { actions?: ReactNode }) {
  return (
    <EmptyState title="Pas encore de vente." actions={actions}>
      <p>La première apparaîtra ici dès que vous l’aurez validée.</p>
    </EmptyState>
  )
}
