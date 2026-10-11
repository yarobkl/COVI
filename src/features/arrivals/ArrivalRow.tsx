import { Button, cx, Ruler } from '../../components/ui'
import { fcfa, money, percent } from '../../lib/format'
import type { ArrivalProfit } from '../../lib/operations'
import type { Arrival } from '../../lib/types'
import {
  arrivalName,
  arrivalWhere,
  nextStepOf,
  recoveryOf,
  soldAndLeft,
  stampOf,
  type Recovery,
  type StampTone,
} from './arrivalMath'

const stampClass: Record<StampTone, string> = {
  draft: 'stamp arrival-stamp--draft',
  ordered: 'stamp arrival-stamp--ordered',
  transit: 'stamp stamp--transit',
  received: 'stamp stamp--received',
  done: 'stamp stamp--done',
}

/** The step of an arrival as a rubber stamp (the words are also said in the line). */
export function ArrivalStamp({
  arrival,
  recovery,
  small = false,
}: {
  arrival: Pick<Arrival, 'status' | 'kind'>
  recovery?: Recovery
  small?: boolean
}) {
  const stamp = stampOf(arrival, recovery)
  return (
    <span className={cx(stampClass[stamp.tone], small && 'stamp--sm', 'arrival-stamp')}>
      {stamp.label}
    </span>
  )
}

/** What it brought back, in words: « Encore 64 000 FCFA à récupérer » / « A rapporté 40 000 FCFA ». */
export function RecoveryLine({ recovery }: { recovery: Recovery }) {
  if (recovery.done)
    return (
      <p className="arrival__result arrival__result--done">
        {recovery.gained > 0 ? (
          <>
            A rapporté <strong className="figures">{fcfa(recovery.gained)}</strong>&nbsp;FCFA.
          </>
        ) : (
          'Rentabilisé : son prix est revenu.'
        )}
      </p>
    )
  return (
    <p className="arrival__result">
      Encore <strong className="figures">{fcfa(recovery.toRecover)}</strong>&nbsp;FCFA à récupérer.
    </p>
  )
}

/** The ruler and its sentence in amounts. */
export function RecoveryRuler({ recovery }: { recovery: Recovery }) {
  return (
    <div className="arrival__ruler">
      <p className="arrival__recovered">
        <span className="figures">{fcfa(recovery.revenue)}</span>&nbsp;FCFA récupérés sur{' '}
        <span className="figures">{fcfa(recovery.cost)}</span>
      </p>
      <Ruler
        value={recovery.percent}
        label={`${money(recovery.revenue)} récupérés sur ${money(recovery.cost)}, soit ${percent(recovery.percent)}`}
      />
    </div>
  )
}

/**
 * One arrival in the notebook: name and stamp, where it comes from, what it cost, what is sold and
 * left, and the ruler of what came back. The whole entry opens the detail; the next step has its
 * own button.
 */
export function ArrivalRow({
  arrival,
  profit,
  onOpen,
  onStep,
}: {
  arrival: Arrival
  profit: ArrivalProfit | undefined
  onOpen: () => void
  onStep: () => void
}) {
  const recovery = recoveryOf(profit?.cost ?? Number(arrival.global_cost), profit?.revenue ?? 0)
  const step = nextStepOf(arrival)
  const where = arrivalWhere(arrival)
  const received = arrival.status === 'received'
  return (
    <li className={cx('arrival', received && recovery.done && 'arrival--done')}>
      <div className="arrival__head">
        <h3 className="arrival__title">
          <button type="button" className="arrival__open" onClick={onOpen}>
            {arrivalName(arrival)}
          </button>
          {arrival.is_test && <span className="arrival__test"> · exemple</span>}
        </h3>
        <ArrivalStamp arrival={arrival} recovery={recovery} small />
      </div>
      {where && <p className="arrival__meta">{where}</p>}
      <p className="arrival__figures">
        Payé <strong className="figures">{fcfa(recovery.cost)}</strong>&nbsp;FCFA
        {profit && profit.productCount > 0 && <> · {soldAndLeft(profit)}</>}
      </p>
      {received && recovery.cost > 0 && (
        <div className="arrival__recovery">
          <RecoveryRuler recovery={recovery} />
          <RecoveryLine recovery={recovery} />
        </div>
      )}
      {step && (
        <div className="arrival__actions">
          <Button variant="secondary" onClick={onStep}>
            {step.action}
          </Button>
        </div>
      )}
    </li>
  )
}
