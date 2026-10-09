// Arrival lifecycle: draft → ordered → in_transit → received.

/** Status reached by the "advance" button, if any. */
export const nextStatus: Record<string, string> = {
  draft: 'ordered',
  ordered: 'in_transit',
  in_transit: 'received',
}

/** Label of the button that moves an arrival to its next status. */
export const nextStatusLabel: Record<string, string> = {
  draft: 'Marquer commandé',
  ordered: 'Marquer en transit',
  in_transit: 'Confirmer la réception',
}

/** Badge text for an arrival status. */
export function statusLabel(status: string) {
  return status === 'received'
    ? 'REÇU'
    : status === 'in_transit'
      ? 'EN TRANSIT'
      : status === 'ordered'
        ? 'COMMANDÉ'
        : 'BROUILLON'
}

/** Short random arrival code, e.g. `CMD-1A2B3C`. */
export const arrivalCode = (prefix: string) =>
  prefix + '-' + crypto.randomUUID().slice(0, 6).toUpperCase()
