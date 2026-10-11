/** Progressive enhancement: browser haptics where supported, tactile feedback everywhere. */
type HapticPattern = 'tap' | 'success' | 'error'

export function haptic(pattern: HapticPattern = 'tap'): boolean {
  if (typeof navigator === 'undefined' || typeof navigator.vibrate !== 'function') return false
  if (typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) return false
  const durations: Record<HapticPattern, number | number[]> = {
    tap: 12,
    success: [18, 45, 24],
    error: [35, 60, 35],
  }
  try {
    return navigator.vibrate(durations[pattern])
  } catch {
    return false
  }
}

/** One delegated listener also covers buttons created later by dialogs and forms. */
export function installButtonFeedback(): () => void {
  const onClick = (event: MouseEvent) => {
    const target = event.target
    if (!(target instanceof Element)) return
    const button = target.closest('button, [role="button"], a.btn')
    if (!(button instanceof HTMLElement)) return
    if (button.matches(':disabled, [aria-disabled="true"]')) return
    haptic('tap')
    button.classList.remove('covi-tap')
    // Force animation restart on successive taps, without keeping timers alive.
    void button.offsetWidth
    button.classList.add('covi-tap')
  }
  const onAnimationEnd = (event: AnimationEvent) => {
    if (event.animationName === 'covi-button-tap' && event.target instanceof HTMLElement) {
      event.target.classList.remove('covi-tap')
    }
  }
  document.addEventListener('click', onClick, { capture: true })
  document.addEventListener('animationend', onAnimationEnd)
  return () => {
    document.removeEventListener('click', onClick, true)
    document.removeEventListener('animationend', onAnimationEnd)
  }
}
