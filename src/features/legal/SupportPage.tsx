import { legal, legalMail } from '../../lib/legal'
import { GuestSheet } from '../orders/GuestSheet'
import { LegalNav, LegalPart } from './LegalNav'

/** Aide et contact : l'adresse de support exigée par l'App Store et le Play Store (#/aide). */
export function SupportPage() {
  return (
    <GuestSheet>
      <article className="legal">
        <h1 className="page-title">Aide et contact</h1>
        <p>
          Une question, un problème, une idée ? Écrivez à{' '}
          <a href={legalMail('Aide COVI')}>{legal.email}</a> en indiquant le nom de votre boutique.
          Réponse sous 48 heures ouvrées.
        </p>

        <LegalPart title="Questions fréquentes">
          <dl className="legal__faq">
            <dt>Je n’ai pas de réseau, puis-je vendre ?</dt>
            <dd>
              Oui. Les ventes sont gardées sur le téléphone et envoyées dès que le réseau revient.
              Ne vous déconnectez pas tant qu’il reste des ventes en attente.
            </dd>
            <dt>Comment ajouter un caissier ?</dt>
            <dd>
              Ma boutique → Caissiers (code PIN) : saisissez son prénom et son code. Il choisit
              ensuite son prénom et tape son code pour ouvrir la caisse.
            </dd>
            <dt>J’ai oublié le code du responsable.</dt>
            <dd>
              Déconnectez-vous puis reconnectez-vous avec le mot de passe du compte, et choisissez
              un nouveau code dans Ma boutique.
            </dd>
            <dt>Comment corriger mon stock ?</dt>
            <dd>
              Stock → touchez l’article → « Corriger le stock », avec un motif (réassort, perte,
              vol, erreur de comptage).
            </dd>
            <dt>Un client m’envoie des messages abusifs.</dt>
            <dd>
              Ouvrez sa commande → « Bloquer ou signaler ce client ». Il ne pourra plus vous envoyer
              de commande.
            </dd>
            <dt>Comment supprimer mon compte ?</dt>
            <dd>
              Ma boutique → Supprimer mon compte. Tout est effacé 30 jours plus tard ; vous pouvez
              annuler d’ici là en vous reconnectant.
            </dd>
          </dl>
        </LegalPart>

        <LegalNav current="#/aide" />
      </article>
    </GuestSheet>
  )
}
