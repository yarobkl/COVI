import { useCallback } from 'react'
import {
  Amount,
  Badge,
  ButtonLink,
  Ledger,
  LedgerRow,
  Notice,
  PageHead,
  Sheet,
} from '../../components/ui'
import { salonApi, type SalonRole } from '../../lib/salon'
import { Loaded } from './SalonParts'
import { methodLabels, minutesLabel, salonTime, statusLabels } from './salonFormat'
import { useSalonLoad } from './useSalonLoad'

/** Étapes de démarrage, dans l'ordre où un salon les fait. */
function nextStep(setup: {
  configured: boolean
  services: number
  staff: number
  appointments: number
  tickets: number
}) {
  if (!setup.configured)
    return {
      text: 'Indiquez vos jours et heures d’ouverture.',
      href: '#/salon-reglages',
      label: 'Régler mon salon',
    }
  if (setup.services === 0)
    return {
      text: 'Écrivez vos prestations, avec leurs prix et durées.',
      href: '#/salon-services',
      label: 'Ajouter mes prestations',
    }
  if (setup.staff === 0)
    return {
      text: 'Ajoutez votre équipe : chaque coiffeur a son planning.',
      href: '#/salon-equipe',
      label: 'Ajouter mon équipe',
    }
  if (setup.appointments === 0)
    return {
      text: 'Notez votre premier rendez-vous ou installez un client de passage.',
      href: '#/salon-bookings',
      label: 'Ouvrir l’agenda',
    }
  if (setup.tickets === 0)
    return {
      text: 'Encaissez votre première prestation depuis l’agenda ou la caisse.',
      href: '#/salon-caisse',
      label: 'Ouvrir la caisse',
    }
  return null
}

/** Accueil du propriétaire ou du responsable : la journée du salon, ses chiffres et ses alertes. */
export function SalonHomePage({
  shopId,
  shopName,
}: {
  shopId: string
  shopName: string
  role: SalonRole
}) {
  const load = useCallback(() => salonApi.dashboard(shopId), [shopId])
  const data = useSalonLoad(load)
  const d = data.data
  const step = d ? nextStep(d.setup) : null
  const day = d?.day

  return (
    <div className="page-stack">
      <PageHead
        title={shopName}
        sub="Le cahier du salon : agenda, caisse, équipe et chiffres au même endroit."
      />
      <Loaded loading={data.loading} error={data.error}>
        {d && day && (
          <>
            {step && (
              <Notice
                live={false}
                title="Prochaine étape"
                actions={
                  <ButtonLink variant="primary" href={step.href}>
                    {step.label}
                  </ButtonLink>
                }
              >
                {step.text} Comment ça marche : un rendez-vous se prend avec un collaborateur ;
                quand le client a fini, « Encaisser » ouvre sa note ; au paiement, le stock, les
                commissions et vos chiffres se mettent à jour tout seuls.
              </Notice>
            )}

            <div className="page-pair">
              <Sheet>
                <h2 className="section-title">Aujourd’hui</h2>
                <Ledger label="Activité du jour">
                  <LedgerRow label="Rendez-vous prévus" value={day.activity.appointments} />
                  <LedgerRow variant="sub" label="terminés" value={day.activity.completed} />
                  <LedgerRow
                    variant="sub"
                    label="annulés ou clients absents"
                    value={day.activity.cancelled + day.activity.no_show}
                  />
                  <LedgerRow label="Clients servis" value={day.clients.served} />
                  <LedgerRow
                    label="Prestations réalisées"
                    value={day.services.reduce((s, x) => s + x.count, 0)}
                  />
                  <LedgerRow
                    variant="head"
                    label="Encaissé aujourd’hui (net)"
                    value={<Amount value={day.finance.net_collected_xaf} size="lg" />}
                  />
                  <LedgerRow
                    label="En attente d’encaissement"
                    value={<Amount value={day.finance.pending_checkout_xaf} />}
                  />
                </Ledger>
                {day.payment_methods.length > 0 && (
                  <Ledger label="Moyens de paiement du jour">
                    {day.payment_methods.map((m) => (
                      <LedgerRow
                        key={m.method}
                        variant="sub"
                        label={methodLabels[m.method]}
                        value={<Amount value={m.net_xaf} />}
                      />
                    ))}
                  </Ledger>
                )}
              </Sheet>
              <Sheet>
                <h2 className="section-title">Ce mois-ci</h2>
                <Ledger label="Finances du mois">
                  <LedgerRow
                    label="Chiffre d’affaires réalisé"
                    value={<Amount value={d.month.revenue_xaf} />}
                  />
                  <LedgerRow
                    label="Coûts directs et produits"
                    value={
                      <Amount
                        value={-(d.month.service_direct_costs_xaf + d.month.product_costs_xaf)}
                        tone="out"
                      />
                    }
                  />
                  <LedgerRow
                    label="Commissions dues"
                    value={<Amount value={-d.month.commissions_due_xaf} tone="out" />}
                  />
                  <LedgerRow
                    label="Autres charges saisies"
                    value={<Amount value={-d.month.other_charges_xaf} tone="out" />}
                  />
                  <LedgerRow
                    variant="total"
                    label="Résultat de pilotage estimé"
                    value={<Amount value={d.month.estimated_result_xaf} size="lg" />}
                  />
                </Ledger>
                <p className="entry__meta">
                  Estimation pour piloter, pas un résultat comptable. Détail et méthode dans{' '}
                  <a href="#/salon-rapports">Rapports</a>.
                </p>
              </Sheet>
            </div>

            <div className="page-pair">
              <Sheet>
                <h2 className="section-title">À surveiller</h2>
                {d.alerts.late.length === 0 &&
                d.alerts.upcoming.length === 0 &&
                d.alerts.low_stock.length === 0 &&
                d.alerts.open_tickets === 0 &&
                d.alerts.pending_requests === 0 &&
                d.alerts.stock_shortfalls === 0 ? (
                  <p className="entry__meta">Rien à signaler.</p>
                ) : (
                  <Ledger label="Alertes">
                    {d.alerts.late.map((a) => (
                      <LedgerRow
                        key={a.id}
                        label={<a href="#/salon-bookings">{a.client_name} est en retard</a>}
                        meta={`${salonTime(a.starts_at, d.time_zone)} · ${a.employee_name}`}
                        value={<Badge tone="danger">Retard</Badge>}
                      />
                    ))}
                    {d.alerts.upcoming.map((a) => (
                      <LedgerRow
                        key={a.id}
                        label={a.client_name}
                        meta={`${salonTime(a.starts_at, d.time_zone)} · ${a.employee_name}`}
                        value={<Badge tone="action">{statusLabels[a.status]}</Badge>}
                      />
                    ))}
                    {d.alerts.open_tickets > 0 && (
                      <LedgerRow
                        label={
                          <a href="#/salon-caisse">{d.alerts.open_tickets} note(s) à encaisser</a>
                        }
                        value={<Badge tone="waiting">Caisse</Badge>}
                      />
                    )}
                    {d.alerts.pending_requests > 0 && (
                      <LedgerRow
                        label={
                          <a href="#/salon-bookings">
                            {d.alerts.pending_requests} demande(s) à planifier
                          </a>
                        }
                        value={<Badge tone="waiting">Agenda</Badge>}
                      />
                    )}
                    {d.alerts.low_stock.map((s) => (
                      <LedgerRow
                        key={s.id}
                        label={<a href="#/salon-stock">{s.name}</a>}
                        meta="stock bas"
                        value={
                          <Badge tone="low">{s.quantity_on_hand.toLocaleString('fr-FR')}</Badge>
                        }
                      />
                    ))}
                    {d.alerts.stock_shortfalls > 0 && (
                      <LedgerRow
                        label={<a href="#/salon-stock">Écarts de stock cette semaine</a>}
                        meta="un produit manquait au moment d’une prestation : recomptez"
                        value={d.alerts.stock_shortfalls}
                      />
                    )}
                  </Ledger>
                )}
              </Sheet>
              <Sheet>
                <h2 className="section-title">Équipe présente</h2>
                {d.staff_today.length === 0 ? (
                  <p className="entry__meta">
                    Personne n’est prévu aujourd’hui (horaires, repos ou absences).
                  </p>
                ) : (
                  <Ledger label="Équipe du jour">
                    {d.staff_today.map((s) => (
                      <LedgerRow
                        key={s.employee_id}
                        label={
                          <>
                            <span
                              className="salon-dot"
                              style={{ background: s.agenda_color }}
                              aria-hidden="true"
                            />
                            {s.full_name}
                          </>
                        }
                        meta={`${s.starts_at}–${s.ends_at} · ${s.appointments} rendez-vous`}
                        value={
                          s.free_minutes_left > 0
                            ? `${minutesLabel(s.free_minutes_left)} libres`
                            : 'complet'
                        }
                      />
                    ))}
                  </Ledger>
                )}
                {day.staff.some((s) => s.revenue_xaf > 0) && (
                  <>
                    <h3 className="entry__subtitle">Chiffre du jour par collaborateur</h3>
                    <Ledger label="Chiffre par collaborateur">
                      {day.staff
                        .filter((s) => s.revenue_xaf > 0)
                        .map((s) => (
                          <LedgerRow
                            key={s.employee_id}
                            label={s.full_name}
                            meta={`${s.services} prestation(s) · commission ${s.commission_xaf.toLocaleString('fr-FR')} F`}
                            value={<Amount value={s.revenue_xaf} />}
                          />
                        ))}
                    </Ledger>
                  </>
                )}
              </Sheet>
            </div>
          </>
        )}
      </Loaded>
    </div>
  )
}
