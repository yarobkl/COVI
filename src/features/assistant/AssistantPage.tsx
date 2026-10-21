import { useRef, useState, type FormEvent } from 'react'
import { Button, Notice, PageHead, Sheet } from '../../components/ui'
import { askCoviAssistant } from '../../lib/assistant'
import type { Shop } from '../../lib/types'
import './assistant.css'

type Exchange = { id: number; question: string; answer?: string; error?: string }

const ideas: Record<string, string[]> = {
  retail: [
    "Quel est mon chiffre d'affaires aujourd'hui ?",
    'Que dois-je surveiller dans mon stock ?',
    'Comment mieux maîtriser mes charges ?',
  ],
  restaurant: [
    'Comment mieux organiser mon service ?',
    'Comment réduire le gaspillage alimentaire ?',
    'Quels indicateurs suivre pour mon restaurant ?',
  ],
  salon: [
    'Comment améliorer mes réservations ?',
    'Quels indicateurs suivre pour mon salon ?',
    'Comment fidéliser mes clients ?',
  ],
}

/** Assistant consultatif : pas de modification d'opérations, pas d'historique conservé à distance. */
export function AssistantPage({ shop }: { shop: Shop }) {
  const [question, setQuestion] = useState('')
  const [accepted, setAccepted] = useState(false)
  const [busy, setBusy] = useState(false)
  const [exchanges, setExchanges] = useState<Exchange[]>([])
  const nextId = useRef(0)
  const pending = useRef(false)
  const sector =
    shop.business_kind === 'restaurant' || shop.business_kind === 'salon'
      ? shop.business_kind
      : 'retail'

  const send = async (value: string) => {
    const text = value.trim()
    if (pending.current || !accepted || text.length < 2 || text.length > 600) return
    pending.current = true
    setBusy(true)
    const id = ++nextId.current
    setQuestion('')
    setExchanges((old) => [...old, { id, question: text }])
    try {
      const answer = await askCoviAssistant(shop.id, text)
      setExchanges((old) => old.map((e) => (e.id === id ? { ...e, answer } : e)))
    } catch (error) {
      const message = error instanceof Error ? error.message : "L'assistant est indisponible."
      setExchanges((old) => old.map((e) => (e.id === id ? { ...e, error: message } : e)))
    } finally {
      pending.current = false
      setBusy(false)
    }
  }

  const onSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    void send(question)
  }

  return (
    <div className="page-stack covi-assistant">
      <PageHead title="COVI Assistant IA" sub="Posez vos questions à votre copilote de gestion." />
      <Notice live={false}>
        <p>
          Conseils en lecture seule : l'IA ne peut ni vendre, ni changer le stock, ni valider un
          paiement. Ses réponses peuvent comporter des erreurs : vérifiez toujours vos chiffres dans
          le Bilan et les opérations enregistrées.
        </p>
      </Notice>
      <Sheet>
        <h2 className="section-title">Une question sur votre activité ?</h2>
        <p className="muted">
          {sector === 'retail'
            ? "L'assistant utilise les chiffres enregistrés de cette boutique, hors données de démonstration et ventes non synchronisées. « Ventes moins charges » n'est pas un bénéfice net."
            : 'Pour votre métier, cette première version donne des conseils généraux. Les chiffres financiers du restaurant ou du salon ne sont pas encore connectés.'}
        </p>
        <div className="covi-assistant__ideas" aria-label="Suggestions de questions">
          {ideas[sector].map((idea) => (
            <button
              type="button"
              className="covi-assistant__suggestion"
              key={idea}
              onClick={() => setQuestion(idea)}
              disabled={busy}
            >
              {idea}
            </button>
          ))}
        </div>
      </Sheet>
      {exchanges.length > 0 && (
        <section aria-label="Conversation avec COVI" className="covi-assistant__conversation">
          {exchanges.map(({ id, question: sent, answer, error }) => (
            <div className="covi-assistant__exchange" key={id}>
              <p className="covi-assistant__question">
                <strong>Vous :</strong> {sent}
              </p>
              {answer ? (
                <div className="covi-assistant__answer">
                  <strong>COVI :</strong>
                  <p>{answer}</p>
                </div>
              ) : error ? (
                <p className="covi-assistant__error" role="alert">
                  {error}
                </p>
              ) : (
                <p className="muted" role="status">
                  COVI prépare une réponse…
                </p>
              )}
            </div>
          ))}
        </section>
      )}
      <Sheet>
        <form onSubmit={onSubmit} className="covi-assistant__form">
          <label htmlFor="covi-assistant-question">Votre question</label>
          <textarea
            id="covi-assistant-question"
            value={question}
            onChange={(event) => setQuestion(event.target.value)}
            maxLength={600}
            rows={3}
            disabled={busy}
            placeholder="Ex. Pourquoi mes ventes ont-elles diminué ?"
          />
          <label className="covi-assistant__consent">
            <input
              type="checkbox"
              checked={accepted}
              onChange={(event) => setAccepted(event.target.checked)}
              disabled={busy}
            />
            <span>
              J'accepte l'envoi de ma question et des indicateurs utiles de mon établissement à
              Google Gemini pour générer une réponse. Évitez les données personnelles de clients.
              Aucun historique de conversation n'est enregistré par COVI dans cette version.
            </span>
          </label>
          <Button
            type="submit"
            variant="primary"
            busy={busy}
            busyLabel="COVI réfléchit…"
            disabled={!accepted || busy || question.trim().length < 2}
          >
            Envoyer ma question
          </Button>
        </form>
      </Sheet>
    </div>
  )
}
