import { useEffect, useRef, useState, type FormEvent, type KeyboardEvent } from 'react'
import { Button, Notice, PageHead, Sheet } from '../../components/ui'
import { askCoviAssistant, type ChatTurn } from '../../lib/assistant'
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

/** Vrai chat multi-tour, local à la page. Pas de stockage durable ni de données entre boutiques. */
export function AssistantPage({ shop }: { shop: Shop }) {
  const [question, setQuestion] = useState('')
  const [accepted, setAccepted] = useState(false)
  const [busy, setBusy] = useState(false)
  const [exchanges, setExchanges] = useState<Exchange[]>([])
  const nextId = useRef(0)
  const pending = useRef(false)
  const endRef = useRef<HTMLDivElement | null>(null)
  const sector =
    shop.business_kind === 'restaurant' || shop.business_kind === 'salon'
      ? shop.business_kind
      : 'retail'

  useEffect(() => {
    if (typeof endRef.current?.scrollIntoView === 'function') {
      endRef.current.scrollIntoView({ behavior: 'smooth', block: 'end' })
    }
  }, [exchanges])

  const send = async (value: string) => {
    const text = value.trim()
    if (pending.current || !accepted || text.length < 2 || text.length > 600) return

    // Les réponses en échec ne sont jamais injectées dans le contexte de Gemini.
    const history: ChatTurn[] = exchanges
      .filter((exchange) => typeof exchange.answer === 'string' && exchange.answer.length > 0)
      .slice(-6)
      .flatMap((exchange) => [
        { role: 'user' as const, text: exchange.question },
        { role: 'model' as const, text: (exchange.answer ?? '').slice(0, 2000) },
      ])

    pending.current = true
    setBusy(true)
    const id = ++nextId.current
    setQuestion('')
    setExchanges((old) => [...old, { id, question: text }])
    try {
      const answer = await askCoviAssistant(shop.id, text, history)
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
  const onComposerKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === 'Enter' && !event.shiftKey && !event.nativeEvent.isComposing) {
      event.preventDefault()
      void send(question)
    }
  }

  return (
    <div className="page-stack covi-assistant">
      <PageHead title="COVI Assistant IA" sub="Votre copilote de gestion, en conversation." />
      <Notice live={false}>
        <p>
          Vous pouvez discuter naturellement avec COVI et lui poser des questions de suivi. Les
          indicateurs proviennent de vos données enregistrées, mais les conseils de l'IA peuvent
          comporter des erreurs. Aucune vente, aucun stock ou paiement ne peut être modifié par cet
          assistant.
        </p>
      </Notice>
      <section aria-label="Chat COVI" className="covi-assistant__chat">
        <div className="covi-assistant__chat-head">
          <div>
            <strong>COVI Assistant</strong>
            <p className="muted">Conseiller en gestion · {shop.name}</p>
          </div>
          {exchanges.length > 0 && (
            <Button
              variant="ghost"
              onClick={() => {
                setExchanges([])
                setQuestion('')
              }}
              disabled={busy}
            >
              Nouvelle conversation
            </Button>
          )}
        </div>
        <div
          className="covi-assistant__conversation"
          aria-label="Messages du chat"
          aria-live="polite"
        >
          {exchanges.length === 0 && (
            <div className="covi-assistant__welcome">
              <h2>Bonjour ! Comment puis-je vous aider ?</h2>
              <p className="muted">
                {sector === 'retail'
                  ? "Parlons de votre chiffre d'affaires, de votre stock ou de vos charges. « Ventes moins charges » n'est pas un bénéfice net."
                  : "Parlons de votre activité. Les chiffres financiers de ce métier ne sont pas encore connectés à l'IA."}
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
            </div>
          )}
          {exchanges.map(({ id, question: sent, answer, error }) => (
            <div className="covi-assistant__exchange" key={id}>
              <div className="covi-assistant__question">
                <strong>Vous</strong>
                <p>{sent}</p>
              </div>
              {answer ? (
                <div className="covi-assistant__answer">
                  <strong>COVI</strong>
                  <p>{answer}</p>
                </div>
              ) : error ? (
                <div className="covi-assistant__answer covi-assistant__error" role="alert">
                  <strong>COVI</strong>
                  <p>{error}</p>
                </div>
              ) : (
                <div className="covi-assistant__answer" role="status">
                  COVI réfléchit…
                </div>
              )}
            </div>
          ))}
          <div ref={endRef} />
        </div>
        <Sheet>
          <form onSubmit={onSubmit} className="covi-assistant__form">
            <label htmlFor="covi-assistant-question">Votre message</label>
            <textarea
              id="covi-assistant-question"
              value={question}
              onChange={(event) => setQuestion(event.target.value)}
              onKeyDown={onComposerKeyDown}
              maxLength={600}
              rows={2}
              disabled={busy}
              placeholder="Posez une question, puis continuez la discussion…"
            />
            <label className="covi-assistant__consent">
              <input
                type="checkbox"
                checked={accepted}
                onChange={(event) => setAccepted(event.target.checked)}
                disabled={busy}
              />
              <span>
                J'accepte l'envoi de mes messages et des indicateurs utiles à Google Gemini. Évitez
                les données personnelles de clients. Cette conversation n'est conservée que sur
                cette page et sera perdue si vous la quittez.
              </span>
            </label>
            <div className="covi-assistant__actions">
              <p className="muted">60 messages par heure et par boutique · Entrée pour envoyer</p>
              <Button
                type="submit"
                variant="primary"
                busy={busy}
                busyLabel="COVI réfléchit…"
                disabled={!accepted || busy || question.trim().length < 2}
              >
                Envoyer
              </Button>
            </div>
          </form>
        </Sheet>
      </section>
    </div>
  )
}
