import { useCallback, useRef, useState, type FormEvent } from 'react'
import {
  Amount,
  Badge,
  Button,
  Dialog,
  EmptyState,
  Ledger,
  LedgerRow,
  Notice,
  PageHead,
  Sheet,
} from '../../components/ui'
import { parseAmount } from '../../lib/format'
import {
  operationKey,
  salonApi,
  type CommissionMode,
  type PaymentMethod,
  type SalonRole,
  type SalonStaff,
  type StaffHours,
} from '../../lib/salon'
import { ActionMessage, Loaded, SalonTabs } from './SalonParts'
import { commissionLabel, methodLabels, roleLabels, weekdayLabels } from './salonFormat'
import { useSalonAction, useSalonLoad } from './useSalonLoad'

type Tab = 'staff' | 'commissions' | 'accounts'
type Draft = {
  id: string | null
  fullName: string
  jobTitle: string
  phone: string
  color: string
  active: boolean
  mode: CommissionMode
  percent: string
  fixed: string
  serviceIds: string[]
  hours: { weekday: number; on: boolean; starts: string; ends: string }[]
  absenceDay: string
  absenceReason: string
}

const emptyHours = () =>
  Array.from({ length: 7 }, (_, i) => ({
    weekday: i + 1,
    on: false,
    starts: '09:00',
    ends: '18:00',
  }))

/** Équipe du salon : fiches, habilitations, horaires, absences, commissions et comptes d'accès. */
export function SalonTeamPage({ shopId, role }: { shopId: string; role: SalonRole }) {
  const isOwner = role === 'owner'
  const [tab, setTab] = useState<Tab>('staff')
  const load = useCallback(async () => {
    const [staff, catalog, balances, accounts] = await Promise.all([
      salonApi.staff(shopId),
      salonApi.catalog(shopId),
      salonApi.commissionBalances(shopId),
      isOwner ? salonApi.staffAccounts(shopId) : Promise.resolve(null),
    ])
    return { staff, catalog, balances, accounts }
  }, [shopId, isOwner])
  const data = useSalonLoad(load)
  const action = useSalonAction()
  const [draft, setDraft] = useState<Draft | null>(null)
  const [invite, setInvite] = useState<{
    name: string
    role: Exclude<SalonRole, 'owner'>
    employeeId: string
  } | null>(null)
  const [code, setCode] = useState<string | null>(null)
  const [payout, setPayout] = useState<{
    employeeId: string
    name: string
    max: number
    amount: string
    method: PaymentMethod
    note: string
  } | null>(null)
  const payoutKey = useRef(operationKey())

  function open(s: SalonStaff | null) {
    const hours = emptyHours()
    for (const h of s?.hours ?? []) {
      hours[h.weekday - 1] = { weekday: h.weekday, on: true, starts: h.starts_at, ends: h.ends_at }
    }
    setDraft({
      id: s?.employee_id ?? null,
      fullName: s?.full_name ?? '',
      jobTitle: s?.job_title ?? 'Coiffeur',
      phone: s?.phone ?? '',
      color: s?.agenda_color ?? '#17408b',
      active: s?.active ?? true,
      mode: s?.commission_mode ?? 'none',
      percent: String(s?.commission_percent ?? ''),
      fixed: String(s?.commission_fixed_xaf ?? ''),
      serviceIds: s?.service_ids ?? [],
      hours,
      absenceDay: '',
      absenceReason: '',
    })
  }

  async function save(e: FormEvent) {
    e.preventDefault()
    if (!draft) return
    if (draft.fullName.trim().length < 2 || draft.jobTitle.trim().length < 2) {
      action.setIsError(true)
      action.setMessage('Indiquez le nom et la fonction (2 caractères au moins).')
      return
    }
    const hours: StaffHours[] = draft.hours
      .filter((h) => h.on)
      .map((h) => ({ weekday: h.weekday, starts_at: h.starts, ends_at: h.ends }))
    const ok = await action.run(async () => {
      const id = await salonApi.saveStaff(shopId, {
        id: draft.id,
        fullName: draft.fullName.trim(),
        jobTitle: draft.jobTitle.trim(),
        phone: draft.phone,
        commissionMode: draft.mode,
        commissionPercent: Number(draft.percent.replace(',', '.')) || 0,
        commissionFixedXaf: parseAmount(draft.fixed) ?? 0,
        color: draft.color,
        active: draft.active,
        serviceIds: draft.serviceIds,
      })
      await salonApi.setStaffHours(shopId, id, hours)
      if (draft.absenceDay)
        await salonApi.setAbsence(shopId, id, draft.absenceDay, true, draft.absenceReason)
      return id
    }, 'Fiche enregistrée.')
    if (ok) {
      setDraft(null)
      data.reload()
    }
  }

  const staff = data.data?.staff ?? []
  const services = (data.data?.catalog.services ?? []).filter((s) => s.active)
  const tabs = [
    { value: 'staff' as const, label: 'Collaborateurs' },
    { value: 'commissions' as const, label: 'Commissions' },
    ...(isOwner ? [{ value: 'accounts' as const, label: 'Accès à COVI' }] : []),
  ]

  return (
    <div className="page-stack">
      <PageHead
        title="Équipe"
        sub="Qui travaille, quand, pour quelles prestations, et ce que chacun touche."
        action={
          tab === 'staff' ? (
            <Button variant="primary" onClick={() => open(null)}>
              Ajouter un collaborateur
            </Button>
          ) : undefined
        }
      />
      <SalonTabs label="Équipe" tabs={tabs} value={tab} onChange={setTab} />
      <ActionMessage message={action.message} isError={action.isError} />
      <Loaded loading={data.loading} error={data.error}>
        {tab === 'staff' &&
          (staff.length === 0 ? (
            <EmptyState
              title="Aucun collaborateur"
              actions={
                <Button variant="primary" onClick={() => open(null)}>
                  Ajouter un collaborateur
                </Button>
              }
            >
              Ajoutez chaque personne qui reçoit des clients, vous compris si vous coiffez.
            </EmptyState>
          ) : (
            <Sheet>
              <Ledger label="Collaborateurs">
                {staff.map((s) => (
                  <LedgerRow
                    key={s.employee_id}
                    variant="link"
                    label={
                      <button type="button" className="ledger__open" onClick={() => open(s)}>
                        <span
                          className="salon-dot"
                          style={{ background: s.agenda_color }}
                          aria-hidden="true"
                        />
                        {s.full_name}
                      </button>
                    }
                    meta={[
                      s.job_title,
                      commissionLabel(
                        s.commission_mode,
                        s.commission_percent,
                        s.commission_fixed_xaf,
                      ),
                      s.hours.length
                        ? s.hours.map((h) => weekdayLabels[h.weekday - 1].slice(0, 3)).join(' ')
                        : 'horaires du salon',
                      s.account?.active ? `accès : ${roleLabels[s.account.role]}` : null,
                    ]
                      .filter(Boolean)
                      .join(' · ')}
                    value={s.active ? undefined : <Badge tone="low">Inactif</Badge>}
                  />
                ))}
              </Ledger>
            </Sheet>
          ))}

        {tab === 'commissions' && (
          <Sheet>
            <h2 className="section-title">Commissions</h2>
            <p className="entry__meta">
              Dues = commissions des prestations payées (hors remboursements). Une commission versée
              sort de la caisse mais n’est pas une charge de plus : elle est déjà comptée dans le
              résultat.
            </p>
            {(data.data?.balances ?? []).length === 0 ? (
              <p className="entry__meta">Aucun collaborateur.</p>
            ) : (
              <Ledger label="Commissions par collaborateur">
                {data.data!.balances.map((b) => (
                  <LedgerRow
                    key={b.employee_id}
                    label={
                      <>
                        {b.full_name}
                        {isOwner && b.balance_xaf > 0 && (
                          <button
                            type="button"
                            className="salon-link"
                            onClick={() =>
                              setPayout({
                                employeeId: b.employee_id,
                                name: b.full_name,
                                max: b.balance_xaf,
                                amount: String(b.balance_xaf),
                                method: 'cash',
                                note: '',
                              })
                            }
                          >
                            Verser
                          </button>
                        )}
                      </>
                    }
                    meta={`gagné ${b.earned_xaf.toLocaleString('fr-FR')} F · versé ${b.paid_xaf.toLocaleString('fr-FR')} F`}
                    value={<Amount value={b.balance_xaf} />}
                  />
                ))}
              </Ledger>
            )}
          </Sheet>
        )}

        {tab === 'accounts' && isOwner && data.data?.accounts && (
          <Sheet>
            <h2 className="section-title">Accès à COVI</h2>
            <p className="entry__meta">
              Chaque collaborateur utilise son propre compte COVI. Vous lui donnez un code à usage
              unique (valable 48 h) qu’il saisit dans « Rejoindre un salon ». Coiffeur : ses
              rendez-vous seulement. Caissier : agenda, clients et caisse. Responsable : tout sauf
              vos réglages, les accès et les commissions.
            </p>
            <Button
              variant="primary"
              onClick={() =>
                setInvite({ name: '', role: 'stylist', employeeId: staff[0]?.employee_id ?? '' })
              }
            >
              Donner un accès
            </Button>
            <Ledger label="Comptes">
              {data.data.accounts.members.map((m) => (
                <LedgerRow
                  key={m.id}
                  label={m.display_name}
                  meta={roleLabels[m.role]}
                  value={
                    m.active ? (
                      <Button
                        variant="ghost"
                        busy={action.busy}
                        onClick={() =>
                          void action
                            .run(() => salonApi.disableMember(shopId, m.id), 'Accès retiré.')
                            .then(() => data.reload())
                        }
                      >
                        Retirer l’accès
                      </Button>
                    ) : (
                      <Badge tone="low">Accès retiré</Badge>
                    )
                  }
                />
              ))}
              {data.data.accounts.invites.map((i) => (
                <LedgerRow
                  key={i.id}
                  label={i.display_name}
                  meta={`${roleLabels[i.role]} · code en attente`}
                  value={
                    <Button
                      variant="ghost"
                      onClick={() =>
                        void action
                          .run(() => salonApi.revokeInvite(shopId, i.id), 'Code annulé.')
                          .then(() => data.reload())
                      }
                    >
                      Annuler le code
                    </Button>
                  }
                />
              ))}
            </Ledger>
          </Sheet>
        )}
      </Loaded>

      {draft && (
        <Dialog open onClose={() => setDraft(null)} labelledBy="salon-staff-title" sheet>
          <form className="dialog__body" onSubmit={(e) => void save(e)}>
            <h2 className="dialog__title" id="salon-staff-title">
              {draft.id ? draft.fullName : 'Nouveau collaborateur'}
            </h2>
            <div className="form-grid">
              <label>
                Nom complet
                <input
                  value={draft.fullName}
                  maxLength={120}
                  required
                  onChange={(e) => setDraft({ ...draft, fullName: e.target.value })}
                />
              </label>
              <label>
                Fonction
                <input
                  value={draft.jobTitle}
                  maxLength={100}
                  required
                  onChange={(e) => setDraft({ ...draft, jobTitle: e.target.value })}
                />
              </label>
              <label>
                Téléphone professionnel <small>(facultatif)</small>
                <input
                  type="tel"
                  value={draft.phone}
                  onChange={(e) => setDraft({ ...draft, phone: e.target.value })}
                />
              </label>
              <label>
                Couleur dans l’agenda
                <input
                  type="color"
                  value={draft.color}
                  onChange={(e) => setDraft({ ...draft, color: e.target.value })}
                />
              </label>
              <fieldset className="salon-fieldset form-grid__full">
                <legend>Commission</legend>
                {!isOwner && (
                  <p className="entry__meta">Seul le propriétaire fixe les commissions.</p>
                )}
                <div className="form-grid">
                  <label>
                    Mode
                    <select
                      value={draft.mode}
                      disabled={!isOwner}
                      onChange={(e) =>
                        setDraft({ ...draft, mode: e.target.value as CommissionMode })
                      }
                    >
                      <option value="none">Aucune commission</option>
                      <option value="percent">Pourcentage du montant payé</option>
                      <option value="fixed">Montant fixe par prestation</option>
                    </select>
                  </label>
                  {draft.mode === 'percent' && (
                    <label>
                      Pourcentage
                      <input
                        inputMode="decimal"
                        value={draft.percent}
                        disabled={!isOwner}
                        onChange={(e) => setDraft({ ...draft, percent: e.target.value })}
                      />
                    </label>
                  )}
                  {draft.mode === 'fixed' && (
                    <label>
                      Montant par prestation (FCFA)
                      <input
                        inputMode="numeric"
                        value={draft.fixed}
                        disabled={!isOwner}
                        onChange={(e) => setDraft({ ...draft, fixed: e.target.value })}
                      />
                    </label>
                  )}
                </div>
                {draft.mode === 'percent' && (
                  <p className="entry__meta">
                    Exemple : une prestation de 10 000 FCFA à {draft.percent || '0'} % donne{' '}
                    {Math.round(
                      (10000 * (Number(draft.percent.replace(',', '.')) || 0)) / 100,
                    ).toLocaleString('fr-FR')}{' '}
                    FCFA de commission.
                  </p>
                )}
              </fieldset>
              <fieldset className="salon-fieldset form-grid__full">
                <legend>Prestations réalisables</legend>
                <p className="entry__meta">
                  Sans case cochée ici, il garde les prestations ouvertes à toute l’équipe.
                </p>
                <div className="salon-checks">
                  {services.map((s) => (
                    <label className="form-check" key={s.id}>
                      <input
                        type="checkbox"
                        checked={draft.serviceIds.includes(s.id)}
                        onChange={(e) =>
                          setDraft({
                            ...draft,
                            serviceIds: e.target.checked
                              ? [...draft.serviceIds, s.id]
                              : draft.serviceIds.filter((x) => x !== s.id),
                          })
                        }
                      />
                      {s.name}
                    </label>
                  ))}
                </div>
              </fieldset>
              <fieldset className="salon-fieldset form-grid__full">
                <legend>Jours et heures de travail</legend>
                <p className="entry__meta">
                  Aucun jour coché = il suit les horaires du salon. Jour non coché = repos.
                </p>
                {draft.hours.map((h, i) => (
                  <div className="salon-hours" key={h.weekday}>
                    <label className="form-check">
                      <input
                        type="checkbox"
                        checked={h.on}
                        onChange={(e) =>
                          setDraft({
                            ...draft,
                            hours: draft.hours.map((x, j) =>
                              j === i ? { ...x, on: e.target.checked } : x,
                            ),
                          })
                        }
                      />
                      {weekdayLabels[i]}
                    </label>
                    {h.on && (
                      <>
                        <input
                          type="time"
                          aria-label={`Début ${weekdayLabels[i]}`}
                          value={h.starts}
                          onChange={(e) =>
                            setDraft({
                              ...draft,
                              hours: draft.hours.map((x, j) =>
                                j === i ? { ...x, starts: e.target.value } : x,
                              ),
                            })
                          }
                        />
                        <input
                          type="time"
                          aria-label={`Fin ${weekdayLabels[i]}`}
                          value={h.ends}
                          onChange={(e) =>
                            setDraft({
                              ...draft,
                              hours: draft.hours.map((x, j) =>
                                j === i ? { ...x, ends: e.target.value } : x,
                              ),
                            })
                          }
                        />
                      </>
                    )}
                  </div>
                ))}
              </fieldset>
              <label>
                Jour d’absence à ajouter <small>(facultatif)</small>
                <input
                  type="date"
                  value={draft.absenceDay}
                  onChange={(e) => setDraft({ ...draft, absenceDay: e.target.value })}
                />
              </label>
              <label>
                Motif <small>(facultatif)</small>
                <input
                  value={draft.absenceReason}
                  maxLength={120}
                  onChange={(e) => setDraft({ ...draft, absenceReason: e.target.value })}
                />
              </label>
              {draft.id &&
                (staff.find((s) => s.employee_id === draft.id)?.absences.length ?? 0) > 0 && (
                  <div className="form-grid__full">
                    <p className="field__label">Absences prévues</p>
                    {staff
                      .find((s) => s.employee_id === draft.id)!
                      .absences.map((a) => (
                        <p key={a.day} className="entry__meta">
                          {new Date(`${a.day}T12:00:00`).toLocaleDateString('fr-FR', {
                            weekday: 'long',
                            day: 'numeric',
                            month: 'long',
                          })}
                          {a.reason ? ` · ${a.reason}` : ''}{' '}
                          <button
                            type="button"
                            className="salon-link"
                            onClick={() =>
                              void action
                                .run(
                                  () => salonApi.setAbsence(shopId, draft.id!, a.day, false, ''),
                                  'Absence retirée.',
                                )
                                .then(() => data.reload())
                            }
                          >
                            Retirer
                          </button>
                        </p>
                      ))}
                  </div>
                )}
              <label className="form-check">
                <input
                  type="checkbox"
                  checked={draft.active}
                  onChange={(e) => setDraft({ ...draft, active: e.target.checked })}
                />
                Travaille au salon (décochez s’il est parti : son historique reste)
              </label>
            </div>
            <ActionMessage message={action.message} isError={action.isError} />
            <div className="dialog__actions">
              <Button variant="ghost" onClick={() => setDraft(null)}>
                Fermer
              </Button>
              <Button type="submit" variant="primary" busy={action.busy}>
                Enregistrer
              </Button>
            </div>
          </form>
        </Dialog>
      )}

      {invite && (
        <Dialog
          open
          onClose={() => {
            setInvite(null)
            setCode(null)
          }}
          labelledBy="salon-invite-title"
          sheet
        >
          <div className="dialog__body">
            <h2 className="dialog__title" id="salon-invite-title">
              Donner un accès à COVI
            </h2>
            {code ? (
              <>
                <Notice tone="success" title="Code créé — valable 48 heures, une seule fois">
                  Donnez ce code à {invite.name}. Il le saisit dans COVI, « Rejoindre un salon »,
                  depuis son propre compte. Ne l’envoyez pas dans un groupe.
                </Notice>
                <p className="salon-code" aria-label="Code d’accès">
                  {code}
                </p>
              </>
            ) : (
              <div className="form-grid">
                <label>
                  Nom affiché
                  <input
                    value={invite.name}
                    maxLength={80}
                    onChange={(e) => setInvite({ ...invite, name: e.target.value })}
                  />
                </label>
                <label>
                  Rôle
                  <select
                    value={invite.role}
                    onChange={(e) =>
                      setInvite({ ...invite, role: e.target.value as Exclude<SalonRole, 'owner'> })
                    }
                  >
                    <option value="stylist">Coiffeur — ses rendez-vous</option>
                    <option value="cashier">Caissier — agenda, clients, caisse</option>
                    <option value="manager">Responsable — gestion du salon</option>
                  </select>
                </label>
                <label className="form-grid__full">
                  Fiche collaborateur
                  <select
                    value={invite.employeeId}
                    onChange={(e) => setInvite({ ...invite, employeeId: e.target.value })}
                  >
                    {invite.role !== 'stylist' && <option value="">Aucune</option>}
                    {staff.map((s) => (
                      <option key={s.employee_id} value={s.employee_id}>
                        {s.full_name}
                      </option>
                    ))}
                  </select>
                </label>
              </div>
            )}
            <ActionMessage message={action.message} isError={action.isError} />
            <div className="dialog__actions">
              <Button
                variant="ghost"
                onClick={() => {
                  setInvite(null)
                  setCode(null)
                  data.reload()
                }}
              >
                Fermer
              </Button>
              {!code && (
                <Button
                  variant="primary"
                  busy={action.busy}
                  disabled={
                    !invite.name.trim() || (invite.role === 'stylist' && !invite.employeeId)
                  }
                  onClick={() =>
                    void action
                      .run(() =>
                        salonApi.createInvite(shopId, {
                          displayName: invite.name.trim(),
                          role: invite.role,
                          employeeId: invite.employeeId || null,
                        }),
                      )
                      .then((r) => r && setCode(r.code))
                  }
                >
                  Créer le code
                </Button>
              )}
            </div>
          </div>
        </Dialog>
      )}

      {payout && (
        <Dialog open onClose={() => setPayout(null)} labelledBy="salon-payout-title">
          <div className="dialog__body">
            <h2 className="dialog__title" id="salon-payout-title">
              Verser une commission à {payout.name}
            </h2>
            <div className="form-grid">
              <label>
                Montant (FCFA, au plus {payout.max.toLocaleString('fr-FR')})
                <input
                  inputMode="numeric"
                  value={payout.amount}
                  onChange={(e) => setPayout({ ...payout, amount: e.target.value })}
                />
              </label>
              <label>
                Payé par
                <select
                  value={payout.method}
                  onChange={(e) =>
                    setPayout({ ...payout, method: e.target.value as PaymentMethod })
                  }
                >
                  {(Object.keys(methodLabels) as PaymentMethod[]).map((m) => (
                    <option key={m} value={m}>
                      {methodLabels[m]}
                    </option>
                  ))}
                </select>
              </label>
              <label className="form-grid__full">
                Note <small>(facultatif)</small>
                <input
                  value={payout.note}
                  maxLength={200}
                  onChange={(e) => setPayout({ ...payout, note: e.target.value })}
                />
              </label>
            </div>
            <ActionMessage message={action.message} isError={action.isError} />
            <div className="dialog__actions">
              <Button variant="ghost" onClick={() => setPayout(null)}>
                Fermer
              </Button>
              <Button
                variant="primary"
                busy={action.busy}
                onClick={() =>
                  void action
                    .run(
                      () =>
                        salonApi.payCommission(shopId, {
                          employeeId: payout.employeeId,
                          amountXaf: parseAmount(payout.amount) ?? 0,
                          method: payout.method,
                          note: payout.note,
                          key: payoutKey.current,
                        }),
                      'Versement enregistré.',
                    )
                    .then((r) => {
                      if (r) {
                        payoutKey.current = operationKey()
                        setPayout(null)
                        data.reload()
                      }
                    })
                }
              >
                Enregistrer le versement
              </Button>
            </div>
          </div>
        </Dialog>
      )}
    </div>
  )
}
