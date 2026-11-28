import { describe, expect, it } from 'vitest'
import {
  addDays,
  csvCell,
  minutesLabel,
  mondayOf,
  nextStatuses,
  salonDay,
  salonInstant,
  salonTime,
  toCsv,
  whatsappHref,
  zoneOffsetMinutes,
} from './salonFormat'

const tz = 'Africa/Brazzaville'

describe('heure du salon', () => {
  it('Brazzaville est à UTC+1 toute l’année', () => {
    expect(zoneOffsetMinutes(tz, new Date('2026-01-15T12:00:00Z'))).toBe(60)
    expect(zoneOffsetMinutes(tz, new Date('2026-07-15T12:00:00Z'))).toBe(60)
  })

  it('10 h 00 à Brazzaville = 9 h 00 UTC, quel que soit le fuseau du téléphone', () => {
    expect(salonInstant('2026-10-24', '10:00', tz).toISOString()).toBe('2026-10-24T09:00:00.000Z')
    expect(salonInstant('2026-10-24', '00:30', tz).toISOString()).toBe('2026-10-23T23:30:00.000Z')
    expect(salonTime('2026-10-24T09:00:00Z', tz)).toBe('10:00')
  })

  it('la date du jour suit le salon, pas UTC', () => {
    expect(salonDay(new Date('2026-10-23T23:30:00Z'), tz)).toBe('2026-10-24')
  })

  it('calendrier : jours, lundi, durées', () => {
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01')
    expect(addDays('2026-03-01', -1)).toBe('2026-02-28')
    expect(mondayOf('2026-10-25')).toBe('2026-10-19') // dimanche → lundi précédent
    expect(mondayOf('2026-10-19')).toBe('2026-10-19')
    expect(minutesLabel(90)).toBe('1 h 30')
    expect(minutesLabel(45)).toBe('45 min')
    expect(minutesLabel(120)).toBe('2 h')
  })
})

describe('étapes d’un rendez-vous', () => {
  it('suit les règles du serveur', () => {
    expect(nextStatuses('confirmed', 'owner')).toEqual([
      'arrived',
      'in_progress',
      'no_show',
      'cancelled',
    ])
    expect(nextStatuses('in_progress', 'owner')).toEqual(['completed'])
    expect(nextStatuses('completed', 'owner')).toEqual([])
  })

  it('le coiffeur ne peut ni annuler ni marquer absent', () => {
    expect(nextStatuses('confirmed', 'stylist')).toEqual(['arrived', 'in_progress'])
    expect(nextStatuses('pending', 'stylist')).toEqual([])
  })
})

describe('export CSV', () => {
  it('protège les séparateurs, guillemets et formules', () => {
    expect(csvCell('Coupe; barbe')).toBe('"Coupe; barbe"')
    expect(csvCell('Dit "oui"')).toBe('"Dit ""oui"""')
    expect(csvCell('=SOMME(A1)')).toBe("'=SOMME(A1)")
    expect(csvCell(null)).toBe('')
    expect(
      toCsv([
        ['a', 1],
        ['b', 2],
      ]),
    ).toBe('﻿a;1\r\nb;2\r\n')
  })
})

describe('WhatsApp', () => {
  it('ouvre une conversation, sans prétendre envoyer', () => {
    expect(whatsappHref('06 555 12 34', 'Bonjour')).toBe('https://wa.me/242065551234?text=Bonjour')
    expect(whatsappHref('+242 06 555 12 34', 'À demain')).toBe(
      'https://wa.me/242065551234?text=%C3%80%20demain',
    )
  })
})
