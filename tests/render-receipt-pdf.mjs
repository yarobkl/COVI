/**
 * Generate synthetic COVI receipts for an ephemeral PDF renderer smoke test.
 * Usage: node --experimental-strip-types tests/render-receipt-pdf.mjs OUT_DIR
 * No network, customer data, database, or production API is accessed.
 */
import { mkdir, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { makeConfirmedReceiptPdf } from '../src/lib/receiptPdf.ts'

const dir = process.argv[2]
if (!dir) throw new Error('Output directory required')
await mkdir(dir, { recursive: true })

const example = {
  shopName: 'YARO BOUTIQUE',
  receiptNumber: 'COVI-489A49A206524EE1BE8461E9173B9E38',
  confirmedAt: '2026-10-17T08:15:00.000Z',
  method: 'mobile_money',
  cashierFirstName: 'Rodrin',
  lines: [{ label: 'Robe', quantity: 1, lineTotalXaf: 3500 }],
  amountXaf: 3500,
}

for (const [filename, data] of [
  ['covi-recu-exemple.pdf', example],
  [
    'covi-recu-multipage.pdf',
    {
      ...example,
      receiptNumber: 'CV-2026-MULTIPAGE',
      lines: Array.from({ length: 75 }, (_, i) => ({
        label: 'Chemise collection N°' + (i + 1),
        quantity: 1,
        lineTotalXaf: 1000,
      })),
      amountXaf: 75000,
    },
  ],
]) {
  const pdf = makeConfirmedReceiptPdf(data)
  const bytes = new Uint8Array(await pdf.arrayBuffer())
  if (
    pdf.type !== 'application/pdf' ||
    bytes.length < 500 ||
    new TextDecoder().decode(bytes.subarray(0, 8)) !== '%PDF-1.4'
  ) {
    throw new Error('Generated PDF is invalid')
  }
  await writeFile(join(dir, filename), bytes)
  console.log(filename, bytes.length + ' bytes')
}
