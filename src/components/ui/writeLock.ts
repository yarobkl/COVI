import { createContext, useContext } from 'react'

/**
 * Why writing is impossible right now (subscription suspended: the shop is read only), or null.
 * Buttons and links marked `write` read it: they stay visible but are disabled, and point to the
 * explanation (`reasonId`, the banner) for screen readers.
 */
export type WriteLock = { reasonId: string; reason: string }

export const WriteLockContext = createContext<WriteLock | null>(null)

export const useWriteLock = () => useContext(WriteLockContext)
