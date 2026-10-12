import '../../styles/app/filters.css'
import { ChevronLeftIcon, ChevronRightIcon } from '../icons'
import { cx } from './cx'

type Step = { label: string; onClick: () => void }

/**
 * « ‹ septembre · Octobre · novembre › »: the month shown, between the previous and the next one.
 * Leave `next` out when there is nothing after (the current month).
 */
export function MonthNav({
  current,
  previous,
  next,
  className,
}: {
  current: string
  previous?: Step
  next?: Step
  className?: string
}) {
  return (
    <nav className={cx('month-nav', className)} aria-label="Changer de mois">
      {previous ? (
        <button type="button" className="month-nav__step" onClick={previous.onClick}>
          <ChevronLeftIcon />
          <span>
            <span className="visually-hidden">Mois précédent : </span>
            {previous.label}
          </span>
        </button>
      ) : (
        <span className="month-nav__step month-nav__step--none" />
      )}
      <p className="month-nav__current" aria-live="polite">
        {current}
      </p>
      {next ? (
        <button
          type="button"
          className="month-nav__step month-nav__step--next"
          onClick={next.onClick}
        >
          <span>
            <span className="visually-hidden">Mois suivant : </span>
            {next.label}
          </span>
          <ChevronRightIcon />
        </button>
      ) : (
        <span className="month-nav__step month-nav__step--none" />
      )}
    </nav>
  )
}
