import { supabase } from './supabase'
import {
  prepareManualCashierAttestation,
  type ManualCashierAttestation,
  type ManualPaymentMethod,
} from './orderLifecycle'

type ManualCheckoutRpcArgs = {
  p_shop_id: string
  p_order_id: string
  p_operation_id: string
  p_cashier_first_name: string
  p_method: ManualPaymentMethod
  p_external_reference: string | null
  p_pin: string | null
}

export type RecordedCheckoutReceipt = {
  saleId: string
  receiptNumber: string
  confirmedAt: string
  cashierFirstName: string
  method: ManualPaymentMethod
  amountXaf: number
  lines: Array<{ label: string; quantity: number; lineTotalXaf: number }>
}

type RpcResult = {
  data: unknown
  error: { message: string } | null
}

// Deliberately typed as a future RPC without editing the generated types for
// today's production schema. Never invoke until the migration was tested.
type FutureCheckoutRpc = {
  rpc: (
    name: 'confirm_manual_checkout_payment',
    args: ManualCheckoutRpcArgs,
  ) => PromiseLike<RpcResult>
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

export function parseRecordedCheckoutReceipt(data: unknown): RecordedCheckoutReceipt {
  if (
    !isRecord(data) ||
    typeof data.saleId !== 'string' ||
    !data.saleId ||
    typeof data.receiptNumber !== 'string' ||
    !data.receiptNumber ||
    typeof data.confirmedAt !== 'string' ||
    !Number.isFinite(Date.parse(data.confirmedAt)) ||
    typeof data.cashierFirstName !== 'string' ||
    !data.cashierFirstName ||
    !['cash', 'mobile_money', 'other'].includes(String(data.method)) ||
    !Number.isSafeInteger(data.amountXaf) ||
    (data.amountXaf as number) < 0 ||
    !Array.isArray(data.lines) ||
    data.lines.length < 1
  ) {
    throw new Error('Réponse de confirmation du serveur invalide.')
  }

  const lines: RecordedCheckoutReceipt['lines'] = []
  let sum = 0
  for (const line of data.lines) {
    if (
      !isRecord(line) ||
      typeof line.label !== 'string' ||
      !line.label ||
      !Number.isSafeInteger(line.quantity) ||
      (line.quantity as number) < 1 ||
      !Number.isSafeInteger(line.lineTotalXaf) ||
      (line.lineTotalXaf as number) < 0
    ) {
      throw new Error('Lignes du reçu retournées par le serveur invalides.')
    }
    const quantity = line.quantity as number
    const lineTotalXaf = line.lineTotalXaf as number
    sum += lineTotalXaf
    if (!Number.isSafeInteger(sum)) throw new Error('Total du reçu invalide.')
    lines.push({ label: line.label, quantity, lineTotalXaf })
  }

  if (sum !== data.amountXaf) throw new Error('Total du reçu incohérent.')
  return {
    saleId: data.saleId,
    receiptNumber: data.receiptNumber,
    confirmedAt: data.confirmedAt,
    cashierFirstName: data.cashierFirstName,
    method: data.method as ManualPaymentMethod,
    amountXaf: data.amountXaf as number,
    lines,
  }
}

/** Server records the shop owner's manual attestation, not a payment-provider event.
 * The existing production cashier does NOT call this; migration is not deployed.
 */
export async function confirmManualCheckoutPayment({
  shopId,
  orderId,
  operationId,
  attestation,
}: {
  shopId: string
  orderId: string
  operationId: string
  attestation: ManualCashierAttestation
}): Promise<RecordedCheckoutReceipt> {
  if (!shopId || !orderId || !operationId) {
    throw new Error('Impossible de confirmer sans identifiants de commande.')
  }
  const input = prepareManualCashierAttestation(attestation)
  const futureClient = supabase as unknown as FutureCheckoutRpc
  const { data, error } = await futureClient.rpc('confirm_manual_checkout_payment', {
    p_shop_id: shopId,
    p_order_id: orderId,
    p_operation_id: operationId,
    p_cashier_first_name: input.cashierFirstName,
    p_method: input.method,
    p_external_reference: input.externalReference ?? null,
    p_pin: input.pin ?? null,
  })
  if (error) throw new Error(error.message)
  if (data && typeof data === 'object' && 'pinRejected' in data)
    throw new Error('Code personnel incorrect ou compte temporairement bloqué.')
  return parseRecordedCheckoutReceipt(data)
}
