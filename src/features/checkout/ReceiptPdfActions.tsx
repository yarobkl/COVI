import { useRef, useState } from 'react'
import { Button } from '../../components/ui'
import { downloadReceiptPdf, shareReceiptPdf } from '../../lib/receiptShare'
import type { PdfReceiptData } from '../../lib/receiptPdf'

/** Share native PDF after server confirmation; never on an unpaid order. */
export function ReceiptPdfActions({ receipt }: { receipt: PdfReceiptData }) {
  const [busy, setBusy] = useState(false)
  const [feedback, setFeedback] = useState('')
  const inProgress = useRef(false)

  async function share() {
    if (inProgress.current) return
    inProgress.current = true
    setBusy(true)
    setFeedback('')
    try {
      const result = await shareReceiptPdf(receipt)
      if (result === 'downloaded') {
        setFeedback(
          'Partage direct indisponible : le PDF a été téléchargé. Vous pouvez l’envoyer depuis vos fichiers.',
        )
      }
      if (result === 'cancelled') setFeedback('Partage annulé.')
    } catch (error) {
      setFeedback(error instanceof Error ? error.message : 'Impossible de préparer le PDF.')
    } finally {
      inProgress.current = false
      setBusy(false)
    }
  }

  function download() {
    if (inProgress.current) return
    setFeedback('')
    try {
      downloadReceiptPdf(receipt)
    } catch (error) {
      setFeedback(error instanceof Error ? error.message : 'Impossible de télécharger le PDF.')
    }
  }

  return (
    <div className="receipt-pdf-actions">
      <Button variant="secondary" block busy={busy} disabled={busy} onClick={() => void share()}>
        Partager la facture PDF
      </Button>
      <Button variant="ghost" block disabled={busy} onClick={download}>
        Télécharger le PDF
      </Button>
      {feedback && (
        <p className="field__hint" role="status">
          {feedback}
        </p>
      )}
    </div>
  )
}
