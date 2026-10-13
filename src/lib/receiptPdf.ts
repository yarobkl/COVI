import type { ConfirmedCheckoutReceipt } from '../features/checkout/ConfirmedCheckoutTicket'

/**
 * Compact, dependency-free PDF receipt. The source is the server-confirmed
 * sale and receipt number; never call this from an unpaid order screen.
 *
 * PDF uses built-in Helvetica/WinAnsi, not remote fonts or a third-party API.
 * This is a receipt, not a tax invoice: fiscal fields must be configured
 * before the product may issue legally compliant invoices in each country.
 */

function encodedPdfText(value: string): string {
  const symbols: Record<string, number> = {
    '€': 128,
    Œ: 140,
    œ: 156,
    '–': 150,
    '—': 151,
    '’': 146,
    '“': 147,
    '”': 148,
    '•': 149,
  }
  let output = ''
  for (const character of value.normalize('NFC').replace(/\s+/g, ' ')) {
    const point = symbols[character] ?? character.codePointAt(0) ?? 63
    if (point === 40 || point === 41 || point === 92) {
      output += '\\' + String.fromCharCode(point)
    } else if (point >= 32 && point < 127) {
      output += String.fromCharCode(point)
    } else if ((point >= 160 && point <= 255) || (point >= 128 && point <= 159)) {
      output += '\\' + point.toString(8).padStart(3, '0')
    } else {
      output += '?'
    }
  }
  return output
}

function fcfa(amount: number): string {
  return new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 0 }).format(amount) + ' FCFA'
}

function receiptLines(receipt: ConfirmedCheckoutReceipt): string[] {
  const names: Record<ConfirmedCheckoutReceipt['method'], string> = {
    cash: 'Espèces',
    mobile_money: 'Mobile Money',
    other: 'Autre',
  }
  const lines = [
    'COVI - REÇU DE VENTE',
    receipt.shopName.slice(0, 75),
    'Numéro : ' + receipt.receiptNumber.slice(0, 90),
    'Date : ' + new Date(receipt.confirmedAt).toLocaleString('fr-FR'),
    '',
    'ARTICLES',
    '----------------------------------------',
  ]
  for (const line of receipt.lines) {
    lines.push(line.quantity + ' x ' + line.label.slice(0, 46) + '    ' + fcfa(line.lineTotalXaf))
  }
  lines.push(
    '----------------------------------------',
    'TOTAL : ' + fcfa(receipt.amountXaf),
    'Paiement : ' + names[receipt.method],
    'Encaissement confirmé par : ' + receipt.cashierFirstName.slice(0, 60),
    '',
    'Reçu émis après confirmation du paiement.',
    'Conservez ce document pour vos archives.',
    'COVI - Commerce & Vie',
  )
  return lines
}

function pdfObjects(receipt: ConfirmedCheckoutReceipt): Uint8Array {
  if (
    !receipt.receiptNumber.trim() ||
    !receipt.shopName.trim() ||
    !Number.isFinite(Date.parse(receipt.confirmedAt)) ||
    !Number.isSafeInteger(receipt.amountXaf) ||
    receipt.amountXaf < 0 ||
    receipt.lines.length < 1
  ) {
    throw new Error('Reçu confirmé incomplet : export PDF impossible.')
  }
  const sum = receipt.lines.reduce((amount, line) => amount + line.lineTotalXaf, 0)
  if (sum !== receipt.amountXaf || !Number.isSafeInteger(sum)) {
    throw new Error('Reçu incohérent : export PDF impossible.')
  }

  const textLines = receiptLines(receipt)
  const perPage = 37
  const pages = Math.ceil(textLines.length / perPage)
  const objects: string[] = [
    '',
    '',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
  ]
  const pageIds: number[] = []
  for (let page = 0; page < pages; page += 1) {
    const chunk = textLines.slice(page * perPage, (page + 1) * perPage)
    const content = [
      '0.5 w 40 797 m 555 797 l S',
      ...chunk.map(
        (line, index) =>
          'BT /F1 ' +
          (index === 0 && page === 0 ? '16' : '10') +
          ' Tf 48 ' +
          (766 - index * 18) +
          ' Td (' +
          encodedPdfText(line) +
          ') Tj ET',
      ),
      'BT /F1 9 Tf 465 38 Td (' + encodedPdfText('Page ' + (page + 1) + '/' + pages) + ') Tj ET',
    ].join('\n')
    const pageId = objects.length + 1
    const streamId = pageId + 1
    pageIds.push(pageId)
    objects.push(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents ' +
        streamId +
        ' 0 R >>',
    )
    objects.push('<< /Length ' + content.length + ' >>\nstream\n' + content + '\nendstream')
  }
  objects[0] = '<< /Type /Catalog /Pages 2 0 R >>'
  objects[1] =
    '<< /Type /Pages /Count ' +
    pages +
    ' /Kids [' +
    pageIds.map((id) => id + ' 0 R').join(' ') +
    '] >>'

  let output = '%PDF-1.4\n'
  const offsets = [0]
  for (const [index, object] of objects.entries()) {
    offsets.push(output.length)
    output += index + 1 + ' 0 obj\n' + object + '\nendobj\n'
  }
  const xref = output.length
  output += 'xref\n0 ' + (objects.length + 1) + '\n0000000000 65535 f \n'
  for (const offset of offsets.slice(1)) {
    output += String(offset).padStart(10, '0') + ' 00000 n \n'
  }
  output +=
    'trailer\n<< /Size ' +
    (objects.length + 1) +
    ' /Root 1 0 R >>\nstartxref\n' +
    xref +
    '\n%%EOF\n'
  return Uint8Array.from(output, (char) => char.charCodeAt(0))
}

export function makeConfirmedReceiptPdf(receipt: ConfirmedCheckoutReceipt): Blob {
  const bytes = pdfObjects(receipt)
  const buffer = new ArrayBuffer(bytes.length)
  new Uint8Array(buffer).set(bytes)
  return new Blob([buffer], { type: 'application/pdf' })
}

export function downloadConfirmedReceiptPdf(receipt: ConfirmedCheckoutReceipt): void {
  const blob = makeConfirmedReceiptPdf(receipt)
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = 'COVI-recu-' + receipt.receiptNumber.replace(/[^a-zA-Z0-9_-]+/g, '-') + '.pdf'
  document.body.appendChild(link)
  link.click()
  link.remove()
  // Give Safari and mobile browsers time to start the download.
  window.setTimeout(() => URL.revokeObjectURL(url), 60_000)
}
