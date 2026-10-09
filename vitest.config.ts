import { defineConfig } from 'vitest/config'

// A time zone far from UTC, so that tests catch local/UTC date mix-ups (inherited by the workers).
process.env.TZ = 'Asia/Tokyo'

// Separate from the Vite build (which runs with Vite defaults): only used by `npm test`.
export default defineConfig({
  test: {
    environment: 'jsdom',
    include: ['src/**/*.test.{ts,tsx}'],
  },
})
