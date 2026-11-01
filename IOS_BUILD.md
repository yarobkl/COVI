# Build iOS de COVI

COVI est maintenant encapsulé avec Capacitor (`com.yaroconsulting.covi`).

## Prévisualisation simulateur

Le workflow `ios-simulator` construit une application iOS non signée pour un simulateur. Il ne nécessite pas de compte Apple Developer et peut être envoyé vers un outil de prévisualisation compatible.

## IPA signée

Le workflow `ios-app-store` construit une IPA signée depuis un runner macOS cloud. Dans Codemagic, il faut connecter App Store Connect, créer le groupe d’environnement `app_store_connect`, puis sélectionner les certificats et profils pour `com.yaroconsulting.covi`.

La signature et la distribution TestFlight/App Store nécessitent l’adhésion Apple Developer ; Xcode installé localement n’est pas nécessaire avec le build cloud.
