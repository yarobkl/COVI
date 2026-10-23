// Accès aux fonctions serveur du module Salon. Toutes les lectures et écritures passent par des
// fonctions SECURITY DEFINER qui vérifient le rôle de l'utilisateur côté serveur
// (supabase/migrations/20261024090000…95000) : ce module ne lit ni n'écrit aucune table salon
// directement.
import { supabase } from './supabase'

export type SalonRole = 'owner' | 'manager' | 'cashier' | 'stylist'
export type AppointmentStatus =
  'pending' | 'confirmed' | 'arrived' | 'in_progress' | 'completed' | 'cancelled' | 'no_show'
export type PaymentMethod = 'cash' | 'mobile_money' | 'card' | 'other'
export type CommissionMode = 'none' | 'percent' | 'fixed'
export type SupplyUnit = 'piece' | 'ml' | 'l' | 'g' | 'kg'
export type SupplyUsage = 'sale' | 'consumption' | 'both'
export type SalonType = 'men' | 'women' | 'mixed' | 'barber' | 'beauty'

export type DayHours = { weekday: number; opens_at: string; closes_at: string }
export type StaffHours = { weekday: number; starts_at: string; ends_at: string }

export type SalonSettings = {
  role: SalonRole
  shop: {
    id: string
    name: string
    city: string | null
    country: string | null
    neighborhood: string | null
    address_line: string | null
    currency: string
  }
  settings: {
    salon_type: SalonType
    owner_name: string | null
    business_phone: string | null
    expected_staff_count: number | null
    time_zone: string
  }
  opening_hours: DayHours[]
  configured: boolean
}

export type SalonService = {
  id: string
  name: string
  category: string | null
  description: string | null
  price_xaf: number
  duration_minutes: number
  direct_cost_xaf: number | null
  active: boolean
  employee_ids: string[]
}
export type SalonStaffBrief = {
  employee_id: string
  full_name: string
  job_title: string
  active: boolean
  agenda_color: string
}
export type SalonCatalog = { services: SalonService[]; staff: SalonStaffBrief[] }

export type SalonStaff = {
  employee_id: string
  full_name: string
  job_title: string
  active: boolean
  phone: string | null
  agenda_color: string
  commission_mode: CommissionMode
  commission_percent: number
  commission_fixed_xaf: number
  service_ids: string[]
  hours: StaffHours[]
  absences: { day: string; reason: string | null }[]
  account: { member_id: string; role: SalonRole; active: boolean; display_name: string } | null
}

export type AppointmentService = {
  service_id: string
  name: string
  price_xaf: number
  duration_minutes: number
}
export type Appointment = {
  id: string
  client_id: string | null
  client_name: string
  client_phone: string | null
  employee_id: string
  employee_name: string
  starts_at: string
  ends_at: string
  status: AppointmentStatus
  source: 'manual' | 'walk_in' | 'request'
  estimated_price_xaf: number
  notes: string | null
  services: AppointmentService[]
  ticket: { id: string; status: TicketStatus } | null
}
export type PendingRequest = {
  id: string
  client_name: string
  phone: string
  requested_at: string
  service_id: string | null
  duration_minutes: number | null
}
export type Agenda = {
  role: SalonRole
  time_zone: string
  appointments: Appointment[]
  pending_requests: PendingRequest[]
}

export type ClientBrief = {
  id: string
  first_name: string
  last_name: string | null
  phone: string | null
  last_visit_at: string | null
  visits: number
}
export type ClientCard = {
  id: string
  first_name: string
  last_name: string | null
  phone: string | null
  email: string | null
  preferences: string | null
  preferences_consent: boolean
  reminder_consent: boolean
  consent_recorded_at: string | null
  anonymized: boolean
  created_at: string
  visits: number
  no_shows: number
  total_spent_xaf: number
  last_visit_at: string | null
  upcoming: { id: string; starts_at: string; status: AppointmentStatus; employee_name: string }[]
  history: {
    id: string
    starts_at: string
    status: AppointmentStatus
    employee_name: string
    services: string | null
  }[]
}
export type ClientSaveResult =
  | { status: 'ok'; id: string }
  | {
      status: 'possible_duplicate'
      duplicates: {
        id: string
        first_name: string
        last_name: string | null
        phone: string | null
      }[]
    }

export type Supply = {
  id: string
  name: string
  category: string | null
  unit: SupplyUnit
  usage: SupplyUsage
  quantity_on_hand: number
  alert_threshold: number
  low: boolean
  unit_cost_xaf: number | null
  sale_price_xaf: number | null
  active: boolean
}

export type TicketStatus = 'open' | 'paid' | 'partially_refunded' | 'refunded' | 'cancelled'
export type TicketLine = {
  id: string
  kind: 'service' | 'product'
  service_id: string | null
  supply_id: string | null
  employee_id: string | null
  employee_name: string | null
  label: string
  quantity: number
  list_price_xaf: number
  unit_price_xaf: number
  line_total_xaf: number
  net_xaf: number | null
  refunded: boolean
}
export type TicketPayment = {
  id: string
  kind: 'payment' | 'refund'
  method: PaymentMethod
  amount_xaf: number
  reference: string | null
  confirmation: 'manual'
  recorded_at: string
}
export type Ticket = {
  id: string
  status: TicketStatus
  appointment_id: string | null
  client_id: string | null
  client_name: string | null
  subtotal_xaf: number
  discount_xaf: number
  total_xaf: number
  paid_xaf: number
  refunded_xaf: number
  opened_at: string
  paid_at: string | null
  lines: TicketLine[]
  payments: TicketPayment[]
}
export type TicketBrief = Pick<
  Ticket,
  | 'id'
  | 'status'
  | 'client_name'
  | 'total_xaf'
  | 'paid_xaf'
  | 'refunded_xaf'
  | 'opened_at'
  | 'paid_at'
  | 'appointment_id'
>

export type CommissionBalance = {
  employee_id: string
  full_name: string
  earned_xaf: number
  paid_xaf: number
  balance_xaf: number
}

export type ReportFinance = {
  services_revenue_xaf: number
  products_revenue_xaf: number
  revenue_xaf: number
  service_direct_costs_xaf: number
  product_costs_xaf: number
  gross_margin_xaf: number
  commissions_due_xaf: number
  other_charges_xaf: number
  commission_category_charges_xaf: number
  estimated_result_xaf: number
  payments_xaf: number
  refunds_xaf: number
  net_collected_xaf: number
  commissions_paid_xaf: number
  purchases_xaf: number
  estimated_cash_flow_xaf: number
  pending_checkout_xaf: number
  pending_checkout_count: number
  paid_tickets: number
  average_ticket_xaf: number
}
export type ReportActivity = {
  appointments: number
  completed: number
  cancelled: number
  no_show: number
  upcoming: number
  walk_ins: number
  honoured_rate: number | null
  cancellation_rate: number | null
}
export type SalonReport = {
  period: { from: string; to: string; time_zone: string }
  finance: ReportFinance
  payment_methods: {
    method: PaymentMethod
    payments_xaf: number
    refunds_xaf: number
    net_xaf: number
  }[]
  activity: ReportActivity
  clients: { served: number; identified: number; returning: number; new_clients: number }
  services: {
    service_id: string
    name: string
    count: number
    revenue_xaf: number
    margin_xaf: number
  }[]
  staff: {
    employee_id: string
    full_name: string
    services: number
    revenue_xaf: number
    commission_xaf: number
  }[]
  weekdays: { weekday: number; appointments: number; revenue_xaf: number }[]
  daily: { day: string; revenue_xaf: number }[]
  consumables: {
    supply_id: string
    name: string
    unit: SupplyUnit
    quantity: number
    cost_xaf: number
  }[]
}
export type SalonDashboard = {
  today: string
  time_zone: string
  setup: {
    configured: boolean
    services: number
    staff: number
    appointments: number
    tickets: number
  }
  day: SalonReport
  month: ReportFinance
  alerts: {
    upcoming: {
      id: string
      client_name: string
      starts_at: string
      employee_name: string
      status: AppointmentStatus
    }[]
    late: { id: string; client_name: string; starts_at: string; employee_name: string }[]
    low_stock: {
      id: string
      name: string
      quantity_on_hand: number
      unit: SupplyUnit
      alert_threshold: number
    }[]
    stock_shortfalls: number
    pending_requests: number
    open_tickets: number
  }
  staff_today: {
    employee_id: string
    full_name: string
    agenda_color: string
    starts_at: string
    ends_at: string
    appointments: number
    free_minutes_left: number
  }[]
}

export type StaffAccounts = {
  members: {
    id: string
    display_name: string
    role: Exclude<SalonRole, 'owner'>
    active: boolean
    employee_id: string | null
    created_at: string
  }[]
  invites: {
    id: string
    display_name: string
    role: Exclude<SalonRole, 'owner'>
    expires_at: string
  }[]
}
export type SalonSpace = {
  shop_id: string
  shop_name: string
  role: Exclude<SalonRole, 'owner'>
  display_name: string
  employee_id: string | null
}

/** Erreur métier traduite pour l'écran (jamais le détail technique de la base). */
export class SalonError extends Error {}

type RpcResult = { data: unknown; error: { message: string; code?: string } | null }
// Les fonctions salon ne figurent pas dans database.types.ts (générés depuis la production, où
// ces migrations ne sont pas encore appliquées) : appel non typé, résultat typé ici.
type RpcFn = (fn: string, args?: Record<string, unknown>) => PromiseLike<RpcResult>
// Lu à chaque appel (et non au chargement du module) : un client simulé sans rpc ne casse rien.
const rpc: RpcFn = (fn, args) => (supabase.rpc as unknown as RpcFn).call(supabase, fn, args)

const messages: [RegExp, string][] = [
  [/already booked/i, 'Ce collaborateur a déjà un rendez-vous sur ce créneau.'],
  [/not qualified/i, 'Ce collaborateur n’est pas habilité pour cette prestation.'],
  [/salon closed/i, 'Le salon est fermé à cette heure-là.'],
  [/not working/i, 'Ce collaborateur ne travaille pas à cette heure-là.'],
  [/absent this day/i, 'Ce collaborateur est absent ce jour-là.'],
  [/collaborator unavailable/i, 'Ce collaborateur n’est pas disponible.'],
  [/in the past|to the past/i, 'Impossible de prendre un rendez-vous dans le passé.'],
  [/walk-in starts now/i, 'Une visite sans rendez-vous commence maintenant.'],
  [/within one day/i, 'Un rendez-vous doit tenir dans la même journée.'],
  [/choose at least one service/i, 'Choisissez au moins une prestation.'],
  [/service unavailable/i, 'Cette prestation n’est plus proposée.'],
  [/client name is required/i, 'Indiquez le nom du client.'],
  [/invalid status transition/i, 'Ce changement d’étape n’est pas possible.'],
  [/absent before/i, 'Le client ne peut pas être absent avant l’heure du rendez-vous.'],
  [/cancel the open checkout/i, 'Annulez d’abord la note ouverte de ce rendez-vous.'],
  [/checkout is already open/i, 'Une note est déjà ouverte pour ce rendez-vous.'],
  [/can no longer be changed/i, 'Ce rendez-vous ne peut plus être modifié.'],
  [/cannot be checked out/i, 'Ce rendez-vous ne peut pas être encaissé.'],
  [/payments must equal/i, 'La somme des paiements doit être égale au total.'],
  [/not enough stock for (.+)/i, 'Stock insuffisant pour $1.'],
  [/not enough stock/i, 'Stock insuffisant.'],
  [/ticket is not open/i, 'Cette note est déjà réglée ou annulée.'],
  [/empty ticket/i, 'Ajoutez au moins une ligne.'],
  [/only a manager can change a price/i, 'Seul un responsable peut changer un prix.'],
  [/only an unpaid open ticket/i, 'Seule une note non réglée peut être annulée.'],
  [/only a paid ticket can be refunded/i, 'Seule une note réglée peut être remboursée.'],
  [/refund exceeds/i, 'Le remboursement dépasse le montant payé.'],
  [/invalid lines to refund/i, 'Ces lignes sont déjà remboursées.'],
  [/a reason is required/i, 'Indiquez le motif (3 caractères au moins).'],
  [/exceeds commission due/i, 'Le montant dépasse la commission due.'],
  [/only the owner can set commissions/i, 'Seul le propriétaire fixe les commissions.'],
  [/possible duplicate/i, 'Ce client existe peut-être déjà.'],
  [/unit cannot change/i, 'L’unité ne change plus une fois du stock enregistré.'],
  [/stock unchanged/i, 'La quantité est déjà celle-ci.'],
  [/for sale only cannot be consumed/i, 'Un produit réservé à la vente ne peut pas être consommé.'],
  [/stylist account must be linked/i, 'Un compte coiffeur doit être relié à sa fiche.'],
  [/too many pending/i, 'Trop d’invitations en attente.'],
  [/operation key already used/i, 'Opération déjà enregistrée sur une autre note.'],
  [
    /could not find the function|function .* does not exist|schema cache/i,
    'Le module Salon professionnel n’est pas encore activé sur ce serveur (mise à jour de la base en attente).',
  ],
  [
    /access denied|authentication required|not found/i,
    'Action non autorisée ou élément introuvable.',
  ],
]

export function salonErrorMessage(error: unknown): string {
  if (error instanceof SalonError) return error.message
  const text = error instanceof Error ? error.message : String(error ?? '')
  for (const [pattern, message] of messages) {
    const match = text.match(pattern)
    if (match) return message.replace('$1', match[1] ?? '')
  }
  if (/check constraint|violates|invalid input/i.test(text))
    return 'Vérifiez les informations saisies.'
  if (/fetch|network|failed to/i.test(text))
    return 'Pas de connexion : rien n’a été enregistré, réessayez.'
  return 'L’opération n’a pas abouti. Réessayez.'
}

async function call<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await rpc(fn, args)
  if (error) throw new SalonError(salonErrorMessage(new Error(error.message)))
  return data as T
}

/** Clé d'opération : la même clé renvoyée deux fois (réseau, double clic) ne compte qu'une fois. */
export const operationKey = () =>
  typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
    ? crypto.randomUUID()
    : `op-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`

export const salonApi = {
  role: (shop: string) => call<SalonRole | null>('salon_role', { p_shop: shop }),
  settings: (shop: string) => call<SalonSettings>('salon_settings_get', { p_shop: shop }),
  saveSettings: (
    shop: string,
    v: {
      salonType: SalonType
      ownerName: string
      phone: string
      staffCount: number | null
      timeZone: string
      hours: DayHours[]
    },
  ) =>
    call<SalonSettings>('salon_settings_save', {
      p_shop: shop,
      p_salon_type: v.salonType,
      p_owner_name: v.ownerName,
      p_business_phone: v.phone,
      p_expected_staff_count: v.staffCount,
      p_time_zone: v.timeZone,
      p_hours: v.hours,
    }),
  catalog: (shop: string) => call<SalonCatalog>('salon_catalog', { p_shop: shop }),
  saveService: (
    shop: string,
    v: {
      id: string | null
      name: string
      category: string
      description: string
      priceXaf: number
      durationMinutes: number
      directCostXaf: number
      active: boolean
      employeeIds: string[]
    },
  ) =>
    call<string>('salon_service_save', {
      p_shop: shop,
      p_id: v.id,
      p_name: v.name,
      p_category: v.category,
      p_description: v.description,
      p_price_xaf: v.priceXaf,
      p_duration_minutes: v.durationMinutes,
      p_direct_cost_xaf: v.directCostXaf,
      p_active: v.active,
      p_employee_ids: v.employeeIds,
    }),
  consumables: (shop: string, service: string) =>
    call<{ supply_id: string; name: string; unit: SupplyUnit; quantity: number }[]>(
      'salon_service_consumables_get',
      { p_shop: shop, p_service: service },
    ),
  setConsumables: (
    shop: string,
    service: string,
    items: { supply_id: string; quantity: number }[],
  ) =>
    call<null>('salon_service_consumables_set', {
      p_shop: shop,
      p_service: service,
      p_items: items,
    }),
  staff: (shop: string) => call<SalonStaff[]>('salon_staff_list', { p_shop: shop }),
  saveStaff: (
    shop: string,
    v: {
      id: string | null
      fullName: string
      jobTitle: string
      phone: string
      commissionMode: CommissionMode
      commissionPercent: number
      commissionFixedXaf: number
      color: string
      active: boolean
      serviceIds: string[] | null
    },
  ) =>
    call<string>('salon_staff_save', {
      p_shop: shop,
      p_employee: v.id,
      p_full_name: v.fullName,
      p_job_title: v.jobTitle,
      p_phone: v.phone,
      p_commission_mode: v.commissionMode,
      p_commission_percent: v.commissionPercent,
      p_commission_fixed_xaf: v.commissionFixedXaf,
      p_agenda_color: v.color,
      p_active: v.active,
      p_service_ids: v.serviceIds,
    }),
  setStaffHours: (shop: string, employee: string, hours: StaffHours[]) =>
    call<null>('salon_staff_hours_set', { p_shop: shop, p_employee: employee, p_hours: hours }),
  setAbsence: (shop: string, employee: string, day: string, absent: boolean, reason: string) =>
    call<null>('salon_staff_absence_set', {
      p_shop: shop,
      p_employee: employee,
      p_day: day,
      p_absent: absent,
      p_reason: reason,
    }),
  agenda: (shop: string, from: Date, to: Date) =>
    call<Agenda>('salon_agenda', {
      p_shop: shop,
      p_from: from.toISOString(),
      p_to: to.toISOString(),
    }),
  saveAppointment: (
    shop: string,
    v: {
      id: string | null
      clientId: string | null
      clientName: string
      clientPhone: string
      employeeId: string
      startsAt: Date
      serviceIds: string[]
      durationMinutes: number | null
      notes: string
      source?: 'manual' | 'walk_in'
    },
  ) =>
    call<string>('salon_appointment_save', {
      p_shop: shop,
      p_id: v.id,
      p_client_id: v.clientId,
      p_client_name: v.clientName,
      p_client_phone: v.clientPhone,
      p_employee: v.employeeId,
      p_starts_at: v.startsAt.toISOString(),
      p_service_ids: v.serviceIds,
      p_duration_minutes: v.durationMinutes,
      p_notes: v.notes,
      p_status: 'confirmed',
      p_source: v.source ?? 'manual',
      p_request_id: null,
    }),
  setStatus: (shop: string, id: string, status: AppointmentStatus, reason = '') =>
    call<AppointmentStatus>('salon_appointment_set_status', {
      p_shop: shop,
      p_id: id,
      p_status: status,
      p_reason: reason,
    }),
  /** Refuse une demande en attente (fonction existante du premier agenda salon). */
  declineRequest: (shop: string, request: string) =>
    call<string>('salon_change_booking_status', {
      p_shop: shop,
      p_booking: request,
      p_status: 'declined',
    }),
  scheduleRequest: (shop: string, request: string, employee: string) =>
    call<string>('salon_request_to_appointment', {
      p_shop: shop,
      p_request: request,
      p_employee: employee,
    }),
  searchClients: (shop: string, query: string) =>
    call<ClientBrief[]>('salon_clients_search', { p_shop: shop, p_query: query, p_limit: 30 }),
  client: (shop: string, id: string) =>
    call<ClientCard>('salon_client_get', { p_shop: shop, p_id: id }),
  saveClient: (
    shop: string,
    v: {
      id: string | null
      firstName: string
      lastName: string
      phone: string
      email: string
      preferences: string
      preferencesConsent: boolean
      reminderConsent: boolean
      force: boolean
    },
  ) =>
    call<ClientSaveResult>('salon_client_save', {
      p_shop: shop,
      p_id: v.id,
      p_first_name: v.firstName,
      p_last_name: v.lastName,
      p_phone: v.phone,
      p_email: v.email,
      p_preferences: v.preferences,
      p_preferences_consent: v.preferencesConsent,
      p_reminder_consent: v.reminderConsent,
      p_force: v.force,
    }),
  anonymizeClient: (shop: string, id: string) =>
    call<null>('salon_client_anonymize', { p_shop: shop, p_id: id }),
  supplies: (shop: string) => call<Supply[]>('salon_supplies_list', { p_shop: shop }),
  saveSupply: (
    shop: string,
    v: {
      id: string | null
      name: string
      category: string
      unit: SupplyUnit
      usage: SupplyUsage
      alertThreshold: number
      unitCostXaf: number
      salePriceXaf: number | null
      active: boolean
    },
  ) =>
    call<string>('salon_supply_save', {
      p_shop: shop,
      p_id: v.id,
      p_name: v.name,
      p_category: v.category,
      p_unit: v.unit,
      p_usage: v.usage,
      p_alert_threshold: v.alertThreshold,
      p_unit_cost_xaf: v.unitCostXaf,
      p_sale_price_xaf: v.salePriceXaf,
      p_active: v.active,
    }),
  adjustSupply: (
    shop: string,
    v: {
      supplyId: string
      reason: 'purchase' | 'return' | 'loss' | 'correction'
      quantity: number
      unitCostXaf: number | null
      note: string
      key: string
    },
  ) =>
    call<number>('salon_supply_adjust', {
      p_shop: shop,
      p_supply: v.supplyId,
      p_reason: v.reason,
      p_quantity: v.quantity,
      p_unit_cost_xaf: v.unitCostXaf,
      p_note: v.note,
      p_operation_key: v.key,
    }),
  openTicket: (
    shop: string,
    v: { appointmentId: string | null; clientId: string | null; clientName: string; key: string },
  ) =>
    call<Ticket>('salon_ticket_open', {
      p_shop: shop,
      p_appointment: v.appointmentId,
      p_client_id: v.clientId,
      p_client_name: v.clientName,
      p_operation_key: v.key,
    }),
  ticket: (shop: string, id: string) =>
    call<Ticket>('salon_ticket_get', { p_shop: shop, p_ticket: id }),
  recentTickets: (shop: string, days = 1) =>
    call<TicketBrief[]>('salon_tickets_recent', { p_shop: shop, p_days: days }),
  addLine: (
    shop: string,
    ticket: string,
    v: {
      kind: 'service' | 'product'
      itemId: string
      employeeId: string | null
      quantity: number
      unitPriceXaf: number | null
    },
  ) =>
    call<Ticket>('salon_ticket_add_line', {
      p_shop: shop,
      p_ticket: ticket,
      p_kind: v.kind,
      p_item: v.itemId,
      p_employee: v.employeeId,
      p_quantity: v.quantity,
      p_unit_price_xaf: v.unitPriceXaf,
    }),
  removeLine: (shop: string, ticket: string, line: string) =>
    call<Ticket>('salon_ticket_remove_line', { p_shop: shop, p_ticket: ticket, p_line: line }),
  setDiscount: (shop: string, ticket: string, discount: number) =>
    call<Ticket>('salon_ticket_set_discount', {
      p_shop: shop,
      p_ticket: ticket,
      p_discount_xaf: discount,
    }),
  cancelTicket: (shop: string, ticket: string) =>
    call<Ticket>('salon_ticket_cancel', { p_shop: shop, p_ticket: ticket }),
  pay: (
    shop: string,
    ticket: string,
    payments: { method: PaymentMethod; amount_xaf: number; reference: string | null }[],
    key: string,
  ) =>
    call<Ticket>('salon_ticket_pay', {
      p_shop: shop,
      p_ticket: ticket,
      p_payments: payments,
      p_operation_key: key,
    }),
  refund: (
    shop: string,
    ticket: string,
    v: { lineIds: string[]; method: PaymentMethod; restock: boolean; reason: string; key: string },
  ) =>
    call<Ticket>('salon_ticket_refund', {
      p_shop: shop,
      p_ticket: ticket,
      p_line_ids: v.lineIds,
      p_method: v.method,
      p_restock: v.restock,
      p_reason: v.reason,
      p_operation_key: v.key,
    }),
  commissionBalances: (shop: string) =>
    call<CommissionBalance[]>('salon_commission_balances', { p_shop: shop }),
  payCommission: (
    shop: string,
    v: { employeeId: string; amountXaf: number; method: PaymentMethod; note: string; key: string },
  ) =>
    call<CommissionBalance[]>('salon_commission_pay', {
      p_shop: shop,
      p_employee: v.employeeId,
      p_amount_xaf: v.amountXaf,
      p_method: v.method,
      p_note: v.note,
      p_operation_key: v.key,
    }),
  report: (shop: string, from: string, to: string) =>
    call<SalonReport>('salon_report', { p_shop: shop, p_from: from, p_to: to }),
  dashboard: (shop: string) => call<SalonDashboard>('salon_dashboard', { p_shop: shop }),
  staffAccounts: (shop: string) => call<StaffAccounts>('salon_staff_accounts', { p_shop: shop }),
  createInvite: (
    shop: string,
    v: { displayName: string; role: Exclude<SalonRole, 'owner'>; employeeId: string | null },
  ) =>
    call<{ invite_id: string; code: string; display_name: string; role: string }>(
      'salon_staff_create_invite',
      {
        p_shop: shop,
        p_display_name: v.displayName,
        p_role: v.role,
        p_employee: v.employeeId,
      },
    ),
  disableMember: (shop: string, member: string) =>
    call<boolean>('salon_staff_disable', { p_shop: shop, p_member: member }),
  revokeInvite: (shop: string, invite: string) =>
    call<boolean>('salon_staff_revoke_invite', { p_shop: shop, p_invite: invite }),
  join: (code: string) =>
    call<{ ok: boolean; reason?: 'locked' | 'invalid' | 'already_member'; shop_id?: string }>(
      'salon_staff_join',
      { p_code: code },
    ),
  mySpaces: () => call<SalonSpace[]>('salon_staff_my_spaces', {}),
}
