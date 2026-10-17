import { useCallback, useEffect, useState } from 'react'
import { Button, Notice, Sheet } from '../../components/ui'
import { TurnstileChallenge } from '../orders/TurnstileChallenge'
import {
  clearGuestToken, guestAction, readGuestToken, saveGuestToken,
  type GuestBasketStatus, type GuestMembership,
} from '../../lib/restaurantGuests'
import type { RestaurantQrCatalog, RestaurantQrMenuItem } from '../../lib/restaurantQr'

const xaf = (n: bigint) => new Intl.NumberFormat('fr-FR').format(n) + ' FCFA'

/** Group guest UI. All decisions and amounts are confirmed by the server. */
export function RestaurantGuestBasket({
  table, catalog,
}: { table: string; catalog: RestaurantQrCatalog }) {
  const [participantToken, setParticipantToken] = useState(() => readGuestToken(table))
  const [code, setCode] = useState('')
  const [challenge, setChallenge] = useState('')
  const [resetKey, setResetKey] = useState(0)
  const [basket, setBasket] = useState<GuestBasketStatus | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')

  const refresh = useCallback(async () => {
    if (!participantToken) return
    const next = await guestAction<GuestBasketStatus>('status', table, { participantToken })
    if (next.expired) {
      clearGuestToken(table)
      setParticipantToken('')
      setBasket(null)
      setNotice('Cette session est terminée. Contactez le personnel pour un nouveau groupe.')
      return
    }
    setBasket(next)
  }, [participantToken, table])

  useEffect(() => {
    if (!participantToken) return
    let live = true
    const check = async () => {
      try {
        if (live) await refresh()
      } catch {
        if (live) setError('Synchronisation temporairement indisponible. Aucun nouvel envoi automatique.')
      }
    }
    void Promise.resolve().then(check)
    const timer = window.setInterval(() => { void check() }, 6000)
    return () => { live = false; window.clearInterval(timer) }
  }, [refresh, participantToken])

  async function run(task: () => Promise<void>) {
    if (busy) return
    setBusy(true)
    setError('')
    try { await task() }
    catch (err) {
      setError(err instanceof Error ? err.message : 'Action indisponible. Réessayez.')
    } finally { setBusy(false) }
  }

  async function join() {
    if (!/^[A-F0-9]{8}$/.test(code) || !challenge) return
    await run(async () => {
      try {
        const participant = await guestAction<GuestMembership>('join', table, { code, challenge })
        saveGuestToken(table, participant.participantToken)
        setParticipantToken(participant.participantToken)
        setNotice('Vous avez rejoint le groupe. Choisissez vos plats.')
        setCode('')
      } finally {
        setChallenge('')
        setResetKey(v => v + 1)
      }
    })
  }

  const lines = basket?.lines ?? []
  const myQuantity = (item: RestaurantQrMenuItem) =>
    lines.filter(l => l.mine && l.itemId === item.id)
      .reduce((sum, l) => sum + l.quantity, 0)
  const amount = lines.reduce(
    (total, line) => total + BigInt(line.quantity) * BigInt(line.unitPriceXaf), 0n,
  )
  async function changeItem(item: RestaurantQrMenuItem, delta: number) {
    const quantity = myQuantity(item) + delta
    if (quantity < 0 || quantity > 100 || !participantToken) return
    await run(async () => {
      await guestAction('choice', table, { participantToken, itemId: item.id, quantity })
      setNotice('Votre choix est enregistré dans le panier collectif.')
      try { await refresh() } catch {
        setError('Choix enregistré, mais affichage non actualisé : vérifiez avant de continuer.')
      }
    })
  }

  async function ready() {
    await run(async () => {
      const result = await guestAction<{ isLeader: boolean }>('ready', table, { participantToken })
      setNotice(result.isLeader
        ? 'Vous êtes responsable du groupe ! Vous validerez la commande lorsque chacun aura terminé.'
        : 'Votre choix est terminé. Le responsable du groupe pourra confirmer la commande.')
      try { await refresh() } catch { setError('État non actualisé : réessayez la synchronisation.') }
    })
  }
  async function submit() {
    if (!window.confirm('Envoyer les choix du groupe en cuisine ? Vérifiez que tout le monde a terminé.'))
      return
    await run(async () => {
      const result = await guestAction<{ reference: string }>('submit', table, { participantToken })
      setNotice('Commande collective envoyée : ' + result.reference)
      try { await refresh() } catch {
        setError('Commande envoyée, mais suivi indisponible. Ne confirmez pas un autre paiement.')
      }
    })
  }

  return (
    <section className="order-guest__part">
      <h2 className="section-title">Commande collective</h2>
      {error && <Notice tone="danger"><p>{error}</p></Notice>}
      {notice && <Notice tone="success"><p>{notice}</p></Notice>}
      {!participantToken ? (
        <Sheet>
          <p>
            Votre table est ouverte par le restaurant. Pour rejoindre le panier du groupe,
            demandez le code temporaire au personnel.
          </p>
          <label>
            Code du groupe
            <input
              value={code}
              maxLength={8}
              autoComplete="off"
              placeholder="Ex. A1B2C3D4"
              onChange={e => setCode(e.target.value.toUpperCase().replace(/[^A-F0-9]/g,''))}
            />
          </label>
          <TurnstileChallenge
            action="covi_restaurant_join"
            onToken={setChallenge}
            resetKey={resetKey}
          />
          <Button
            variant="primary"
            disabled={!/^[A-F0-9]{8}$/.test(code) || !challenge}
            busy={busy}
            onClick={() => void join()}
          >
            Rejoindre la commande de la table
          </Button>
        </Sheet>
      ) : basket?.groupStatus === 'submitted' ? (
        <Notice tone="calm">
          <p><strong>Commande {basket.orderReference ?? 'envoyée'}</strong></p>
          <p>Votre commande a été envoyée. Pour ajouter un article, demandez au personnel.</p>
          <p>Le paiement est enregistré exclusivement par la caisse du restaurant.</p>
        </Notice>
      ) : !basket ? (
        <p role="status">Chargement de votre groupe…</p>
      ) : (
        <>
          <Notice tone="calm">
            <p>{basket.participants ?? 0} participant(s) — {basket.readyParticipants ?? 0} choix terminé(s)</p>
            {basket.isLeader && <p><strong>Vous êtes responsable du groupe.</strong>
              Vous confirmerez l'envoi lorsque tout le monde sera prêt.</p>}
            {basket.ready && !basket.isLeader && <p>Votre choix est terminé. En attente du responsable.</p>}
          </Notice>
          <ul className="team-invites">
            {catalog.menu.map(item => {
              const quantity = myQuantity(item)
              return (
                <li key={item.id}>
                  <div>
                    <strong>{item.name}</strong>
                    <p className="muted">{xaf(BigInt(item.priceXaf))} · {item.category}</p>
                    {!item.available && <p className="muted">Épuisé</p>}
                  </div>
                  <div className="row-actions">
                    <Button disabled={busy || quantity===0} onClick={()=>void changeItem(item,-1)}>−</Button>
                    <span aria-label={`Quantité ${item.name}`}>{quantity}</span>
                    <Button disabled={busy || !item.available || quantity>=100}
                      onClick={()=>void changeItem(item,1)}>+</Button>
                  </div>
                </li>
              )
            })}
          </ul>
          <Sheet>
            <h3 className="section-title">Panier de la table</h3>
            {lines.length===0 ? <p className="muted">Aucun plat ajouté.</p> :
              lines.map((l,i)=><p key={i}>
                {l.mine?'Mon choix':'Choix du groupe'} : {l.quantity} × {l.name}
              </p>)}
            <p><strong>Total du groupe : {xaf(amount)}</strong></p>
          </Sheet>
          <div className="row-actions">
            <Button disabled={busy || basket.ready} onClick={()=>void ready()}>
              J’ai terminé mon choix
            </Button>
            {basket.isLeader && (
              <Button
                variant="primary"
                busy={busy}
                disabled={!basket.ready ||
                  basket.readyParticipants !== basket.participants || lines.length===0}
                onClick={()=>void submit()}
              >
                Envoyer la commande du groupe
              </Button>
            )}
          </div>
          <p className="muted">
            La commande ne part pas automatiquement quand tout le monde est prêt.
            Le responsable confirme l'envoi.
          </p>
        </>
      )}
    </section>
  )
}
