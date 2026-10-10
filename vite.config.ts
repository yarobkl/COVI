import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

// Progressive Web App (web only: src/lib/pwaRegister.ts does not register the service worker in
// Tauri). The service worker precaches the application so that it opens without network; the data
// itself (queued sales, stock, shop) lives in IndexedDB (src/lib/offline.ts), never in its caches.
export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: 'prompt',
      // Registered by src/lib/pwaRegister.ts (needs the Tauri check), not by an injected script.
      injectRegister: false,
      // Icons are precached by globPatterns below (no duplicate entries).
      includeManifestIcons: false,
      manifest: {
        name: 'COVI',
        short_name: 'COVI',
        description: 'Le système d’exploitation de votre commerce.',
        lang: 'fr',
        dir: 'ltr',
        start_url: '/',
        scope: '/',
        display: 'standalone',
        orientation: 'any',
        theme_color: '#17408B',
        background_color: '#FCFBF8',
        icons: [
          { src: 'icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
          { src: 'icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
          {
            src: 'icon-maskable-512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable',
          },
        ],
      },
      workbox: {
        // Application shell only. No .woff (every browser that runs COVI reads .woff2).
        globPatterns: ['**/*.{js,css,html,woff2,png,svg,ico}'],
        globIgnores: ['**/*.woff', 'sw-sync.js'],
        navigateFallback: 'index.html',
        cleanupOutdatedCaches: true,
        // Background Sync: wakes the open pages so that they send the queued sales.
        importScripts: ['sw-sync.js'],
        runtimeCaching: [
          {
            // Supabase API (REST, RPC, Auth, Functions): always the network, never cached. Answers
            // are authenticated and personal; offline data goes through src/lib/offline.ts.
            urlPattern: ({ url }) =>
              url.hostname.endsWith('.supabase.co') &&
              /^\/(rest|auth|functions|realtime)\/v1\//.test(url.pathname),
            handler: 'NetworkOnly',
          },
          {
            // Signed product photos (private bucket): stale-while-revalidate, 50 photos, 7 days.
            urlPattern: ({ url }) =>
              url.hostname.endsWith('.supabase.co') &&
              url.pathname.startsWith('/storage/v1/object/sign/covi-product-images/'),
            handler: 'StaleWhileRevalidate',
            options: {
              cacheName: 'covi-product-images',
              expiration: {
                maxEntries: 50,
                maxAgeSeconds: 7 * 24 * 60 * 60,
                purgeOnQuotaError: true,
              },
              // Only real (CORS) 200 answers: an opaque answer weighs several MB of quota.
              cacheableResponse: { statuses: [200] },
              plugins: [
                {
                  // The signature (?token=) changes at every listing: key the cache on the path.
                  cacheKeyWillBeUsed: async ({ request }) => {
                    const url = new URL(request.url)
                    url.search = ''
                    return url.href
                  },
                  // <img> requests are no-cors (opaque answers): ask for a CORS answer instead,
                  // which Supabase Storage allows, so that it can be cached at its real size.
                  requestWillFetch: async ({ request }) =>
                    new Request(request.url, { mode: 'cors', credentials: 'omit' }),
                  // No cached copy and the CORS request failed: let the browser load it as usual.
                  handlerDidError: async ({ request }) => fetch(request),
                },
              ],
            },
          },
        ],
      },
    }),
  ],
})
