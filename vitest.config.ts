import { defineConfig } from 'vitest/config'

// Separate from the Vite build (which runs with Vite defaults): only used by `npm test`.
export default defineConfig({
  test: {
    environment: 'jsdom',
    include: ['src/**/*.test.{ts,tsx}'],
  },
})
