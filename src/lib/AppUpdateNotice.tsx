import { useAppUpdate } from './pwa'

/**
 * Minimal "new version" prompt, rendered by main.tsx. The interface can style `.update-notice` or
 * replace this component with its own built on `useAppUpdate()`.
 */
export function AppUpdateNotice() {
  const { needRefresh, reload, dismiss } = useAppUpdate()
  if (!needRefresh) return null
  return (
    <div
      className="update-notice"
      role="status"
      style={{
        position: 'fixed',
        left: 16,
        right: 16,
        bottom: 'calc(16px + env(safe-area-inset-bottom, 0px))',
        zIndex: 1000,
        maxWidth: 420,
        margin: '0 auto',
        display: 'flex',
        alignItems: 'center',
        gap: 12,
        padding: '10px 14px',
        borderRadius: 12,
        background: '#FCFBF8',
        color: '#17408B',
        border: '1px solid #17408B',
        font: 'inherit',
      }}
    >
      <span style={{ flex: 1 }}>Nouvelle version disponible ·</span>
      <button type="button" onClick={() => void reload()}>
        Recharger
      </button>
      <button type="button" onClick={dismiss} aria-label="Plus tard">
        ×
      </button>
    </div>
  )
}
