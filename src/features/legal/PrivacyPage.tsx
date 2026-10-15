import type { ReactNode } from 'react'
import { GuestSheet } from '../orders/GuestSheet'

/** Éditeur et contact affichés publiquement (choisis par le propriétaire de COVI). */
const privacyContact = { editor: 'Elie Bakala', email: 'eliebakala@gmail.com' }
const updatedOn = '15 octobre 2026'

function Part({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="privacy__part">
      <h2 className="section-title">{title}</h2>
      {children}
    </section>
  )
}

/**
 * Politique de confidentialité (exigée par l'App Store et le Play Store) : page publique, lisible
 * sans compte, à l'adresse #/confidentialite.
 */
export function PrivacyPage() {
  const mail = `mailto:${privacyContact.email}`
  return (
    <GuestSheet>
      <article className="privacy">
        <h1 className="page-title">Politique de confidentialité</h1>
        <p className="muted">Mise à jour le {updatedOn}.</p>
        <p>
          COVI est un cahier de caisse en ligne pour les boutiques : ventes, stock, arrivages,
          charges et commandes des clients. Cette page dit quelles données COVI enregistre,
          pourquoi, où elles sont gardées et comment les faire effacer.
        </p>

        <Part title="Qui est responsable">
          <p>
            COVI est édité par <b>{privacyContact.editor}</b>. Pour toute question sur vos données :{' '}
            <a href={mail}>{privacyContact.email}</a>.
          </p>
        </Part>

        <Part title="Ce que COVI enregistre">
          <ul>
            <li>
              <b>Votre compte</b> : adresse e-mail, mot de passe (jamais lisible, même par COVI),
              nom et photo de profil si vous en ajoutez une. Si vous vous connectez avec Google,
              Facebook ou Apple, COVI reçoit seulement votre e-mail et votre nom.
            </li>
            <li>
              <b>Votre boutique</b> : nom, pays, ville, quartier et, seulement si vous la demandez,
              sa position GPS.
            </li>
            <li>
              <b>Votre gestion</b> : produits et leurs photos, stock et corrections de stock,
              arrivages, ventes, charges, prénoms des caissiers et leurs codes PIN (gardés sous
              forme chiffrée, jamais lisibles), journal des actions de la boutique.
            </li>
            <li>
              <b>Les commandes de vos clients</b> (QR code, WhatsApp, TikTok) : nom, téléphone,
              adresse de livraison si besoin, message et photo de référence envoyés par le client.
            </li>
          </ul>
          <p>
            COVI n’encaisse pas d’argent : les règlements (espèces, Mobile Money, carte, virement)
            se font entre la boutique et ses clients.
          </p>
        </Part>

        <Part title="Pourquoi">
          <p>
            Uniquement pour faire fonctionner votre boutique : enregistrer les ventes, tenir le
            stock, calculer vos chiffres, recevoir et suivre les commandes, et protéger le compte
            (codes PIN, journal).{' '}
            <b>Pas de publicité, pas de revente de données, pas de pistage.</b>
          </p>
        </Part>

        <Part title="Où sont gardées les données">
          <ul>
            <li>
              Base de données et photos : <b>Supabase</b>, serveurs situés à Paris (Union
              européenne), accès chiffré.
            </li>
            <li>
              Site et application : servis par <b>Vercel</b>.
            </li>
            <li>
              Formulaire de commande : protégé contre les robots par <b>Cloudflare Turnstile</b>.
            </li>
            <li>
              Sur votre téléphone : une copie du stock et les ventes pas encore envoyées, pour
              continuer à vendre sans réseau.
            </li>
          </ul>
          <p>Ces prestataires ne traitent les données que pour le compte de COVI.</p>
        </Part>

        <Part title="Qui peut les voir">
          <p>
            Le propriétaire de la boutique voit tout. Un caissier voit seulement ce que le
            propriétaire lui autorise. Un client voit seulement le suivi de sa propre commande.
            Aucune autre boutique ne peut lire vos données.
          </p>
        </Part>

        <Part title="Durée et suppression">
          <p>
            Vos données sont gardées tant que votre compte existe. Vous pouvez supprimer votre
            compte à tout moment dans l’application : <b>Ma boutique → Supprimer mon compte</b>. La
            boutique ferme tout de suite aux commandes en ligne ; 30 jours plus tard, le compte, la
            boutique, toutes ses données et ses photos sont effacés définitivement. Pendant ces 30
            jours, vous pouvez annuler en vous reconnectant.
          </p>
          <p>
            Un client d’une boutique peut demander l’effacement de sa commande à la boutique, ou
            écrire à <a href={mail}>{privacyContact.email}</a>.
          </p>
        </Part>

        <Part title="Vos droits">
          <p>
            Vous pouvez demander à consulter, corriger ou effacer vos données, et poser toute
            question, en écrivant à <a href={mail}>{privacyContact.email}</a>. Réponse sous 30
            jours.
          </p>
        </Part>

        <p className="privacy__back">
          <a href="#/">← Revenir à COVI</a>
        </p>
      </article>
    </GuestSheet>
  )
}
