// Fictitious three months (July to September 2026) at « Chez Mama Grâce », shown by the example
// shop. Nothing here is read from or written to Supabase.

type Line = {
  name: string
  category: string
  arrival: string
  initial: number
  sold: number
  quantity: number
}
export type Ticket = { id: string; date: Date; payment: string; lines: Line[]; total: number }
type Unit = Omit<Line, 'quantity'>

const BALE_PIECE = 'pièce de ballon'
/** Garments taken out of the bale, in turn. */
const balePieces = [
  'Veste en jean',
  'Robe pagne',
  'Chemise à carreaux',
  'Pantalon cargo',
  'Jupe plissée',
  'Blouson léger',
]

const paymentMethods = ['Espèces', 'Mobile Money', 'Carte', 'Virement']

function monthlyUnits(month: number): Unit[] {
  const counts: Record<number, Array<[string, string, string, number, number, number]>> = {
    6: [
      ['Robe wax modèle A', 'Robes', 'CHN-001', 18000, 18000, 8],
      ['Jean droit modèle B', 'Jeans', 'CHN-001', 22000, 22000, 5],
      ['Chemise lin modèle C', 'Chemises', 'CHN-001', 12000, 12000, 10],
      [BALE_PIECE, 'Friperie', 'BAL-001', 15000, 10000, 12],
    ],
    7: [
      ['Robe wax modèle A', 'Robes', 'CHN-001', 18000, 18000, 7],
      ['Jean droit modèle B', 'Jeans', 'CHN-001', 22000, 22000, 5],
      ['Chemise lin modèle C', 'Chemises', 'CHN-001', 12000, 12000, 10],
      [BALE_PIECE, 'Friperie', 'BAL-001', 15000, 15000, 22],
      ['Ensemble brodé modèle D', 'Ensembles', 'IND-002', 20000, 20000, 15],
    ],
    8: [
      ['Robe wax modèle A', 'Robes', 'CHN-001', 18000, 18000, 5],
      ['Jean droit modèle B', 'Jeans', 'CHN-001', 22000, 22000, 4],
      ['Chemise lin modèle C', 'Chemises', 'CHN-001', 12000, 12000, 8],
      [BALE_PIECE, 'Friperie', 'BAL-001', 15000, 15000, 12],
      ['Ensemble brodé modèle D', 'Ensembles', 'IND-002', 20000, 20000, 20],
    ],
  }
  const rows = counts[month] ?? []
  let piece = 0
  return rows.flatMap(([name, category, arrival, initial, sold, quantity]) =>
    Array.from({ length: quantity }, () => ({
      // Each piece of a bale is a different garment.
      name: name === BALE_PIECE ? balePieces[piece++ % balePieces.length] : name,
      category,
      arrival,
      initial,
      sold,
    })),
  )
}

function makeTickets(): Ticket[] {
  const plan = [
    { month: 6, customers: 25, firstDay: 6 },
    { month: 7, customers: 42, firstDay: 1 },
    { month: 8, customers: 38, firstDay: 1 },
  ]
  let sequence = 0
  return plan.flatMap(({ month, customers, firstDay }) => {
    const units = monthlyUnits(month)
    const tickets: Ticket[] = Array.from({ length: customers }, (_, i) => {
      const daysInMonth = new Date(2026, month + 1, 0).getDate()
      const day = Math.min(
        daysInMonth,
        firstDay + Math.floor((i * (daysInMonth - firstDay)) / customers),
      )
      sequence += 1
      return {
        id: `V-${String(sequence).padStart(3, '0')}`,
        date: new Date(2026, month, day, 9 + ((i * 3) % 9), (i * 17) % 60),
        payment: paymentMethods[(i + month) % paymentMethods.length],
        lines: [],
        total: 0,
      }
    })
    units.forEach((unit, index) => {
      const firstSellDay =
        unit.arrival === 'BAL-001' && month === 6
          ? 18
          : unit.arrival === 'IND-002' && month === 7
            ? 15
            : firstDay
      const eligibleTickets = tickets.filter((ticket) => ticket.date.getDate() >= firstSellDay)
      const ticket = eligibleTickets[index % eligibleTickets.length]
      const same = ticket.lines.find(
        (line) => line.name === unit.name && line.arrival === unit.arrival,
      )
      if (same) same.quantity += 1
      else ticket.lines.push({ ...unit, quantity: 1 })
    })
    tickets.forEach((ticket) => {
      ticket.total = ticket.lines.reduce((sum, line) => sum + line.sold * line.quantity, 0)
    })
    return tickets
  })
}

export const tickets = makeTickets()

export const arrivals = [
  {
    code: 'CHN-001',
    kind: 'supplier_order' as const,
    origin: 'Chine',
    supplier: 'Fournisseur de Canton (Chine)',
    received: 'reçu le 5 juillet',
    items: 65,
    sold: 62,
    remaining: 3,
    cost: 620000,
    revenue: 1004000,
  },
  {
    code: 'BAL-001',
    kind: 'balloon' as const,
    origin: 'Acheté à Brazzaville',
    supplier: 'Ballon de friperie',
    received: 'ouvert le 18 juillet',
    items: 50,
    sold: 46,
    remaining: 4,
    cost: 250000,
    revenue: 630000,
  },
  {
    code: 'IND-002',
    kind: 'supplier_order' as const,
    origin: 'Inde',
    supplier: 'Fournisseur de Delhi (Inde)',
    received: 'reçu le 15 août',
    items: 40,
    sold: 35,
    remaining: 5,
    cost: 360000,
    revenue: 700000,
  },
]

export const months = [
  {
    name: 'Juillet',
    buyers: 25,
    units: 35,
    sales: 494000,
    arrivals: 870000,
    expenses: 110000,
    stock: 50,
  },
  {
    name: 'Août',
    buyers: 42,
    units: 59,
    sales: 986000,
    arrivals: 360000,
    expenses: 130000,
    stock: 53,
  },
  {
    name: 'Septembre',
    buyers: 38,
    units: 49,
    sales: 854000,
    arrivals: 0,
    expenses: 140000,
    stock: 12,
  },
]

/** Remaining stock on 30 September: article, arrival, pieces left, displayed price, unique piece. */
export const remainingStock: Array<[string, string, number, number, boolean]> = [
  ['Ensemble brodé modèle D', 'IND-002', 5, 20000, false],
  ['Chemise lin modèle C', 'CHN-001', 2, 12000, false],
  ['Jean droit modèle B', 'CHN-001', 1, 22000, false],
  ['Veste en jean', 'BAL-001', 1, 15000, true],
  ['Robe pagne', 'BAL-001', 1, 15000, true],
  ['Chemise à carreaux', 'BAL-001', 1, 15000, true],
  ['Pantalon cargo', 'BAL-001', 1, 15000, true],
]

/** Monthly shop expenses: month, rent, other expenses, total. */
export const monthlyExpenses: Array<[string, number, number, number]> = [
  ['Juillet', 70000, 40000, 110000],
  ['Août', 70000, 60000, 130000],
  ['Septembre', 70000, 70000, 140000],
]
