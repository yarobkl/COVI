import { useCallback, useMemo, useState } from 'react'
import { Amount, Button, Ledger, LedgerRow, Notice, PageHead, Sheet } from '../../components/ui'
import { percent } from '../../lib/format'
import { salonApi } from '../../lib/salon'
import { Loaded, SalonTabs } from './SalonParts'
import { reportCsvRows } from './salonReportCsv'
import {
  addDays,
  downloadCsv,
  methodLabels,
  mondayOf,
  salonDay,
  unitLabels,
  weekdayLabels,
} from './salonFormat'
import { useSalonLoad } from './useSalonLoad'

type Period = 'today' | 'week' | 'month' | 'custom'
const periods = [
  { value: 'today', label: 'Aujourd’hui' },
  { value: 'week', label: 'Cette semaine' },
  { value: 'month', label: 'Ce mois' },
  { value: 'custom', label: 'Période' },
] as const

/** Rapports : finances avec leur méthode de calcul, activité, équipe, clients, export CSV. */
export function SalonReportsPage({ shopId }: { shopId: string }) {
  const today = salonDay(new Date(), 'Africa/Brazzaville')
  const [period, setPeriod] = useState<Period>('month')
  const [from, setFrom] = useState(addDays(today, -29))
  const [to, setTo] = useState(today)
  const range = useMemo(() => {
    if (period === 'today') return { from: today, to: today }
    if (period === 'week') return { from: mondayOf(today), to: today }
    if (period === 'month') return { from: `${today.slice(0, 8)}01`, to: today }
    return { from, to }
  }, [period, from, to, today])
  const load = useCallback(() => salonApi.report(shopId, range.from, range.to), [shopId, range])
  const report = useSalonLoad(load)
  const r = report.data
  const f = r?.finance
  const maxDay = Math.max(1, ...(r?.daily ?? []).map((d) => d.revenue_xaf))
  const byMargin = [...(r?.services ?? [])].sort((a, b) => b.margin_xaf - a.margin_xaf).slice(0, 5)

  return (
    <div className="page-stack">
      <PageHead
        title="Rapports"
        sub="Ce que vous vendez, ce que vous encaissez, ce que vous dépensez, et ce qu’il vous reste."
        action={
          r ? (
            <Button
              onClick={() =>
                downloadCsv(`rapport-salon-${r.period.from}-${r.period.to}.csv`, reportCsvRows(r))
              }
            >
              Exporter (CSV)
            </Button>
          ) : undefined
        }
      />
      <SalonTabs label="Période" tabs={periods} value={period} onChange={setPeriod} />
      {period === 'custom' && (
        <div className="form-grid">
          <label>
            Du
            <input type="date" value={from} max={to} onChange={(e) => setFrom(e.target.value)} />
          </label>
          <label>
            Au
            <input type="date" value={to} min={from} onChange={(e) => setTo(e.target.value)} />
          </label>
        </div>
      )}
      <Loaded loading={report.loading && !r} error={report.error}>
        {r && f && (
          <>
            <div className="page-pair">
              <Sheet>
                <h2 className="section-title">Résultat</h2>
                <Ledger label="Compte de résultat estimé">
                  <LedgerRow
                    label="Prestations payées"
                    value={<Amount value={f.services_revenue_xaf} />}
                  />
                  <LedgerRow
                    label="Ventes de produits"
                    value={<Amount value={f.products_revenue_xaf} />}
                  />
                  <LedgerRow
                    variant="head"
                    label="Chiffre d’affaires réalisé"
                    value={<Amount value={f.revenue_xaf} />}
                  />
                  <LedgerRow
                    label="Consommables et coûts directs"
                    value={<Amount value={-f.service_direct_costs_xaf} tone="out" />}
                  />
                  <LedgerRow
                    label="Coût des produits vendus"
                    value={<Amount value={-f.product_costs_xaf} tone="out" />}
                  />
                  <LedgerRow
                    label="Commissions dues"
                    value={<Amount value={-f.commissions_due_xaf} tone="out" />}
                  />
                  <LedgerRow
                    label="Autres charges saisies"
                    value={<Amount value={-f.other_charges_xaf} tone="out" />}
                  />
                  <LedgerRow
                    variant="total"
                    label="Résultat de pilotage estimé"
                    value={<Amount value={f.estimated_result_xaf} size="lg" />}
                  />
                </Ledger>
                <p className="entry__meta">
                  Méthode : CA payé dans la période (hors lignes remboursées) − consommables sortis
                  du stock (ou coût direct estimé de la prestation) − coût d’achat des produits
                  vendus − commissions − charges saisies hors catégorie « commission ». Ce n’est ni
                  un résultat comptable ni un bénéfice fiscal.
                </p>
                {f.commission_category_charges_xaf > 0 && (
                  <Notice live={false} title="Charges « commission » non recomptées">
                    {f.commission_category_charges_xaf.toLocaleString('fr-FR')} FCFA saisis en
                    charges dans une catégorie « commission » ne sont pas déduits une deuxième fois
                    : les commissions sont déjà calculées par la caisse.
                  </Notice>
                )}
              </Sheet>
              <Sheet>
                <h2 className="section-title">Trésorerie</h2>
                <Ledger label="Encaissements">
                  <LedgerRow
                    label="Paiements reçus"
                    value={<Amount value={f.payments_xaf} tone="in" />}
                  />
                  <LedgerRow
                    label="Remboursements versés"
                    value={<Amount value={-f.refunds_xaf} tone="out" />}
                  />
                  <LedgerRow
                    variant="head"
                    label="Encaissements nets"
                    value={<Amount value={f.net_collected_xaf} />}
                  />
                  <LedgerRow
                    label="Commissions versées"
                    value={<Amount value={-f.commissions_paid_xaf} tone="out" />}
                  />
                  <LedgerRow
                    label="Autres charges saisies"
                    value={<Amount value={-f.other_charges_xaf} tone="out" />}
                  />
                  <LedgerRow
                    label="Achats de produits"
                    value={<Amount value={-f.purchases_xaf} tone="out" />}
                  />
                  <LedgerRow
                    variant="total"
                    label="Flux de trésorerie estimé"
                    value={<Amount value={f.estimated_cash_flow_xaf} size="lg" />}
                  />
                </Ledger>
                {f.pending_checkout_xaf > 0 && (
                  <p className="entry__meta">
                    {f.pending_checkout_count} note(s) en attente pour{' '}
                    {f.pending_checkout_xaf.toLocaleString('fr-FR')} FCFA : pas encore encaissées,
                    donc pas comptées.
                  </p>
                )}
                <h3 className="entry__subtitle">Par moyen de paiement</h3>
                {r.payment_methods.length === 0 ? (
                  <p className="entry__meta">Aucun paiement sur la période.</p>
                ) : (
                  <Ledger label="Moyens de paiement">
                    {r.payment_methods.map((m) => (
                      <LedgerRow
                        key={m.method}
                        label={methodLabels[m.method]}
                        meta={
                          m.refunds_xaf
                            ? `dont ${m.refunds_xaf.toLocaleString('fr-FR')} remboursés`
                            : undefined
                        }
                        value={<Amount value={m.net_xaf} />}
                      />
                    ))}
                  </Ledger>
                )}
              </Sheet>
            </div>

            <div className="page-pair">
              <Sheet>
                <h2 className="section-title">Activité</h2>
                <Ledger label="Activité">
                  <LedgerRow label="Rendez-vous" value={r.activity.appointments} />
                  <LedgerRow variant="sub" label="terminés" value={r.activity.completed} />
                  <LedgerRow variant="sub" label="annulés" value={r.activity.cancelled} />
                  <LedgerRow variant="sub" label="clients absents" value={r.activity.no_show} />
                  <LedgerRow variant="sub" label="sans rendez-vous" value={r.activity.walk_ins} />
                  <LedgerRow
                    label="Taux de rendez-vous honorés"
                    value={
                      r.activity.honoured_rate === null ? '—' : percent(r.activity.honoured_rate)
                    }
                  />
                  <LedgerRow
                    label="Taux d’annulation (dont absents)"
                    value={
                      r.activity.cancellation_rate === null
                        ? '—'
                        : percent(r.activity.cancellation_rate)
                    }
                  />
                  <LedgerRow label="Notes payées" value={f.paid_tickets} />
                  <LedgerRow label="Panier moyen" value={<Amount value={f.average_ticket_xaf} />} />
                  <LedgerRow label="Clients servis" value={r.clients.served} />
                  <LedgerRow
                    variant="sub"
                    label="revenus au moins 2 fois"
                    value={r.clients.returning}
                  />
                  <LedgerRow variant="sub" label="nouvelles fiches" value={r.clients.new_clients} />
                </Ledger>
              </Sheet>
              <Sheet>
                <h2 className="section-title">Chiffre d’affaires par jour</h2>
                {r.daily.length === 0 ? (
                  <p className="entry__meta">Aucune vente sur la période.</p>
                ) : (
                  <ul className="salon-bars" aria-label="Chiffre d’affaires par jour">
                    {r.daily.map((d) => (
                      <li key={d.day}>
                        <span className="salon-bars__label">
                          {new Date(`${d.day}T12:00:00`).toLocaleDateString('fr-FR', {
                            day: 'numeric',
                            month: 'short',
                          })}
                        </span>
                        <span className="salon-bars__track">
                          <span
                            className="salon-bars__fill"
                            style={{ width: `${Math.round((d.revenue_xaf / maxDay) * 100)}%` }}
                          />
                        </span>
                        <Amount value={d.revenue_xaf} size="sm" />
                      </li>
                    ))}
                  </ul>
                )}
                <h3 className="entry__subtitle">Fréquentation par jour de la semaine</h3>
                {r.weekdays.length === 0 ? (
                  <p className="entry__meta">Pas encore de rendez-vous terminés.</p>
                ) : (
                  <Ledger label="Jours de la semaine">
                    {r.weekdays.map((w) => (
                      <LedgerRow
                        key={w.weekday}
                        label={weekdayLabels[w.weekday - 1]}
                        meta={`${w.appointments} rendez-vous`}
                        value={<Amount value={w.revenue_xaf} />}
                      />
                    ))}
                  </Ledger>
                )}
              </Sheet>
            </div>

            <div className="page-pair">
              <Sheet>
                <h2 className="section-title">Prestations</h2>
                {r.services.length === 0 ? (
                  <p className="entry__meta">Aucune prestation payée.</p>
                ) : (
                  <>
                    <h3 className="entry__subtitle">Les plus demandées</h3>
                    <Ledger label="Prestations les plus demandées">
                      {r.services.slice(0, 8).map((s) => (
                        <LedgerRow
                          key={s.service_id}
                          label={s.name}
                          meta={`${s.count} fois`}
                          value={<Amount value={s.revenue_xaf} />}
                        />
                      ))}
                    </Ledger>
                    <h3 className="entry__subtitle">
                      Les plus rentables (après coûts et commissions)
                    </h3>
                    <Ledger label="Prestations les plus rentables">
                      {byMargin.map((s) => (
                        <LedgerRow
                          key={s.service_id}
                          label={s.name}
                          value={<Amount value={s.margin_xaf} />}
                        />
                      ))}
                    </Ledger>
                  </>
                )}
              </Sheet>
              <Sheet>
                <h2 className="section-title">Équipe</h2>
                <Ledger label="Performance par collaborateur">
                  {r.staff.map((s) => (
                    <LedgerRow
                      key={s.employee_id}
                      label={s.full_name}
                      meta={`${s.services} prestation(s) · commission ${s.commission_xaf.toLocaleString('fr-FR')} F`}
                      value={<Amount value={s.revenue_xaf} />}
                    />
                  ))}
                </Ledger>
                <h3 className="entry__subtitle">Produits les plus consommés</h3>
                {r.consumables.length === 0 ? (
                  <p className="entry__meta">Aucune consommation enregistrée.</p>
                ) : (
                  <Ledger label="Consommation">
                    {r.consumables.map((c) => (
                      <LedgerRow
                        key={c.supply_id}
                        label={c.name}
                        meta={`${c.quantity.toLocaleString('fr-FR')} ${unitLabels[c.unit]}`}
                        value={<Amount value={c.cost_xaf} />}
                      />
                    ))}
                  </Ledger>
                )}
              </Sheet>
            </div>
          </>
        )}
      </Loaded>
    </div>
  )
}
