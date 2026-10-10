import type { CSSProperties } from 'react'

/**
 * Loading: notebook lines writing themselves, with a short human caption (« On fait les
 * comptes… »). Each line gives its width and whether it ends with an amount.
 */
export function Skeleton({
  caption,
  lines = [{ width: 52, amount: true }, { width: 44 }, { width: 68 }, { width: 36, amount: true }],
}: {
  caption: string
  lines?: { width: number; amount?: boolean }[]
}) {
  return (
    <div className="skeleton" role="status" aria-live="polite">
      <p className="skeleton__caption">{caption}</p>
      {lines.map((line, i) => (
        <div
          key={i}
          className={line.amount ? 'skeleton__line skeleton__line--amount' : 'skeleton__line'}
          style={{ '--w': `${line.width}%`, '--i': i } as CSSProperties}
          aria-hidden="true"
        />
      ))}
    </div>
  )
}
