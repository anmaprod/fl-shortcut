# Buzz Eat

Prise de commande au bar, et le **téléphone du client sonne quand sa commande est prête**.

1. Au bar, on note la commande et on la **valide** : un **QR code** s'affiche.
2. Le client le scanne avec l'appareil photo de son téléphone : une page web s'ouvre (rien à installer). Il touche **Activer l'alerte**.
3. Quand c'est prêt, le serveur clique sur **Venir retirer la commande** : chez le client, **alarme sonore, vibration, écran qui clignote** et notification.
4. Le client vient au bar, le serveur clique sur **Récupérée** : **tout s'efface** (la commande et l'abonnement aux notifications de son téléphone).

Une commande oubliée s'efface toute seule au bout de 12 heures.

Fonctionne sur **ordinateur, tablette et téléphone** (iPhone, Android, Windows, Mac), dans le navigateur. L'écran du bar peut s'installer comme une appli (« Ajouter à l'écran d'accueil »).

## Ce que l'établissement personnalise

Dans **Réglages** :

- **nom** et **SIRET** (vérifié : 14 chiffres et clé de contrôle ; affiché en bas de la page du client) ;
- **logo** (réduit à 512 px et réencodé dans le navigateur avant l'envoi) ;
- **palette de couleurs** parmi 10 : Océan, Bistrot, Forêt, Soleil, Ardoise, Framboise, Lavande, Lagon, Café, Nuit. Elle colore l'écran du bar et la page du client ;
- **aperçu** de la page du client, avec un bouton pour essayer l'alarme.

## Abonnement

- **5 € par mois** et par établissement, sans engagement, payé par carte via **Stripe**. Sans abonnement actif, on ne peut pas créer de commande (celles en cours se terminent normalement).
- **Code promo** pour votre entreprise : abonnement à **0 €**, sans carte. Les codes se règlent dans la variable `PROMO_CODES_GRATUITS` du serveur (plusieurs possibles, séparés par des virgules ; majuscules et espaces ignorés). **Ne les écrivez jamais dans le dépôt : il est public.** 8 essais par quart d'heure au plus.

Le prix (5 €, `priceCents: 500`) est dans `src/config.js` ; il est aussi écrit sur la page d'accueil (`public/index.html`).

## Lancer sur son ordinateur

Il faut **Node.js 22.13 ou plus récent**.

```sh
cd buzz-eat
npm install
PROMO_CODES_GRATUITS=MONCODE npm start
```

Puis ouvrir <http://localhost:3000>, créer un compte et saisir `MONCODE` dans *Réglages › Abonnement*.

Tests : `npm test` (inscription, abonnement et code promo, commande de bout en bout avec le temps réel, effacement, personnalisation, sécurité, webhooks Stripe).

## Mettre en ligne

**HTTPS est obligatoire** en ligne : sans lui, les téléphones refusent les notifications et le maintien de l'écran allumé.

N'importe quel hébergeur qui lance un conteneur Docker et garde un **disque persistant** convient (Render, Railway, Fly.io, un VPS…) :

```sh
docker build -t buzz-eat buzz-eat
docker run -p 3000:3000 -v buzz-eat-data:/data --env-file buzz-eat/.env buzz-eat
```

La base de données (un fichier SQLite) vit dans `/data` : ce dossier doit être sur le disque persistant, sinon tout est perdu au redémarrage. **Une seule instance** du serveur à la fois : le temps réel passe par la mémoire du serveur.

### Réglages du serveur

Voir `.env.example`.

| Variable | Rôle |
|---|---|
| `PUBLIC_URL` | Adresse publique en `https://…`, écrite dans les QR codes et les liens de paiement. |
| `TRUST_PROXY` | `1` quand l'hébergeur reçoit le HTTPS à votre place (le cas de Render, Railway, Fly.io). |
| `DATA_DIR` | Dossier de la base (`/data` dans Docker). |
| `PROMO_CODES_GRATUITS` | Codes promo « abonnement offert ». |
| `STRIPE_SECRET_KEY` | Clé secrète Stripe (`sk_live_…` ou `sk_test_…`). Sans elle, le paiement est désactivé (le code promo marche). |
| `STRIPE_WEBHOOK_SECRET` | Secret du webhook Stripe (`whsec_…`). |
| `STRIPE_PRICE_ID` | Facultatif : prix créé dans Stripe. Sinon, 5 €/mois est créé à la volée. |
| `VAPID_SUBJECT` | `mailto:` de contact donné aux services de notification. |
| `SIGNUPS_PER_HOUR` | Comptes créés par heure depuis une même connexion (10 par défaut). |

### Stripe (paiement des 5 €/mois)

1. Créez un compte sur <https://dashboard.stripe.com>, commencez en **mode test**.
2. *Développeurs › Clés API* : copiez la clé secrète dans `STRIPE_SECRET_KEY`.
3. *Développeurs › Webhooks › Ajouter un endpoint* : adresse `https://VOTRE-SITE/api/stripe/webhook`, événements `checkout.session.completed`, `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`. Copiez le secret de signature dans `STRIPE_WEBHOOK_SECRET`.
4. *Paramètres › Billing › Portail client* : enregistrez la configuration une fois (bouton « Gérer mon abonnement » : carte, factures, résiliation).
5. TVA : le montant envoyé est 5,00 €. Pour 5 € HT + TVA, activez Stripe Tax ou créez un prix dans Stripe et mettez son identifiant dans `STRIPE_PRICE_ID`.

## Ce qu'il faut savoir côté téléphone du client

- **Android** : sonnerie, vibration et notification. Si le client a accepté les notifications, il est prévenu **même écran verrouillé ou page fermée**.
- **iPhone** : sonnerie et clignotement, mais **pas de vibration** (Safari ne la permet pas aux pages web) et **pas de notification** sans installer la page sur l'écran d'accueil. La page doit donc **rester ouverte** : elle garde l'écran allumé tant qu'elle est devant, et le dit au client.
- Le son ne démarre qu'après un geste du client : c'est le rôle du bouton **Activer l'alerte**, qui fait aussi entendre un bip d'essai.
- L'écran du bar montre où en est chaque client : *QR code pas encore scanné*, *Page ouverte, alerte pas activée*, *Alerte activée*, *Téléphone du client déconnecté*. Le QR code se ferme tout seul une fois scanné.
- **Sonner à nouveau** relance l'alarme si le client tarde.

## Données et sécurité

- Le client ne donne rien : au plus un prénom noté par le serveur. Tout est effacé à la récupération, à l'annulation ou au bout de 12 h.
- Mots de passe chiffrés (scrypt), session dans un cookie `HttpOnly`, essais de connexion limités.
- Chaque commande a une adresse impossible à deviner (128 bits) ; un établissement ne voit que ses commandes.
- Pas de script tiers, politique de sécurité du contenu stricte, logo vérifié (PNG, JPEG ou WebP seulement).
- Les webhooks Stripe sont vérifiés par leur signature. Les notifications ne partent que vers les services des navigateurs (Google, Apple, Mozilla, Microsoft).

## Pas encore fait

- Mot de passe oublié (il faut un service d'envoi d'e-mails).
- Plusieurs comptes de serveurs par établissement (aujourd'hui : un compte par établissement, ouvert sur autant d'appareils que voulu).
- Suppression du compte par l'établissement lui-même.
