import { legal, legalMail } from '../../lib/legal'
import { GuestSheet } from '../orders/GuestSheet'
import { LegalNav, LegalPart } from './LegalNav'

/**
 * Conditions générales d'utilisation (CGU) : page publique, lisible sans compte, à l'adresse
 * #/conditions. Acceptées à la création du compte.
 */
export function TermsPage() {
  const mail = legalMail('Conditions d’utilisation COVI')
  return (
    <GuestSheet>
      <article className="legal">
        <h1 className="page-title">Conditions générales d’utilisation</h1>
        <p className="muted">Mise à jour le {legal.updatedOn}.</p>
        <p>
          Ces conditions règlent l’utilisation de COVI, le cahier de caisse en ligne des boutiques.
          En créant un compte, vous les acceptez, ainsi que la{' '}
          <a href="#/confidentialite">politique de confidentialité</a>.
        </p>

        <LegalPart title="1. Qui édite COVI">
          <p>
            COVI est édité par <b>{legal.editor}</b>. Contact : <a href={mail}>{legal.email}</a>.
          </p>
        </LegalPart>

        <LegalPart title="2. Ce que fait COVI">
          <p>
            COVI permet à une boutique d’enregistrer ses ventes, de tenir son stock, ses arrivages
            et ses charges, de gérer ses caissiers et de recevoir des commandes de ses clients par
            QR code, WhatsApp ou TikTok. COVI est un outil de gestion : ce n’est ni une banque, ni
            un moyen de paiement, ni un logiciel de comptabilité officielle.
          </p>
        </LegalPart>

        <LegalPart title="3. Votre compte">
          <ul>
            <li>Vous fournissez des informations exactes et gardez votre mot de passe secret.</li>
            <li>
              Le compte de la boutique peut être partagé avec vos employés : chaque caissier a son
              propre code PIN. Vous êtes responsable de ce qui est fait avec le compte et des
              personnes à qui vous en donnez l’accès.
            </li>
            <li>Prévenez-nous sans attendre si vous pensez que votre compte a été piraté.</li>
          </ul>
        </LegalPart>

        <LegalPart title="4. Votre boutique et vos données">
          <ul>
            <li>
              Les données que vous saisissez (produits, ventes, stock, charges, clients) vous
              appartiennent. COVI les garde et les traite seulement pour vous rendre le service,
              comme le décrit la politique de confidentialité.
            </li>
            <li>
              Vous restez seul responsable de votre activité : prix, ventes, factures, taxes et
              obligations légales de votre commerce. Les chiffres calculés par COVI (bilan,
              rentabilité) sont une aide au pilotage, à vérifier par vous.
            </li>
            <li>
              Quand vous recevez les commandes de vos clients, vous utilisez leurs coordonnées
              uniquement pour traiter leur commande.
            </li>
          </ul>
        </LegalPart>

        <LegalPart title="5. Commandes et paiements des clients">
          <p>
            COVI transmet les commandes des clients à la boutique, mais ne vend rien et n’encaisse
            pas d’argent. Le prix, la disponibilité, la livraison, le paiement (espèces, Mobile
            Money, carte, virement), les échanges et les remboursements se règlent directement entre
            la boutique et son client.
          </p>
        </LegalPart>

        <LegalPart title="6. Ce qui est interdit">
          <ul>
            <li>Utiliser COVI pour une activité illégale, frauduleuse ou trompeuse.</li>
            <li>
              Envoyer, par une commande ou ailleurs, des contenus injurieux, menaçants,
              discriminatoires, à caractère sexuel ou qui portent atteinte aux droits d’autrui.
            </li>
            <li>Tenter d’accéder aux données d’une autre boutique ou de perturber le service.</li>
          </ul>
          <p>
            Une boutique peut bloquer un client abusif et signaler un abus à COVI. COVI peut
            suspendre ou fermer un compte qui ne respecte pas ces règles, après avoir prévenu son
            titulaire sauf urgence.
          </p>
        </LegalPart>

        <LegalPart title="7. Disponibilité">
          <p>
            COVI fait de son mieux pour que le service soit disponible et que vos données soient
            protégées, et continue de fonctionner sans réseau pour les ventes. Le service peut
            toutefois être interrompu pour maintenance ou à cause d’un prestataire ou du réseau.
          </p>
        </LegalPart>

        <LegalPart title="8. Responsabilité">
          <p>
            COVI est fourni tel quel. Dans les limites permises par la loi, l’éditeur n’est pas
            responsable des pertes indirectes (manque à gagner, perte de clientèle) liées à
            l’utilisation du service, ni des transactions entre une boutique et ses clients.
          </p>
        </LegalPart>

        <LegalPart title="9. Prix">
          <p>
            Si une partie de COVI devient payante, son prix sera annoncé à l’avance et rien ne vous
            sera facturé sans votre accord.
          </p>
        </LegalPart>

        <LegalPart title="10. Fin de l’utilisation">
          <p>
            Vous pouvez arrêter à tout moment et supprimer votre compte dans l’application :{' '}
            <b>Ma boutique → Supprimer mon compte</b>. Le compte et toutes les données de la
            boutique sont effacés 30 jours plus tard ; vous pouvez annuler d’ici là.
          </p>
        </LegalPart>

        <LegalPart title="11. Modifications">
          <p>
            Ces conditions peuvent évoluer. En cas de changement important, vous serez prévenu dans
            l’application avant qu’il s’applique.
          </p>
        </LegalPart>

        <LegalPart title="12. Droit applicable et litiges">
          <p>
            Ces conditions sont soumises au droit de la République du Congo. En cas de désaccord,
            écrivez-nous d’abord : nous chercherons une solution à l’amiable. À défaut, les
            tribunaux de Brazzaville seront compétents.
          </p>
        </LegalPart>

        <LegalNav current="#/conditions" />
      </article>
    </GuestSheet>
  )
}
