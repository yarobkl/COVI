// Domain types shared by the data layer and the pages.

/** The signed-in owner's shop, as loaded by AuthGate and edited in the settings. */
export type Shop = {
  id: string
  name: string
  city: string | null
  country: string | null
  currency: string
}
