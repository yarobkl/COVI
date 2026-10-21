import { supabase } from './supabase'

/** Pas de clé Gemini côté navigateur : uniquement la fonction Edge authentifiée. */
export async function askCoviAssistant(shopId: string, message: string): Promise<string> {
  const { data, error } = await supabase.functions.invoke('covi-assistant', {
    body: { shopId, message },
  })
  if (error) {
    const response = 'context' in error ? error.context : null
    if (response instanceof Response) {
      try {
        const payload: unknown = await response.json()
        if (payload && typeof payload === 'object' && 'error' in payload) {
          const detail = (payload as { error?: unknown }).error
          if (typeof detail === 'string') throw new Error(detail)
        }
      } catch (cause) {
        if (cause instanceof Error && cause.message !== 'Unexpected end of JSON input') {
          // Ne laisse pas une erreur de parsing cacher le vrai état, mais conserve le message serveur.
          if (cause instanceof SyntaxError) throw new Error("L'assistant est indisponible.")
          throw cause
        }
      }
    }
    throw new Error("L'assistant est indisponible. Vérifiez votre connexion et réessayez.")
  }
  if (!data || typeof data.answer !== 'string' || !data.answer.trim()) {
    throw new Error("L'assistant n'a pas pu répondre.")
  }
  return data.answer
}
