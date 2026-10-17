import { Button, Notice } from './ui'

/** Loading failure with a retry button (shown instead of an endless "Chargement…"). */
export function LoadError({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <Notice
      tone="danger"
      live
      actions={
        <Button variant="secondary" onClick={onRetry}>
          Réessayer
        </Button>
      }
    >
      <p>{message}</p>
    </Notice>
  )
}
