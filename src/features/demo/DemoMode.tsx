import { useState } from 'react'
import {
  ArrowLeft,
  ChartNoAxesCombined,
  History,
  Home,
  Package,
  ReceiptText,
  Ship,
  type LucideIcon,
} from 'lucide-react'
import { Brand } from '../../components/Brand'
import { DemoArrivals } from './DemoArrivals'
import { DemoDashboard } from './DemoDashboard'
import { DemoExpenses } from './DemoExpenses'
import { DemoHistory } from './DemoHistory'
import { DemoStatistics } from './DemoStatistics'
import { DemoStock } from './DemoStock'

type DemoPage =
  | 'Tableau de bord'
  | 'Produits vendus'
  | 'Mon stock'
  | 'Mes arrivages'
  | 'Statistiques'
  | 'Charges de la boutique'

const nav: readonly (readonly [DemoPage, LucideIcon])[] = [
  ['Tableau de bord', Home],
  ['Produits vendus', History],
  ['Mon stock', Package],
  ['Mes arrivages', Ship],
  ['Statistiques', ChartNoAxesCombined],
  ['Charges de la boutique', ReceiptText],
]

const bottomNav: readonly (readonly [string, LucideIcon, DemoPage])[] = [
  ['Accueil', Home, 'Tableau de bord'],
  ['Ventes', History, 'Produits vendus'],
  ['Stock', Package, 'Mon stock'],
  ['Arrivages', Ship, 'Mes arrivages'],
]

/** Three-month store simulation with fictitious data, available without an account. */
export function DemoMode({ onExit }: { onExit: () => void }) {
  const [page, setPage] = useState<DemoPage>('Tableau de bord')
  const [query, setQuery] = useState('')
  const [selectedArrival, setSelectedArrival] = useState<string | null>(null)
  const content =
    page === 'Produits vendus' ? (
      <DemoHistory query={query} onQueryChange={setQuery} />
    ) : page === 'Mon stock' ? (
      <DemoStock />
    ) : page === 'Mes arrivages' ? (
      <DemoArrivals selectedArrival={selectedArrival} onSelectArrival={setSelectedArrival} />
    ) : page === 'Statistiques' ? (
      <DemoStatistics />
    ) : page === 'Charges de la boutique' ? (
      <DemoExpenses />
    ) : (
      <DemoDashboard
        onOpenArrival={(code) => {
          setPage('Mes arrivages')
          setSelectedArrival(code)
        }}
      />
    )
  return (
    <div className="app demo-app">
      <aside>
        <Brand />
        <p className="tag">
          Le système d’exploitation
          <br />
          de votre commerce.
        </p>
        <nav>
          {nav.map(([name, Icon]) => (
            <button
              className={page === name ? 'active' : ''}
              key={name}
              onClick={() => setPage(name)}
            >
              <Icon />
              {name}
            </button>
          ))}
        </nav>
        <div className="shop">
          <span>BOUTIQUE DE SIMULATION</span>
          <b>Élégance Brazzaville</b>
          <small>Brazzaville · XAF</small>
        </div>
      </aside>
      <main>
        <div className="demo-banner">
          <b>SIMULATION</b>
          <span>
            Données fictives du 1er juillet au 30 septembre 2026. Rien n’est enregistré dans ta
            boutique.
          </span>
          <button onClick={onExit}>
            <ArrowLeft />
            Quitter
          </button>
        </div>
        <header>
          <div className="demo-top-label">{page} · données de simulation</div>
          <select
            className="demo-page-select"
            aria-label="Choisir une page de simulation"
            value={page}
            onChange={(e) => setPage(e.target.value as DemoPage)}
          >
            {nav.map(([name]) => (
              <option key={name} value={name}>
                {name}
              </option>
            ))}
          </select>
        </header>
        <div className="content">
          <div className="hello">
            <div>
              <h1>{page}</h1>
              <span>Scénario de gestion d’une boutique sur trois mois.</span>
            </div>
          </div>
          {content}
        </div>
      </main>
      <div className="bottom">
        {bottomNav.map(([name, Icon, target]) => (
          <button
            className={page === target ? 'active' : ''}
            key={name}
            onClick={() => setPage(target)}
          >
            <Icon />
            {name}
          </button>
        ))}
      </div>
    </div>
  )
}
