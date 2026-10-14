/** The database stores the same reference as a generated unique column on every sale. */
export function saleOperationReference(saleId: string | null | undefined): string | null {
  if (!saleId || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(saleId)) {
    return null
  }
  return `COVI-${saleId.replace(/-/g, '').toUpperCase()}`
}
