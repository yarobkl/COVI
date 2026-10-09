/** Loading failure with a retry button (shown instead of an endless "Chargement…"). */
export function LoadError({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <section className="card" role="alert">
      <p className="authmessage">{message}</p>
      <button className="outline" type="button" onClick={onRetry}>
        Réessayer
      </button>
    </section>
  )
}
