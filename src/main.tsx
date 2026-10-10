import { createRoot } from 'react-dom/client'
import './styles.css'
import { Root } from './app/Root'
import { AppUpdateNotice } from './lib/AppUpdateNotice'
import { isTauriApp } from './lib/desktopAuth'
import { initOfflineStore } from './lib/offline'

// The offline store (queued sales, stock, last shop) is loaded before the first render, so that the
// till can open on it without network. initOfflineStore() never rejects.
void initOfflineStore().finally(() => {
  createRoot(document.getElementById('root')!).render(
    <>
      <Root />
      <AppUpdateNotice />
    </>,
  )
})

// Service worker: web only (Tauri serves its files locally), never in development.
if (import.meta.env.PROD && !isTauriApp())
  void import('./lib/pwaRegister').then(({ registerServiceWorker }) => registerServiceWorker())
