import { useCallback, useEffect, useState, type FormEvent } from 'react'
import {
  Amount,
  Button,
  Dialog,
  EmptyState,
  Ledger,
  LedgerRow,
  Notice,
  PageHead,
  SearchField,
  Sheet,
} from '../../components/ui'
import { salonApi, type ClientCard, type SalonRole } from '../../lib/salon'
import { ActionMessage, Loaded } from './SalonParts'
import { downloadCsv, statusLabels, whatsappHref } from './salonFormat'
import { useSalonAction, useSalonLoad } from './useSalonLoad'

type Draft = {
  id: string | null
  firstName: string
  lastName: string
  phone: string
  email: string
  preferences: string
  preferencesConsent: boolean
  reminderConsent: boolean
}

const blank: Draft = {
  id: null,
  firstName: '',
  lastName: '',
  phone: '',
  email: '',
  preferences: '',
  preferencesConsent: false,
  reminderConsent: false,
}

const dateFr = (iso: string | null) =>
  iso
    ? new Date(iso).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' })
    : '—'

/** Fichier clients du salon : recherche, fiche, historique, consentements, anonymisation. */
export function SalonClientsPage({ shopId, role }: { shopId: string; role: SalonRole }) {
  const canAdmin = role === 'owner' || role === 'manager'
  const [query, setQuery] = useState('')
  const [debounced, setDebounced] = useState('')
  useEffect(() => {
    const t = setTimeout(() => setDebounced(query), 250)
    return () => clearTimeout(t)
  }, [query])
  const load = useCallback(() => salonApi.searchClients(shopId, debounced), [shopId, debounced])
  const list = useSalonLoad(load)
  const action = useSalonAction()
  const [draft, setDraft] = useState<Draft | null>(null)
  const [dupes, setDupes] = useState<
    { id: string; first_name: string; last_name: string | null; phone: string | null }[]
  >([])
  const [card, setCard] = useState<ClientCard | null>(null)
  const [confirmErase, setConfirmErase] = useState(false)

  async function openCard(id: string) {
    const c = await action.run(() => salonApi.client(shopId, id))
    if (c) setCard(c)
  }

  async function save(e: FormEvent | null, force = false) {
    e?.preventDefault()
    if (!draft) return
    const r = await action.run(() => salonApi.saveClient(shopId, { ...draft, force }))
    if (!r) return
    if (r.status === 'possible_duplicate') {
      setDupes(r.duplicates)
      return
    }
    setDupes([])
    setDraft(null)
    action.setMessage('Fiche client enregistrée.')
    list.reload()
    if (card?.id === r.id) void openCard(r.id)
  }

  function exportCsv() {
    const rows = list.data ?? []
    downloadCsv('clients-salon.csv', [
      ['Prénom', 'Nom', 'Téléphone', 'Visites', 'Dernière visite'],
      ...rows.map((c) => [
        c.first_name,
        c.last_name ?? '',
        c.phone ?? '',
        c.visits,
        c.last_visit_at ? c.last_visit_at.slice(0, 10) : '',
      ]),
    ])
  }

  return (
    <div className="page-stack">
      <PageHead
        title="Clients"
        sub="Le fichier de vos clients : visites, dépenses, préférences (avec leur accord)."
        action={
          <Button
            variant="primary"
            onClick={() => {
              setDraft({ ...blank })
              setDupes([])
            }}
          >
            Nouveau client
          </Button>
        }
      />
      <SearchField
        label="Chercher un client"
        value={query}
        onChange={setQuery}
        placeholder="Nom ou téléphone"
      />
      <ActionMessage message={action.message} isError={action.isError} />
      <Loaded loading={list.loading && !list.data} error={list.error}>
        {(list.data ?? []).length === 0 ? (
          <EmptyState title={query ? 'Aucun client trouvé' : 'Aucun client enregistré'}>
            Créez une fiche à la première visite : elle se remplit ensuite toute seule avec les
            rendez-vous et les passages en caisse.
          </EmptyState>
        ) : (
          <Sheet>
            <Ledger label="Clients">
              {list.data!.map((c) => (
                <LedgerRow
                  key={c.id}
                  variant="link"
                  label={
                    <button
                      type="button"
                      className="ledger__open"
                      onClick={() => void openCard(c.id)}
                    >
                      {c.first_name} {c.last_name}
                    </button>
                  }
                  meta={[
                    c.phone,
                    c.visits ? `${c.visits} visite${c.visits > 1 ? 's' : ''}` : 'aucune visite',
                    c.last_visit_at ? `dernière le ${dateFr(c.last_visit_at)}` : null,
                  ]
                    .filter(Boolean)
                    .join(' · ')}
                />
              ))}
            </Ledger>
            {canAdmin && (
              <div className="row-actions">
                <Button variant="ghost" onClick={exportCsv}>
                  Exporter la liste (CSV)
                </Button>
              </div>
            )}
          </Sheet>
        )}
      </Loaded>

      {card && (
        <Dialog
          open
          onClose={() => {
            setCard(null)
            setConfirmErase(false)
          }}
          labelledBy="salon-client-title"
          sheet
        >
          <div className="dialog__body">
            <h2 className="dialog__title" id="salon-client-title">
              {card.first_name} {card.last_name}
            </h2>
            <Ledger label="Résumé">
              <LedgerRow label="Visites" value={card.visits} />
              <LedgerRow label="Absences sans prévenir" value={card.no_shows} />
              <LedgerRow
                label="Dépensé (net des remboursements)"
                value={<Amount value={card.total_spent_xaf} />}
              />
              <LedgerRow label="Dernière visite" value={dateFr(card.last_visit_at)} />
            </Ledger>
            {card.phone && (
              <p className="row-actions">
                <a className="btn btn--ghost" href={`tel:${card.phone}`}>
                  Appeler
                </a>
                {card.reminder_consent && (
                  <a
                    className="btn btn--ghost"
                    href={whatsappHref(card.phone, `Bonjour ${card.first_name}, `)}
                    target="_blank"
                    rel="noreferrer"
                  >
                    Préparer un message WhatsApp
                  </a>
                )}
              </p>
            )}
            {!card.reminder_consent && card.phone && (
              <p className="entry__meta">
                Pas d’accord pour les rappels : ne lui envoyez pas de message commercial.
              </p>
            )}
            {card.preferences && (
              <Notice live={false} title="Préférences (avec son accord)">
                {card.preferences}
              </Notice>
            )}
            {card.upcoming.length > 0 && (
              <>
                <h3 className="entry__subtitle">Prochains rendez-vous</h3>
                <Ledger label="Prochains rendez-vous">
                  {card.upcoming.map((u) => (
                    <LedgerRow
                      key={u.id}
                      label={dateFr(u.starts_at)}
                      meta={u.employee_name}
                      value={statusLabels[u.status]}
                    />
                  ))}
                </Ledger>
              </>
            )}
            <h3 className="entry__subtitle">Historique</h3>
            {card.history.length === 0 ? (
              <p className="entry__meta">Pas encore de visite.</p>
            ) : (
              <Ledger label="Historique">
                {card.history.map((h) => (
                  <LedgerRow
                    key={h.id}
                    label={dateFr(h.starts_at)}
                    meta={[h.services, h.employee_name].filter(Boolean).join(' · ')}
                    value={statusLabels[h.status]}
                  />
                ))}
              </Ledger>
            )}
            {canAdmin && !card.anonymized && (
              <div className="row-actions">
                {!confirmErase ? (
                  <Button variant="ghost" onClick={() => setConfirmErase(true)}>
                    Effacer ses informations personnelles…
                  </Button>
                ) : (
                  <Notice
                    tone="danger"
                    title="Anonymiser cette fiche ?"
                    actions={
                      <>
                        <Button
                          variant="danger"
                          solid
                          busy={action.busy}
                          onClick={() =>
                            void action
                              .run(
                                () => salonApi.anonymizeClient(shopId, card.id),
                                'Fiche anonymisée.',
                              )
                              .then(() => {
                                setCard(null)
                                setConfirmErase(false)
                                list.reload()
                              })
                          }
                        >
                          Anonymiser
                        </Button>
                        <Button variant="ghost" onClick={() => setConfirmErase(false)}>
                          Garder
                        </Button>
                      </>
                    }
                  >
                    Nom, téléphone, e-mail et préférences sont effacés définitivement. Les visites
                    et montants restent, sans nom, pour vos comptes.
                  </Notice>
                )}
              </div>
            )}
            <ActionMessage message={action.message} isError={action.isError} />
            <div className="dialog__actions">
              <Button
                variant="ghost"
                onClick={() =>
                  downloadCsv(`client-${card.first_name}.csv`, [
                    ['Champ', 'Valeur'],
                    ['Prénom', card.first_name],
                    ['Nom', card.last_name ?? ''],
                    ['Téléphone', card.phone ?? ''],
                    ['E-mail', card.email ?? ''],
                    ['Préférences', card.preferences ?? ''],
                    ['Accord rappels', card.reminder_consent ? 'oui' : 'non'],
                    ['Visites', card.visits],
                    ...card.history.map((h) => [
                      'Visite',
                      `${h.starts_at.slice(0, 10)} ${h.services ?? ''} (${statusLabels[h.status]})`,
                    ]),
                  ])
                }
              >
                Exporter sa fiche
              </Button>
              {!card.anonymized && (
                <Button
                  onClick={() => {
                    setDraft({
                      id: card.id,
                      firstName: card.first_name,
                      lastName: card.last_name ?? '',
                      phone: card.phone ?? '',
                      email: card.email ?? '',
                      preferences: card.preferences ?? '',
                      preferencesConsent: card.preferences_consent,
                      reminderConsent: card.reminder_consent,
                    })
                    setDupes([])
                  }}
                >
                  Modifier
                </Button>
              )}
              <Button variant="secondary" onClick={() => setCard(null)}>
                Fermer
              </Button>
            </div>
          </div>
        </Dialog>
      )}

      {draft && (
        <Dialog open onClose={() => setDraft(null)} labelledBy="salon-client-edit-title" sheet>
          <form className="dialog__body" onSubmit={(e) => void save(e)}>
            <h2 className="dialog__title" id="salon-client-edit-title">
              {draft.id ? 'Modifier la fiche' : 'Nouveau client'}
            </h2>
            <div className="form-grid">
              <label>
                Prénom
                <input
                  value={draft.firstName}
                  maxLength={80}
                  required
                  onChange={(e) => setDraft({ ...draft, firstName: e.target.value })}
                />
              </label>
              <label>
                Nom <small>(facultatif)</small>
                <input
                  value={draft.lastName}
                  maxLength={80}
                  onChange={(e) => setDraft({ ...draft, lastName: e.target.value })}
                />
              </label>
              <label>
                Téléphone <small>(facultatif)</small>
                <input
                  type="tel"
                  value={draft.phone}
                  onChange={(e) => setDraft({ ...draft, phone: e.target.value })}
                />
              </label>
              <label>
                E-mail <small>(facultatif)</small>
                <input
                  type="email"
                  value={draft.email}
                  maxLength={160}
                  onChange={(e) => setDraft({ ...draft, email: e.target.value })}
                />
              </label>
              <label className="form-check form-grid__full">
                <input
                  type="checkbox"
                  checked={draft.reminderConsent}
                  onChange={(e) => setDraft({ ...draft, reminderConsent: e.target.checked })}
                />
                Le client accepte de recevoir des rappels de rendez-vous
              </label>
              <label className="form-check form-grid__full">
                <input
                  type="checkbox"
                  checked={draft.preferencesConsent}
                  onChange={(e) =>
                    setDraft({
                      ...draft,
                      preferencesConsent: e.target.checked,
                      preferences: e.target.checked ? draft.preferences : '',
                    })
                  }
                />
                Le client accepte qu’on note ses préférences de coiffure
              </label>
              {draft.preferencesConsent && (
                <label className="form-grid__full">
                  Préférences{' '}
                  <small>(seulement l’utile : coupe, produits, allergies déclarées)</small>
                  <textarea
                    value={draft.preferences}
                    maxLength={500}
                    onChange={(e) => setDraft({ ...draft, preferences: e.target.value })}
                  />
                </label>
              )}
            </div>
            {dupes.length > 0 && (
              <Notice
                tone="danger"
                title="Ce client existe peut-être déjà"
                actions={
                  <>
                    {dupes.map((d) => (
                      <Button
                        key={d.id}
                        variant="ghost"
                        onClick={() => {
                          setDraft(null)
                          setDupes([])
                          void openCard(d.id)
                        }}
                      >
                        Ouvrir {d.first_name} {d.last_name ?? ''}
                      </Button>
                    ))}
                    <Button
                      variant="secondary"
                      busy={action.busy}
                      onClick={() => void save(null, true)}
                    >
                      Créer quand même
                    </Button>
                  </>
                }
              >
                {dupes
                  .map(
                    (d) => `${d.first_name} ${d.last_name ?? ''}${d.phone ? ` (${d.phone})` : ''}`,
                  )
                  .join(', ')}
              </Notice>
            )}
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
    </div>
  )
}
