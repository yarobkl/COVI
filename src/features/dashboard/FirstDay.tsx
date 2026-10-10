import { ButtonLink } from '../../components/ui'

/** A new shop with nothing in it yet: three steps to start, and the example shop. */
export function FirstDay({
  shopName,
  onSimulation,
}: {
  shopName: string
  onSimulation: () => void
}) {
  return (
    <section className="first-day" aria-labelledby="first-day">
      <h2 className="first-day__title" id="first-day">
        {shopName} est prête.
      </h2>
      <p className="first-day__lead">
        Pour commencer, mettez en boutique ce que vous avez à vendre.
      </p>
      <ol className="first-day__steps">
        <li>
          <span>Notez un arrivage : un ballon ou une commande.</span>
          <ButtonLink variant="secondary" href="#/arrivages">
            Nouvel arrivage
          </ButtonLink>
        </li>
        <li>
          <span>Mettez vos pièces en stock.</span>
          <ButtonLink variant="secondary" href="#/stock">
            Ajouter au stock
          </ButtonLink>
        </li>
        <li>
          <span>Faites votre première vente.</span>
          <ButtonLink variant="sale" href="#/vendre">
            Vendre
          </ButtonLink>
        </li>
      </ol>
      <button type="button" className="btn btn--ghost first-day__example" onClick={onSimulation}>
        Voir d’abord une boutique d’exemple
      </button>
    </section>
  )
}
