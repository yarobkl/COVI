import { useId, useState } from 'react'
import type { ComponentType } from 'react'
import {
  BarsIcon,
  BillIcon,
  BoxIcon,
  ChevronLeftIcon,
  HangerIcon,
  HomeIcon,
  MenuIcon,
  NotebookIcon,
  type IconProps,
} from '../../components/icons'
import { Button, Dialog, LabelCard, PageHead } from '../../components/ui'
import { DemoArrivals } from './DemoArrivals'
import { DemoDashboard } from './DemoDashboard'
import { DemoExpenses } from './DemoExpenses'
import { DemoHistory } from './DemoHistory'
import { DemoStatistics } from './DemoStatistics'
import { DemoStock } from './DemoStock'

type DemoPage = 'Accueil' | 'Ventes' | 'Stock' | 'Arrivages' | 'Bilan' | 'Charges'

const nav: readonly (readonly [DemoPage, ComponentType<IconProps>, string])[] = [
  ['Accueil', HomeIcon, 'Trois mois de la boutique Élégance Brazzaville.'],
  ['Ventes', NotebookIcon, 'Chaque article vendu pendant la simulation.'],
  ['Stock', HangerIcon, 'Ce qu’il reste en rayon au 30 septembre.'],
  ['Arrivages', BoxIcon, 'Ce que chaque arrivage a coûté et rapporté.'],
  ['Bilan', BarsIcon, 'Les chiffres clés des trois mois.'],
  ['Charges', BillIcon, 'Loyer et autres charges, mois par mois.'],
]
const bottom: readonly DemoPage[] = ['Accueil', 'Ventes', 'Stock', 'Arrivages']

/**
 * Three-month store simulation with fictitious data, available without an account. Same shell
 * and same notebook as the real application; nothing is read from or written to the shop.
 */
export function DemoMode({ onExit }: { onExit: () => void }) {
  const [page, setPage] = useState<DemoPage>('Accueil')
  const [menuOpen, setMenuOpen] = useState(false)
  const [query, setQuery] = useState('')
  const [selectedArrival, setSelectedArrival] = useState<string | null>(null)
  const menuTitle = useId()
  const go = (next: DemoPage) => {
    setPage(next)
    setMenuOpen(false)
    window.scrollTo(0, 0)
  }
  const content =
    page === 'Ventes' ? (
      <DemoHistory query={query} onQueryChange={setQuery} />
    ) : page === 'Stock' ? (
      <DemoStock />
    ) : page === 'Arrivages' ? (
      <DemoArrivals selectedArrival={selectedArrival} onSelectArrival={setSelectedArrival} />
    ) : page === 'Bilan' ? (
      <DemoStatistics />
    ) : page === 'Charges' ? (
      <DemoExpenses />
    ) : (
      <DemoDashboard
        onOpenArrival={(code) => {
          go('Arrivages')
          setSelectedArrival(code)
        }}
      />
    )
  const label = (
    <LabelCard className="shop-label">
      <p className="sommaire__shop-kicker">Boutique d’exemple</p>
      <p className="sommaire__shop-name">Élégance Brazzaville</p>
      <p className="sommaire__shop-place">Brazzaville · XAF</p>
    </LabelCard>
  )
  const links = (
    <ul className="sommaire__list">
      {nav.map(([name, Icon]) => (
        <li key={name}>
          <button
            type="button"
            className="sommaire__link"
            aria-current={page === name ? 'page' : undefined}
            onClick={() => go(name)}
          >
            <Icon />
            <span>{name}</span>
          </button>
        </li>
      ))}
    </ul>
  )
  const description = nav.find(([name]) => name === page)?.[2]

  return (
    <div className="shell demo-shell">
      <header className="topbar">
        <p className="topbar__shop">Élégance Brazzaville · exemple</p>
        <Button variant="ghost" icon={<ChevronLeftIcon />} onClick={onExit}>
          Quitter
        </Button>
      </header>

      <nav className="sommaire" aria-label="Sommaire de l’exemple">
        {label}
        <h2 className="sommaire__title">Sommaire</h2>
        {links}
        <div className="sommaire__foot">
          <button type="button" className="btn btn--ghost sommaire__quiet" onClick={onExit}>
            Quitter l’exemple
          </button>
        </div>
      </nav>

      <main className="shell__page seyes margin-rule" id="contenu">
        <div className="page page-stack" key={page}>
          <p className="demo-band" role="note">
            <b>Simulation</b> · données fictives du 1er juillet au 30 septembre 2026. Rien n’est
            enregistré dans votre boutique.
          </p>
          <PageHead title={page} sub={description} />
          {content}
        </div>
      </main>

      <nav className="bottom-nav" aria-label="Navigation de l’exemple">
        {bottom.map((name) => {
          const Icon = nav.find(([n]) => n === name)![1]
          return (
            <button
              key={name}
              type="button"
              className="bottom-nav__item"
              aria-current={page === name ? 'page' : undefined}
              onClick={() => go(name)}
            >
              <Icon />
              {name}
            </button>
          )
        })}
        <button
          type="button"
          className="bottom-nav__item"
          aria-haspopup="dialog"
          aria-expanded={menuOpen}
          aria-current={!bottom.includes(page) ? 'page' : undefined}
          onClick={() => setMenuOpen(true)}
        >
          <MenuIcon />
          Plus
        </button>
      </nav>

      <Dialog open={menuOpen} onClose={() => setMenuOpen(false)} labelledBy={menuTitle} sheet>
        <div className="dialog__body menu-sheet">
          <h2 className="visually-hidden" id={menuTitle}>
            Menu de l’exemple
          </h2>
          {label}
          {links}
          <div className="menu-sheet__foot">
            <Button variant="secondary" onClick={onExit}>
              Quitter l’exemple
            </Button>
          </div>
        </div>
      </Dialog>
    </div>
  )
}
