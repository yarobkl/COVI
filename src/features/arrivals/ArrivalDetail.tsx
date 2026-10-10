import { useId } from 'react'
import { CloseIcon, PlusIcon } from '../../components/icons'
import { Amount, Button, Dialog, IconButton, Ledger, LedgerRow, Notice } from '../../components/ui'
import { plural } from '../../lib/format'
import type { ArrivalProfit } from '../../lib/operations'
import type { Arrival } from '../../lib/types'
import { stockNote } from '../sale/saleMath'
import { productDetails } from '../stock/stockFilters'
import { ProductPicture } from '../stock/StockRow'
import { arrivalName, arrivalWhere, nextStepOf, recoveryOf } from './arrivalMath'
import { ArrivalStamp, RecoveryRuler } from './ArrivalRow'

function DetailBody({
  arrival: a,
  profit,
  titleId,
  added,
  onClose,
  onStep,
  onAdd,
}: {
  arrival: Arrival
  profit: ArrivalProfit | undefined
  titleId: string
  added: string | null
  onClose: () => void
  onStep: () => void
  onAdd: () => void
}) {
  const recovery = recoveryOf(profit?.cost ?? Number(a.global_cost), profit?.revenue ?? 0)
  const received = a.status === 'received'
  const step = nextStepOf(a)
  const balloon = a.kind === 'balloon'
  const products = profit?.products ?? []
  const left = products.filter((p) => p.status === 'active' && Number(p.quantity_on_hand) > 0)
  const breakdown =
    !balloon &&
    [a.merchandise_cost, a.transport_cost, a.customs_cost].filter((x) => Number(x) > 0).length > 1
  const where = arrivalWhere(a)

  return (
    <div className="dialog__body arrival-detail">
      <div className="product-form__head">
        <div>
          <h2 className="dialog__title" id={titleId}>
            {arrivalName(a)}
          </h2>
          {where && <p className="arrival__meta">{where}</p>}
        </div>
        <IconButton label={`Fermer ${arrivalName(a)}`} onClick={onClose}>
          <CloseIcon />
        </IconButton>
      </div>

      <div className="arrival-detail__stamp">
        <ArrivalStamp arrival={a} recovery={recovery} />
      </div>

      {added && (
        <Notice tone="success">
          <p>{added}</p>
        </Notice>
      )}

      <Ledger label={`Ce que ${a.code} a coûté et rapporté`}>
        <LedgerRow variant="head" label="Payé" value={<Amount value={recovery.cost} />} />
        {breakdown && (
          <>
            <LedgerRow
              variant="sub"
              label="Marchandise"
              value={<Amount value={Number(a.merchandise_cost)} regular />}
            />
            {Number(a.transport_cost) > 0 && (
              <LedgerRow
                variant="sub"
                label="Transport"
                value={<Amount value={Number(a.transport_cost)} regular />}
              />
            )}
            {Number(a.customs_cost) > 0 && (
              <LedgerRow
                variant="sub"
                label="Douane"
                value={<Amount value={Number(a.customs_cost)} regular />}
              />
            )}
          </>
        )}
        {received && (
          <>
            <LedgerRow
              label={
                <>
                  Ventes{' '}
                  {profit && profit.sold > 0 && (
                    <span className="muted">({plural(profit.sold, 'pièce')})</span>
                  )}
                </>
              }
              value={<Amount value={recovery.revenue} tone="in" />}
            />
            <LedgerRow
              variant="total"
              label={recovery.done ? 'A rapporté' : 'Encore à récupérer'}
              value={
                <Amount
                  value={recovery.done ? recovery.gained : recovery.toRecover}
                  tone={recovery.done ? 'in' : undefined}
                />
              }
            />
          </>
        )}
      </Ledger>

      {received && recovery.cost > 0 && (
        <div className="arrival-detail__ruler">
          <RecoveryRuler recovery={recovery} />
        </div>
      )}

      <section className="arrival-detail__pieces" aria-labelledby={`${titleId}-pieces`}>
        <h3 className="section-title" id={`${titleId}-pieces`}>
          {left.length ? 'Ce qui reste' : 'Les pièces'}
        </h3>
        {profit && profit.productCount > 0 && (
          <p className="muted">
            {plural(profit.sold + profit.remaining, 'pièce enregistrée', 'pièces enregistrées')} ·{' '}
            {plural(profit.sold, 'vendue')} · {profit.remaining}{' '}
            {profit.remaining > 1 ? 'restent' : 'reste'}
          </p>
        )}
        {left.length > 0 ? (
          <ul className="stock-list arrival-detail__list">
            {left.map((p) => {
              const note = stockNote(p)
              const details = productDetails(p)
              return (
                <li className="stock-row" key={p.id}>
                  <ProductPicture product={{ name: p.name, image_url: null }} size="sm" />
                  <div className="stock-row__main">
                    <p className="stock-row__name">{p.name}</p>
                    <p className="stock-row__meta">
                      {details && `${details} · `}
                      {note.low ? <mark>{note.text}</mark> : note.text}
                    </p>
                  </div>
                  <p className="stock-row__price">
                    <span className="visually-hidden">Prix affiché : </span>
                    <Amount value={Number(p.initial_sale_price)} />
                  </p>
                </li>
              )
            })}
          </ul>
        ) : (
          <p className="arrival-detail__none">
            {products.length > 0
              ? 'Tout est vendu.'
              : balloon
                ? 'Aucune pièce encore. Ajoutez-les à mesure que vous déballez.'
                : 'Aucune pièce encore. Mettez la marchandise en stock quand elle arrive.'}
          </p>
        )}
      </section>

      <div className="dialog__actions arrival-detail__actions">
        {received ? (
          <Button variant="primary" icon={<PlusIcon />} onClick={onAdd}>
            {balloon ? 'Ajouter une pièce' : 'Ajouter un modèle'}
          </Button>
        ) : (
          <>
            <p className="arrival-detail__wait">
              Vous ajouterez les pièces quand la marchandise sera arrivée.
            </p>
            {step && (
              <Button variant="primary" onClick={onStep}>
                {step.action}
              </Button>
            )}
          </>
        )}
      </div>
    </div>
  )
}

/** The detail of an arrival in a sheet: what it cost and brought back, its pieces, add one. */
export function ArrivalDetail({
  arrival,
  profit,
  added,
  onClose,
  onStep,
  onAdd,
}: {
  arrival: Arrival | null
  profit: ArrivalProfit | undefined
  added: string | null
  onClose: () => void
  onStep: () => void
  onAdd: () => void
}) {
  const titleId = useId()
  return (
    <Dialog
      open={Boolean(arrival)}
      onClose={onClose}
      labelledBy={titleId}
      sheet
      className="product-sheet arrival-sheet"
    >
      {arrival && (
        <DetailBody
          arrival={arrival}
          profit={profit}
          titleId={titleId}
          added={added}
          onClose={onClose}
          onStep={onStep}
          onAdd={onAdd}
        />
      )}
    </Dialog>
  )
}
