// Mots, dates et petits calculs d'affichage du salon. Aucun calcul d'argent ici : les montants
// viennent tous du serveur (salon_report, salon_ticket_*).
import type {
  AppointmentStatus,
  CommissionMode,
  PaymentMethod,
  SalonRole,
  SalonType,
  SupplyUnit,
  SupplyUsage,
} from '../../lib/salon'

export const statusLabels: Record<AppointmentStatus, string> = {
  pending: 'En attente',
  confirmed: 'Confirmé',
  arrived: 'Client arrivé',
  in_progress: 'En cours',
  completed: 'Terminé',
  cancelled: 'Annulé',
  no_show: 'Client absent',
}

export const statusTone: Record<
  AppointmentStatus,
  'action' | 'transit' | 'success' | 'danger' | 'low' | 'waiting'
> = {
  pending: 'waiting',
  confirmed: 'action',
  arrived: 'transit',
  in_progress: 'transit',
  completed: 'success',
  cancelled: 'danger',
  no_show: 'danger',
}

/** Étapes suivantes possibles, dans l'ordre où on les propose (mêmes règles que le serveur). */
export function nextStatuses(status: AppointmentStatus, role: SalonRole): AppointmentStatus[] {
  const all: Record<AppointmentStatus, AppointmentStatus[]> = {
    pending: ['confirmed', 'cancelled'],
    confirmed: ['arrived', 'in_progress', 'no_show', 'cancelled'],
    arrived: ['in_progress', 'no_show', 'cancelled'],
    in_progress: ['completed'],
    completed: [],
    cancelled: [],
    no_show: [],
  }
  const next = all[status]
  return role === 'stylist'
    ? next.filter((s) => s === 'arrived' || s === 'in_progress' || s === 'completed')
    : next
}

export const roleLabels: Record<SalonRole, string> = {
  owner: 'Propriétaire',
  manager: 'Responsable',
  cashier: 'Caissier',
  stylist: 'Coiffeur',
}

export const methodLabels: Record<PaymentMethod, string> = {
  cash: 'Espèces',
  mobile_money: 'Mobile Money',
  card: 'Carte',
  other: 'Autre',
}

export const salonTypeLabels: Record<SalonType, string> = {
  men: 'Hommes',
  women: 'Femmes',
  mixed: 'Mixte',
  barber: 'Barbier',
  beauty: 'Esthétique et coiffure',
}

export const unitLabels: Record<SupplyUnit, string> = {
  piece: 'pièce',
  ml: 'ml',
  l: 'litre',
  g: 'g',
  kg: 'kg',
}

export const usageLabels: Record<SupplyUsage, string> = {
  sale: 'À vendre',
  consumption: 'Consommé en prestation',
  both: 'Vente et prestation',
}

export const commissionLabel = (mode: CommissionMode, percent: number, fixed: number) =>
  mode === 'percent'
    ? `${percent.toLocaleString('fr-FR')} % du montant`
    : mode === 'fixed'
      ? `${fixed.toLocaleString('fr-FR')} FCFA par prestation`
      : 'Aucune commission'

export const weekdayLabels = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
]

/** Décalage (minutes) du fuseau `tz` à l'instant `at` : Brazzaville → +60. */
export function zoneOffsetMinutes(tz: string, at: Date): number {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(at)
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? 0)
  const asUtc = Date.UTC(
    get('year'),
    get('month') - 1,
    get('day'),
    get('hour'),
    get('minute'),
    get('second'),
  )
  return Math.round((asUtc - at.getTime()) / 60000)
}

/** Instant correspondant à `day` (AAAA-MM-JJ) à `time` (HH:MM) à l'heure du salon. */
export function salonInstant(day: string, time: string, tz: string): Date {
  const [y, m, d] = day.split('-').map(Number)
  const [hh, mm] = time.split(':').map(Number)
  const guess = Date.UTC(y, m - 1, d, hh, mm)
  const offset = zoneOffsetMinutes(tz, new Date(guess))
  const first = new Date(guess - offset * 60000)
  // Second passage : exact même si le décalage change ce jour-là (pas en Afrique centrale).
  return new Date(guess - zoneOffsetMinutes(tz, first) * 60000)
}

/** Date du jour (AAAA-MM-JJ) à l'heure du salon. */
export function salonDay(at: Date, tz: string): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(at)
}

export function salonTime(at: Date | string, tz: string): string {
  return new Intl.DateTimeFormat('fr-FR', {
    timeZone: tz,
    hour: '2-digit',
    minute: '2-digit',
  }).format(typeof at === 'string' ? new Date(at) : at)
}

export function salonDateLabel(at: Date | string, tz: string, withYear = false): string {
  return new Intl.DateTimeFormat('fr-FR', {
    timeZone: tz,
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    ...(withYear ? { year: 'numeric' } : {}),
  }).format(typeof at === 'string' ? new Date(at) : at)
}

/** Ajoute `n` jours à une date AAAA-MM-JJ (calendrier, sans fuseau). */
export function addDays(day: string, n: number): string {
  const [y, m, d] = day.split('-').map(Number)
  const t = new Date(Date.UTC(y, m - 1, d + n))
  return t.toISOString().slice(0, 10)
}

/** Lundi de la semaine de `day` (AAAA-MM-JJ). */
export function mondayOf(day: string): string {
  const [y, m, d] = day.split('-').map(Number)
  const isoDow = ((new Date(Date.UTC(y, m - 1, d)).getUTCDay() + 6) % 7) + 1
  return addDays(day, 1 - isoDow)
}

export const minutesLabel = (n: number) => {
  const h = Math.floor(n / 60)
  const m = n % 60
  return h === 0 ? `${m} min` : m === 0 ? `${h} h` : `${h} h ${String(m).padStart(2, '0')}`
}

/** Une cellule CSV : guillemets doublés, et neutralisation des formules (=, +, -, @). */
export function csvCell(value: unknown): string {
  let text = value === null || value === undefined ? '' : String(value)
  if (/^[=+\-@\t\r]/.test(text)) text = `'${text}`
  return /[";\n\r]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text
}

/** Fichier CSV lisible par Excel en français (séparateur « ; », BOM UTF-8). */
export function toCsv(rows: unknown[][]): string {
  return '﻿' + rows.map((row) => row.map(csvCell).join(';')).join('\r\n') + '\r\n'
}

export function downloadCsv(filename: string, rows: unknown[][]) {
  const blob = new Blob([toCsv(rows)], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

/** Lien WhatsApp vers un numéro : ouvre l'application, n'envoie rien tout seul. */
export function whatsappHref(phone: string, text: string): string {
  const digits = phone.replace(/[^0-9]/g, '')
  const intl = digits.length === 9 ? `242${digits}` : digits
  return `https://wa.me/${intl}?text=${encodeURIComponent(text)}`
}
