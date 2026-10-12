import { useEffect, useId, useRef, useState, type ComponentType } from 'react'
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
import { Badge, Button, Dialog, LabelCard } from '../../components/ui'
import '../../styles/app/exemple.css'
import {
  DemoArrivals,
  DemoBilan,
  DemoCharges,
  DemoHome,
  DemoSales,
  DemoStock,
  type DemoPageId,
} from './DemoPages'

const pages: Record<DemoPageId, { label: string; icon: ComponentType<IconProps> }> = {
  accueil: { label: 'Accueil', icon: HomeIcon },
  ventes: { label: 'Ventes', icon: NotebookIcon },
  stock: { label: 'Stock', icon: HangerIcon },
  arrivages: { label: 'Arrivages', icon: BoxIcon },
  charges: { label: 'Charges', icon: BillIcon },
  bilan: { label: 'Bilan', icon: BarsIcon },
}
const order: DemoPageId[] = ['accueil', 'ventes', 'stock', 'arrivages', 'charges', 'bilan']
/** Phone bottom bar; Charges and Bilan are in « Plus ». */
const bottom: DemoPageId[] = ['accueil', 'ventes', 'stock', 'arrivages']
const more: DemoPageId[] = ['charges', 'bilan']

/** The example shop's label, like the real notebook label but marked « Boutique d’exemple ». */
function ExampleLabel() {
  return (
    <LabelCard className="shop-label">
      <p className="sommaire__shop-kicker">Boutique d’exemple</p>
      <p className="sommaire__shop-name">Chez Mama Grâce</p>
      <p className="sommaire__shop-place">Poto-Poto, Brazzaville</p>
      <p className="sommaire__shop-owner">
        Tenu par <span className="hand">Grâce M.</span>
      </p>
    </LabelCard>
  )
}

/**
 * The example shop: three made-up months at « Chez Mama Grâce », drawn with the same notebook as
 * the real application and clearly marked « Exemple ». Nothing is read from or written to the
 * account. `signedIn` says where leaving goes back to.
 */
export function DemoMode({ onExit, signedIn = false }: { onExit: () => void; signedIn?: boolean }) {
  const [page, setPage] = useState<DemoPageId>('accueil')
  const [menuOpen, setMenuOpen] = useState(false)
  const menuTitle = useId()
  const main = useRef<HTMLElement>(null)
  const first = useRef(true)
  const exitLabel = signedIn ? 'Revenir à ma boutique' : 'Fermer l’exemple'

  useEffect(() => {
    document.title = `${pages[page].label} · exemple · COVI`
    if (first.current) {
      first.current = false
      return
    }
    window.scrollTo(0, 0)
    main.current?.focus({ preventScroll: true })
  }, [page])

  const go = (next: DemoPageId) => {
    setMenuOpen(false)
    setPage(next)
  }
  const current = (id: DemoPageId) => (page === id ? 'page' : undefined)

  const content =
    page === 'ventes' ? (
      <DemoSales />
    ) : page === 'stock' ? (
      <DemoStock />
    ) : page === 'arrivages' ? (
      <DemoArrivals />
    ) : page === 'charges' ? (
      <DemoCharges />
    ) : page === 'bilan' ? (
      <DemoBilan />
    ) : (
      <DemoHome go={go} />
    )

  return (
    <div className="shell demo-shell">
      <a className="skip-link" href="#contenu-exemple">
        Aller au contenu
      </a>

      <header className="topbar">
        <p className="topbar__shop">Chez Mama Grâce</p>
        <Badge tone="action">Exemple</Badge>
      </header>

      <nav className="sommaire" aria-label="Sommaire de l’exemple">
        <ExampleLabel />
        <h2 className="sommaire__title">Sommaire</h2>
        <ul className="sommaire__list">
          {order.map((id) => {
            const Icon = pages[id].icon
            return (
              <li key={id}>
                <button
                  type="button"
                  className="sommaire__link"
                  aria-current={current(id)}
                  onClick={() => go(id)}
                >
                  <Icon />
                  <span>{pages[id].label}</span>
                </button>
              </li>
            )
          })}
        </ul>
        <div className="sommaire__foot">
          <Button variant="secondary" icon={<ChevronLeftIcon />} onClick={onExit}>
            {exitLabel}
          </Button>
        </div>
      </nav>

      <main className="shell__page seyes margin-rule" id="contenu-exemple" ref={main} tabIndex={-1}>
        <aside className="demo-banner" aria-label="Boutique d’exemple">
          <p className="demo-banner__stamp" aria-hidden="true">
            Exemple
          </p>
          <p className="demo-banner__text">
            <strong>Boutique d’exemple.</strong> Boutique fictive, de juillet à septembre 2026. Rien
            de ce que vous voyez ici ne touche votre boutique.
          </p>
          <Button variant="ghost" className="demo-banner__exit" onClick={onExit}>
            {exitLabel}
          </Button>
        </aside>
        <div key={page} className="page">
          {content}
        </div>
      </main>

      <nav className="bottom-nav" aria-label="Navigation de l’exemple">
        {bottom.map((id) => {
          const Icon = pages[id].icon
          return (
            <button
              key={id}
              type="button"
              className="bottom-nav__item"
              aria-current={current(id)}
              onClick={() => go(id)}
            >
              <Icon />
              {pages[id].label}
            </button>
          )
        })}
        <button
          type="button"
          className="bottom-nav__item"
          aria-haspopup="dialog"
          aria-expanded={menuOpen}
          aria-current={more.includes(page) ? 'page' : undefined}
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
          <ExampleLabel />
          <ul className="sommaire__list">
            {more.map((id) => {
              const Icon = pages[id].icon
              return (
                <li key={id}>
                  <button
                    type="button"
                    className="sommaire__link"
                    aria-current={current(id)}
                    onClick={() => go(id)}
                  >
                    <Icon />
                    <span>{pages[id].label}</span>
                  </button>
                </li>
              )
            })}
          </ul>
          <div className="menu-sheet__foot">
            <Button variant="secondary" icon={<ChevronLeftIcon />} onClick={onExit}>
              {exitLabel}
            </Button>
          </div>
        </div>
      </Dialog>
    </div>
  )
}
