import { useCallback, useEffect, useRef, useState, type FormEvent } from 'react'
import { Button, Notice, PageHead, Sheet } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import type { Tables } from '../../lib/database.types'

type Table = Tables<'restaurant_tables'>
type Session = Tables<'restaurant_table_sessions'>
type Participant = Tables<'restaurant_participants'>
type Line = Tables<'restaurant_session_lines'>
type Item = Tables<'restaurant_menu_items'>
type Payment = Tables<'restaurant_cash_payments'>

const formatXaf = (amount: bigint) => new Intl.NumberFormat('fr-FR').format(amount) + ' FCFA'
const toXaf = (value: number) => BigInt(value)

/**
 * Private owner's desk. Exercises the transactional server engine without opening
 * an unsafe customer QR endpoint or falsely attributing actions to waitresses.
 */
export function RestaurantOrdersPage({ shopId }: { shopId: string }) {
  const [tables, setTables] = useState<Table[]>([])
  const [sessions, setSessions] = useState<Session[]>([])
  const [participants, setParticipants] = useState<Participant[]>([])
  const [lines, setLines] = useState<Line[]>([])
  const [items, setItems] = useState<Item[]>([])
  const [payments, setPayments] = useState<Payment[]>([])
  const [sessionId, setSessionId] = useState('')
  const [tableId, setTableId] = useState('')
  const [people, setPeople] = useState(2)
  const [memberId, setMemberId] = useState('')
  const [itemId, setItemId] = useState('')
  const [quantity, setQuantity] = useState(1)
  const [cash, setCash] = useState('')
  const [acknowledgedCash, setAcknowledgedCash] = useState(false)
  const [busy, setBusy] = useState(false)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  // Keep the same idempotency key on network failure; a new receipt starts a new operation.
  const cashOperation = useRef(crypto.randomUUID())

  const refresh = useCallback(async () => {
    const [tablesResponse, sessionsResponse, menuResponse] = await Promise.all([
      supabase.from('restaurant_tables').select('*')
        .eq('shop_id', shopId).eq('active', true).order('label').limit(1000),
      supabase.from('restaurant_table_sessions').select('*')
        .eq('shop_id', shopId).in('status', ['collecting', 'submitted'])
        .order('created_at', { ascending: false }).limit(1000),
      supabase.from('restaurant_menu_items').select('*')
        .eq('shop_id', shopId).order('name').limit(1000),
    ])
    if (tablesResponse.error || sessionsResponse.error || menuResponse.error)
      throw new Error('Impossible de lire les tables, les additions ou la carte.')
    if ((tablesResponse.data?.length ?? 0) >= 1000
        || (sessionsResponse.data?.length ?? 0) >= 1000
        || (menuResponse.data?.length ?? 0) >= 1000)
      throw new Error('Liste incomplète : la caisse est bloquée jusqu’à récupération intégrale.')

    const active = sessionsResponse.data ?? []
    const sessionIds = active.map(row => row.id)
    let recentParticipants: Participant[] = []
    let recentLines: Line[] = []
    let recentPayments: Payment[] = []
    if (sessionIds.length) {
      const [participantsResponse, linesResponse, paymentsResponse] = await Promise.all([
        supabase.from('restaurant_participants').select('*')
          .eq('shop_id', shopId).in('session_id', sessionIds)
          .order('created_at', { ascending: true }).limit(1000),
        supabase.from('restaurant_session_lines').select('*')
          .eq('shop_id', shopId).in('session_id', sessionIds)
          .order('created_at', { ascending: true }).limit(1000),
        supabase.from('restaurant_cash_payments').select('*')
          .eq('shop_id', shopId).in('session_id', sessionIds).limit(1000),
      ])
      if (participantsResponse.error || linesResponse.error || paymentsResponse.error)
        throw new Error('Impossible de récupérer les lignes et paiements des tables ouvertes.')
      if ((participantsResponse.data?.length ?? 0)>=1000
          || (linesResponse.data?.length ?? 0)>=1000
          || (paymentsResponse.data?.length ?? 0)>=1000)
        throw new Error('Addition incomplète : encaissement bloqué par sécurité.')
      recentParticipants = participantsResponse.data ?? []
      recentLines = linesResponse.data ?? []
      recentPayments = paymentsResponse.data ?? []
    }
    setTables(tablesResponse.data ?? [])
    setSessions(active)
    setParticipants(recentParticipants)
    setLines(recentLines)
    setItems(menuResponse.data ?? [])
    setPayments(recentPayments)
    setSessionId(old => active.some(row=>row.id===old) ? old : active[0]?.id ?? '')
  }, [shopId])

  useEffect(() => {
    let mounted = true
    void Promise.resolve()
      .then(refresh)
      .catch(() => {
        if (mounted) setError('Les opérations restaurant ne sont pas disponibles sur cette base.')
      })
      .finally(() => {
        if (mounted) setLoading(false)
      })
    return () => {
      mounted = false
    }
  }, [refresh])

  async function run(operation: () => Promise<unknown>, success: string) {
    if (busy) return
    setBusy(true)
    setError('')
    setNotice('')
    try {
      await operation()
      await refresh()
      setNotice(success)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Opération refusée par COVI.')
    } finally {
      setBusy(false)
    }
  }

  const activeSession = sessions.find((x) => x.id === sessionId)
  const group = participants.filter((x) => x.session_id === sessionId)
  const activeLines = lines.filter((x) => x.session_id === sessionId)
  const paid = payments.filter((x) => x.session_id === sessionId)
  const total = activeLines
    .filter((x) => x.status !== 'draft')
    .reduce((v, x) => v + toXaf(x.unit_price_xaf) * BigInt(x.quantity), 0n)
  const received = paid.reduce((v, x) => v + toXaf(x.amount_xaf), 0n)
  const balance = total - received
  const leader = group.find((x) => x.is_leader)
  const allReady = group.length > 0 && group.every((x) => x.ready)
  const selectedItem = items.find((x) => x.id === itemId)
  const selectedParticipant = group.find((x) => x.id === memberId) ?? group[0]

  async function rpc<T>(name: string, args: Record<string, unknown>) {
    // All operations are defined in typed Supabase RPC signatures; the function
    // name remains internal and never comes from input or URL parameters.
    const { data, error } = await supabase.rpc(name as 'restaurant_open_table', args as never)
    if (error) throw error
    return data as T
  }

  async function openTable(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    await run(async () => {
      const id = await rpc<string>('restaurant_open_table', {
        p_shop: shopId,
        p_table: tableId,
        p_guest_count: people,
      })
      setSessionId(id)
    }, 'Une session a été ouverte pour cette table.')
  }

  async function addChoice(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!selectedParticipant || !selectedItem) {
      setError('Choisissez un participant et un article.')
      return
    }
    await run(
      () =>
        rpc('restaurant_choose_item', {
          p_shop: shopId,
          p_session: sessionId,
          p_participant: selectedParticipant.id,
          p_item: selectedItem.id,
          p_quantity: quantity,
        }),
      'Choix enregistré dans le panier commun.',
    )
  }

  async function addStaff(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!selectedItem) {
      setError('Sélectionnez un article.')
      return
    }
    await run(
      () =>
        rpc('restaurant_staff_add_item', {
          p_shop: shopId,
          p_session: sessionId,
          p_item: selectedItem.id,
          p_quantity: quantity,
        }),
      'Article ajouté à l’addition en cours.',
    )
  }

  async function captureCash(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const amount = Number(cash)
    if (
      !acknowledgedCash ||
      !Number.isSafeInteger(amount) ||
      amount <= 0 ||
      BigInt(amount) > balance
    ) {
      setError('Confirmez les espèces réellement reçues et vérifiez le montant restant.')
      return
    }
    await run(async () => {
      await rpc<boolean>('restaurant_capture_cash', {
        p_shop: shopId,
        p_session: sessionId,
        p_amount: amount,
        p_operation_id: cashOperation.current,
      })
      cashOperation.current = crypto.randomUUID()
      setCash('')
      setAcknowledgedCash(false)
    }, 'Encaissement enregistré. La table sera libérée uniquement si le solde est entièrement réglé.')
  }

  return (
    <div className="page-stack">
      <PageHead
        title="Service & caisse"
        sub="Commandes de table et règlements, sous le contrôle du propriétaire."
      />
      <Notice tone="calm">
        <p>
          Premier parcours interne uniquement : les clients ne peuvent pas encore commander depuis
          leur QR. Les actions réalisées ici sont enregistrées par le propriétaire connecté ; la
          gestion des accès serveurs suivra.
        </p>
      </Notice>
      {error && (
        <Notice tone="danger">
          <p>{error}</p>
        </Notice>
      )}
      {notice && (
        <Notice tone="success">
          <p>{notice}</p>
        </Notice>
      )}
      {loading ? (
        <Sheet>
          <p>Chargement du restaurant…</p>
        </Sheet>
      ) : (
        <>
          <Sheet aria-label="Ouverture de table">
            <h2 className="section-title">Ouvrir une table</h2>
            <form className="form-grid" onSubmit={(e) => void openTable(e)}>
              <label>
                Table
                <select required value={tableId} onChange={(e) => setTableId(e.target.value)}>
                  <option value="">Choisir une table</option>
                  {tables.map((t) => (
                    <option value={t.id} key={t.id}>
                      {t.label} · {t.capacity} places
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Clients présents
                <input
                  type="number"
                  min={1}
                  max={50}
                  value={people}
                  onChange={(e) => setPeople(Number(e.target.value))}
                  required
                />
              </label>
              <Button type="submit" variant="primary" busy={busy} disabled={!tableId}>
                Commencer la tablée
              </Button>
            </form>
            <p className="muted">
              Une table déjà occupée refusera toute nouvelle session. Le nombre de personnes n’est
              pas limité par les places de la table.
            </p>
          </Sheet>
          <Sheet aria-label="Tables en cours">
            <h2 className="section-title">Tables avec addition ouverte</h2>
            {sessions.length === 0 ? (
              <p className="muted">Aucune table en cours.</p>
            ) : (
              <label>
                Suivre une table
                <select
                  value={sessionId}
                  onChange={(e) => {
                    setSessionId(e.target.value)
                    setCash('')
                    setAcknowledgedCash(false)
                  }}
                >
                  {sessions.map((s) => {
                    const t = tables.find((x) => x.id === s.table_id)
                    return (
                      <option key={s.id} value={s.id}>
                        Table {t?.label ?? '?'} — {s.order_reference ?? 'Choix en cours'}
                      </option>
                    )
                  })}
                </select>
              </label>
            )}
          </Sheet>
          {activeSession && (
            <Sheet aria-label="Addition de la table">
              <h2 className="section-title">{activeSession.order_reference ?? 'Choix en cours'}</h2>
              <p className="muted">
                Table {tables.find((t) => t.id === activeSession.table_id)?.label ?? '—'} ·{' '}
                {activeSession.guest_count} personnes déclarées ·{' '}
                {activeSession.status === 'collecting' ? 'Panier collectif' : 'Commande envoyée'}
              </p>
              {activeSession.status === 'collecting' && (
                <>
                  <h3 className="section-title">Participants</h3>
                  {group.map((p, i) => (
                    <div className="row-actions" key={p.id}>
                      <span>
                        {p.is_leader ? 'Responsable du groupe' : `Client ${i + 1}`} —{' '}
                        {p.ready ? 'Choix terminé' : 'Choix en cours'}
                      </span>
                      {!p.ready && (
                        <Button
                          disabled={busy}
                          onClick={() =>
                            void run(
                              () =>
                                rpc('restaurant_mark_ready', {
                                  p_shop: shopId,
                                  p_session: sessionId,
                                  p_participant: p.id,
                                }),
                              'Choix terminé. Le premier à terminer devient responsable.',
                            )
                          }
                        >
                          J’ai terminé mon choix
                        </Button>
                      )}
                    </div>
                  ))}
                  <Button
                    disabled={busy}
                    onClick={() =>
                      void run(
                        () =>
                          rpc('restaurant_add_participant', {
                            p_shop: shopId,
                            p_session: sessionId,
                          }),
                        'Un participant a rejoint la commande.',
                      )
                    }
                  >
                    Ajouter un participant
                  </Button>
                  <h3 className="section-title">Choix individuel</h3>
                  <form className="form-grid" onSubmit={(e) => void addChoice(e)}>
                    <label>
                      Participant
                      <select
                        value={selectedParticipant?.id ?? ''}
                        onChange={(e) => setMemberId(e.target.value)}
                      >
                        {group.map((p, i) => (
                          <option key={p.id} value={p.id}>
                            {p.is_leader ? 'Responsable' : `Client ${i + 1}`}
                          </option>
                        ))}
                      </select>
                    </label>
                    <label>
                      Plat ou boisson
                      <select value={itemId} onChange={(e) => setItemId(e.target.value)}>
                        <option value="">Choisir</option>
                        {items
                          .filter((x) => x.available)
                          .map((i) => (
                            <option value={i.id} key={i.id}>
                              {i.name} · {formatXaf(BigInt(i.price_xaf))}
                            </option>
                          ))}
                      </select>
                    </label>
                    <label>
                      Quantité
                      <input
                        type="number"
                        min={1}
                        max={100}
                        value={quantity}
                        onChange={(e) => setQuantity(Number(e.target.value))}
                      />
                    </label>
                    <Button
                      type="submit"
                      disabled={!selectedParticipant || !selectedItem}
                      busy={busy}
                    >
                      Ajouter au panier
                    </Button>
                  </form>
                  <p className="muted">
                    Le premier client qui termine devient responsable. Seul ce responsable pourra
                    valider le groupe ; aucune commande n’est transmise automatiquement.
                  </p>
                  <Button
                    variant="primary"
                    busy={busy}
                    disabled={!leader || !allReady || activeLines.length === 0}
                    onClick={() =>
                      void run(
                        () =>
                          rpc('restaurant_submit_group', {
                            p_shop: shopId,
                            p_session: sessionId,
                            p_leader: leader?.id,
                          }),
                        'Commande collective envoyée.',
                      )
                    }
                  >
                    Envoyer la commande du groupe
                  </Button>
                </>
              )}
              {activeSession.status === 'submitted' && (
                <>
                  <h3 className="section-title">Ajouter à l’addition</h3>
                  <form className="form-grid" onSubmit={(e) => void addStaff(e)}>
                    <label>
                      Article
                      <select value={itemId} onChange={(e) => setItemId(e.target.value)}>
                        <option value="">Choisir</option>
                        {items
                          .filter((x) => x.available)
                          .map((i) => (
                            <option value={i.id} key={i.id}>
                              {i.name} · {formatXaf(BigInt(i.price_xaf))}
                            </option>
                          ))}
                      </select>
                    </label>
                    <label>
                      Quantité
                      <input
                        type="number"
                        min={1}
                        max={100}
                        value={quantity}
                        onChange={(e) => setQuantity(Number(e.target.value))}
                      />
                    </label>
                    <Button type="submit" disabled={!selectedItem} busy={busy}>
                      Ajouter une commande complémentaire
                    </Button>
                  </form>
                </>
              )}
              <h3 className="section-title">Articles de la table</h3>
              {activeLines.map((l) => (
                <div key={l.id} className="row-actions">
                  <span>
                    {l.quantity} × {items.find((i) => i.id === l.menu_item_id)?.name ?? 'Article'} —{' '}
                    {formatXaf(BigInt(l.quantity) * BigInt(l.unit_price_xaf))} ·{' '}
                    {l.status === 'draft'
                      ? 'Brouillon'
                      : l.status === 'served'
                        ? 'Servi'
                        : 'En service'}
                  </span>
                  {l.status === 'ordered' && (
                    <Button
                      busy={busy}
                      onClick={() =>
                        void run(
                          () => rpc('restaurant_mark_served', { p_shop: shopId, p_line: l.id }),
                          'Article déclaré servi.',
                        )
                      }
                    >
                      Marquer servi
                    </Button>
                  )}
                </div>
              ))}
              {activeSession.status === 'submitted' && (
                <div className="form-grid">
                  <p>
                    <strong>À facturer : {formatXaf(total)}</strong>
                  </p>
                  <p>Déjà encaissé : {formatXaf(received)}</p>
                  <p>
                    <strong>Solde : {formatXaf(balance)}</strong>
                  </p>
                  <form className="form-grid" onSubmit={(e) => void captureCash(e)}>
                    <label>
                      Espèces réellement reçues (FCFA)
                      <input
                        type="number"
                        min={1}
                        step={1}
                        required
                        value={cash}
                        onChange={(e) => {
                          setCash(e.target.value)
                          cashOperation.current = crypto.randomUUID()
                        }}
                      />
                    </label>
                    <label>
                      <input
                        type="checkbox"
                        checked={acknowledgedCash}
                        onChange={(e) => setAcknowledgedCash(e.target.checked)}
                      />{' '}
                      Je confirme avoir reçu les espèces
                    </label>
                    <Button
                      variant="primary"
                      type="submit"
                      busy={busy}
                      disabled={!acknowledgedCash || !cash}
                    >
                      Enregistrer l’encaissement
                    </Button>
                  </form>
                  <p className="muted">
                    Une somme partielle ne libère jamais la table. Le règlement final clôture la
                    session et rend le QR permanent disponible pour une nouvelle tablée.
                  </p>
                </div>
              )}
            </Sheet>
          )}
        </>
      )}
    </div>
  )
}
