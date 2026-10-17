/** A server-confirmed checkout or a synced, recorded legacy sale. */
export type PdfReceiptData = {
  shopName: string
  receiptNumber: string
  confirmedAt: string
  cashierFirstName?: string | null
  method: string
  amountXaf: number
  lines: ReadonlyArray<{ label: string; quantity: number; lineTotalXaf: number }>
}

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

function receiptLines(receipt: PdfReceiptData): string[] {
  const names: Record<string, string> = {
    cash: 'Espèces',
    mobile_money: 'Mobile Money',
    card: 'Carte',
    bank_transfer: 'Virement',
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
    'Paiement : ' + (names[receipt.method] ?? receipt.method.slice(0, 60)),
    ...(receipt.cashierFirstName?.trim() ? [
      'Encaissement confirmé par : ' + receipt.cashierFirstName.trim().slice(0, 60),
    ] : []),
    '',
    'Reçu émis après confirmation du paiement.',
    'Conservez ce document pour vos archives.',
    'COVI - Commerce & Vie',
  )
  return lines
}

function pdfObjects(receipt: PdfReceiptData): Uint8Array {
  if (
    !receipt.receiptNumber.trim() ||
    !receipt.shopName.trim() ||
    !Number.isFinite(Date.parse(receipt.confirmedAt)) ||
    !Number.isSafeInteger(receipt.amountXaf) ||
    receipt.amountXaf < 0 ||
    receipt.lines.length < 1 ||
    receipt.lines.length > 120 ||
    receipt.lines.some((line) =>
      !line.label.trim() ||
      !Number.isSafeInteger(line.quantity) || line.quantity <= 0 ||
      !Number.isSafeInteger(line.lineTotalXaf) || line.lineTotalXaf < 0
    )
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
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>',
  ]
  const pageIds: number[] = []
  for (let page = 0; page < pages; page += 1) {
    const chunk = textLines.slice(page * perPage, (page + 1) * perPage)
    // Same paper/ink vocabulary as the UI: ruled page, red margin,
    // white ticket, navy heading and yellow total highlight.
    const ruled = Array.from({ length: 38 }, (_, i) => {
      const y = 22 * (i + 1)
      return '0.88 0.92 0.97 RG 0.35 w 0 ' + y + ' m 595 ' + y + ' l S'
    })
    const content = [
      '0.985 0.981 0.963 rg 0 0 595 842 re f',
      ...ruled,
      '0.77 0.35 0.31 RG 1.2 w 34 0 m 34 842 l S',
      '1 1 1 rg 42 81 511 718 re f',
      '0.15 0.31 0.55 RG 2 w 46 795 m 550 795 l S',
      ...chunk.map((line, index) => {
        const y = 766 - index * 18
        const isTotal = line.startsWith('TOTAL :')
        const accent = isTotal
          ? '0.99 0.87 0.40 rg 47 ' + (y - 5) + ' 495 18 re f\n'
          : ''
        const color = (index === 0 || isTotal)
          ? '0.14 0.29 0.53 rg '
          : '0.14 0.17 0.23 rg '
        const font = index === 0 || isTotal ? 'F2' : 'F1'
        const size = index === 0 && page === 0 ? 16 : isTotal ? 12 : 10
        return accent + color + 'BT /' + font + ' ' + size +
          ' Tf 48 ' + y + ' Td (' + encodedPdfText(line) + ') Tj ET'
      }),
      ...(page === pages - 1 && chunk.length < 32
        ? [
            '0.68 0.20 0.16 RG 1.8 w 415 106 122 47 re S',
            '0.68 0.20 0.16 rg BT /F2 20 Tf 433 122 Td (' +
              encodedPdfText('PAYÉ') + ') Tj ET',
          ]
        : []),
      '0.14 0.29 0.53 rg BT /F3 9 Tf 465 38 Td (' +
        encodedPdfText('Page ' + (page + 1) + '/' + pages) + ') Tj ET',
    ].join('\n')
    const pageId = objects.length + 1
    const streamId = pageId + 1
    pageIds.push(pageId)
    objects.push(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R /F2 4 0 R /F3 5 0 R >> >> /Contents ' +
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

export function makeConfirmedReceiptPdf(receipt: PdfReceiptData): Blob {
  const bytes = pdfObjects(receipt)
  const buffer = new ArrayBuffer(bytes.length)
  new Uint8Array(buffer).set(bytes)
  return new Blob([buffer], { type: 'application/pdf' })
}

export function downloadConfirmedReceiptPdf(receipt: PdfReceiptData): void {
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
