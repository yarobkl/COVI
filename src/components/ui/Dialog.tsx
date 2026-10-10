import { useEffect, useRef, type ReactNode } from 'react'
import { cx } from './cx'

/**
 * Native modal `<dialog>`: focus trapped, Escape (and the Android back gesture) closes it, plain
 * backdrop. `sheet`: rises from the bottom on phones, centred from 640 px. Replaces
 * `window.confirm`.
 */
export function Dialog({
  open,
  onClose,
  labelledBy,
  sheet = false,
  className,
  children,
}: {
  open: boolean
  onClose: () => void
  /** Id of the heading that names the dialog. */
  labelledBy: string
  sheet?: boolean
  className?: string
  children: ReactNode
}) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => {
    const dialog = ref.current
    if (!dialog) return
    if (open && !dialog.open) {
      // jsdom (tests) has no showModal: fall back to the plain attribute.
      if (typeof dialog.showModal === 'function') dialog.showModal()
      else dialog.setAttribute('open', '')
    } else if (!open && dialog.open) {
      if (typeof dialog.close === 'function') dialog.close()
      else dialog.removeAttribute('open')
    }
  }, [open])
  return (
    <dialog
      ref={ref}
      className={cx('dialog', sheet && 'dialog--sheet', className)}
      aria-labelledby={labelledBy}
      onCancel={(e) => {
        e.preventDefault()
        onClose()
      }}
      onClose={() => {
        if (open) onClose()
      }}
      onClick={(e) => {
        // A tap on the backdrop (outside the dialog box) closes it.
        if (e.target === e.currentTarget) {
          const box = e.currentTarget.getBoundingClientRect()
          const inside =
            e.clientX >= box.left &&
            e.clientX <= box.right &&
            e.clientY >= box.top &&
            e.clientY <= box.bottom
          if (!inside) onClose()
        }
      }}
    >
      {open && children}
    </dialog>
  )
}
