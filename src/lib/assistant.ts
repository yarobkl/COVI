import { supabase } from './supabase'

export type ChatTurn = { role: 'user' | 'model'; text: string }

/** Pas de clé Gemini côté navigateur : uniquement la fonction Edge authentifiée.
 * Le contexte de 6 échanges précédents est éphémère, sans PIN.
 */
export async function askCoviAssistant(
  shopId: string,
  message: string,
  history: ChatTurn[] = [],
): Promise<string> {
  const { data, error } = await supabase.functions.invoke('covi-assistant', {
    body: { shopId, message, history },
  })
  if (error) {
    const response = 'context' in error ? error.context : null
    if (response instanceof Response) {
      let payload: unknown
      try {
        payload = await response.json()
      } catch {
        // La réponse serveur n'est pas du JSON exploitable.
      }
      if (payload && typeof payload === 'object' && 'error' in payload) {
        const detail = (payload as { error?: unknown }).error
        if (typeof detail === 'string') throw new Error(detail)
      }
    }
    throw new Error("L'assistant est indisponible. Vérifiez votre connexion et réessayez.")
  }
  if (!data || typeof data.answer !== 'string' || !data.answer.trim()) {
    throw new Error("L'assistant n'a pas pu répondre.")
  }
  return data.answer
}
