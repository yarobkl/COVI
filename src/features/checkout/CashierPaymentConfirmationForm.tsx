import { useRef, useState, type FormEvent } from 'react'
import { Amount, Button, Field, Input, Segmented } from '../../components/ui'
import {
  prepareManualCashierAttestation,
  type ManualCashierAttestation,
  type ManualPaymentMethod,
} from '../../lib/orderLifecycle'

const paymentOptions = [
  { value: 'cash', label: 'Espèces' },
  { value: 'mobile_money', label: 'Mobile Money' },
  { value: 'other', label: 'Autre' },
] as const

/**
 * Reusable "Le Cahier" form for a future approved checkout order.
 * Not yet mounted in the live app: onConfirm must call an authorized atomic RPC.
 * No payment API, receipt issuance or stock change happens in this component.
 */
export function CashierPaymentConfirmationForm({
  amountXaf,
  onConfirm,
}: {
  amountXaf: number
  onConfirm: (attestation: ManualCashierAttestation) => Promise<void>
}) {
  const [cashierFirstName, setCashierFirstName] = useState('')
  const [method, setMethod] = useState<ManualPaymentMethod | null>(null)
  const [externalReference, setExternalReference] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  // Prevent duplicate submit in the same event turn, before React has re-rendered.
  const submitting = useRef(false)

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (submitting.current) return
    submitting.current = true
    setBusy(true)
    setError('')
    try {
      if (!method) throw new Error('Choisissez le moyen de paiement reçu.')
      const attestation = prepareManualCashierAttestation({
        cashierFirstName,
        method,
        externalReference,
      })
      await onConfirm(attestation)
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Confirmation impossible. Réessayez.')
    } finally {
      submitting.current = false
      setBusy(false)
    }
  }

  return (
    <form className="card" onSubmit={(event) => { void submit(event) }}>
      <h2>Encaissement</h2>
      <p>Montant à vérifier : <Amount value={amountXaf} unit /></p>
      <p>Vérifiez la réception effective de l'argent avant de confirmer.</p>

      <Segmented
        legend="Paiement reçu par"
        options={paymentOptions}
        value={method}
        onChange={setMethod}
        sale
      />

      <Field
        label="Prénom de la personne qui encaisse"
        hint="Il sera inscrit sur le reçu. Le compte connecté reste identifié dans l'historique."
      >
        {(props) => (
          <Input
            {...props}
            type="text"
            name="cashierFirstName"
            autoComplete="given-name"
            maxLength={60}
            required
            value={cashierFirstName}
            onChange={(event) => setCashierFirstName(event.target.value)}
            placeholder="Ex. : Marie Lou"
          />
        )}
      </Field>

      <Field label="Référence Mobile Money / reçu" optional>
        {(props) => (
          <Input
            {...props}
            type="text"
            name="externalReference"
            maxLength={120}
            autoComplete="off"
            value={externalReference}
            onChange={(event) => setExternalReference(event.target.value)}
            placeholder="SMS ou référence, si disponible"
          />
        )}
      </Field>

      {error && <p className="field__error" role="alert">{error}</p>}
      {(!method || !cashierFirstName.trim()) && (
        <p className="field__hint">Choisissez le paiement et saisissez votre prénom pour valider.</p>
      )}
      <Button
        type="submit"
        variant="sale"
        size="lg"
        block
        busy={busy}
        busyLabel="Vérification de la confirmation…"
        disabled={busy || !method || !cashierFirstName.trim()}
      >
        Confirmer le paiement reçu
      </Button>
    </form>
  )
}
