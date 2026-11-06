# Site FL Shortcuts (Cloudflare + SumUp)

Ce dossier contient le site public : la page (`public/index.html`) et un petit serveur (`src/worker.js`) qui prépare le paiement chez SumUp. Il est hébergé gratuitement sur **Cloudflare Workers**.

Le dossier `site/` reste l'ancienne page de téléchargement (GitHub Pages) tant que ce site n'est pas en ligne.

## Le parcours d'achat

1. On choisit son prix (prix libre, de 0 à 999 €) et son système (Mac ou Windows).
2. La fenêtre « obtenir l'app » montre l'article (FL Shortcuts, système, prix), puis demande **le mail**, pour tout le monde.
3. **0 €** : « Télécharger gratuitement » affiche le téléchargement tout de suite, et le lien part aussi par mail.
4. **1 € ou plus** : on coche la case de renonciation au droit de rétractation (obligatoire pour un produit numérique livré tout de suite), puis « Payer X € sur SumUp » envoie sur la **page de paiement de SumUp** (`checkout.sumup.com` : carte, Apple Pay, Google Pay). Le numéro de carte ne passe jamais par le site. La page SumUp reste ouverte 30 minutes.
5. Après le paiement, le bouton de retour de la page SumUp ramène sur le site. Le serveur demande à SumUp si le paiement est bien reçu, puis la fenêtre « merci » donne le téléchargement et le mode d'emploi du bon système, et le lien part par mail.

Le mail ne sert qu'à envoyer le lien : il n'est enregistré nulle part sur le site. Tant que Brevo n'est pas branché, rien ne part et la fenêtre « merci » ne parle pas de mail. Au plus 3 envois par minute pour une même connexion et une même adresse.

Tant que SumUp n'est pas branché, le site marche en **gratuit seulement** : le bouton « Payer » propose de télécharger gratuitement.

Les fichiers à télécharger restent sur la page des versions GitHub (`releases/latest`).

## Mettre le site en ligne (une seule fois)

1. Crée un compte sur [dash.cloudflare.com](https://dash.cloudflare.com).
2. **Workers & Pages › Create › Import a repository**, choisis `anmaprod/fl-shortcut`, puis :
   - *Root directory* : `web`
   - *Production branch* : `main`
   - laisse la commande de déploiement par défaut (`npx wrangler deploy`).
3. **Nom de domaine** : *Domain Registration* pour l'acheter, puis dans le Worker `fl-shortcuts` : *Settings › Domains & Routes › Add › Custom domain*.

Ensuite, chaque modification fusionnée dans `main` met le site à jour toute seule.

## Brancher SumUp

1. Sur ton compte SumUp, partie développeurs (*Settings › For developers*) :
   - crée une **clé API** (elle commence par `sup_sk_`) ;
   - note ton **code marchand** (un code du genre `MH4H92C7`) ;
   - pour tester sans vrai argent, crée un **compte sandbox** et utilise sa clé et son code. En sandbox, un paiement de 11 € échoue toujours, pour tester les refus.
2. Dans Cloudflare, Worker `fl-shortcuts`, *Settings › Variables and Secrets* :

   | Nom | Type | Valeur |
   |---|---|---|
   | `SUMUP_API_KEY` | **Secret** | ta clé API |
   | `SUMUP_MERCHANT_CODE` | Text | ton code marchand |

   La clé API ne va **jamais** dans le code, dans le dépôt ou dans une conversation.
3. **Ce que voit l'acheteur sur la page SumUp** : dans le tableau de bord SumUp, page *Branding*, ajoute le logo (`public/img/icone.png`) ; page *Business profile*, mets le nom « FL Shortcuts ». C'est ce qui rassure l'acheteur sur la page de paiement.
4. **PayPal** : la documentation de SumUp ne dit pas si sa page de paiement le propose. À demander au service client SumUp.

## Envoyer le lien par mail (Brevo)

1. Crée un compte sur [brevo.com](https://www.brevo.com) (société française, plan gratuit : 300 mails par jour).
2. *Senders, Domains & Dedicated IPs › Domains* : ajoute ton nom de domaine et suis les étapes. Brevo donne des lignes à ajouter dans les réglages DNS du domaine (chez Cloudflare : *DNS › Records*). Sans ça, les mails finissent en indésirables.
3. *SMTP & API › API keys* : crée une clé (elle commence par `xkeysib-`).
4. Dans Cloudflare, Worker `fl-shortcuts`, *Settings › Variables and Secrets* :

   | Nom | Type | Valeur |
   |---|---|---|
   | `BREVO_API_KEY` | **Secret** | ta clé Brevo |
   | `MAIL_EXPEDITEUR` | Text | l'adresse d'envoi sur ton domaine, par exemple `bonjour@ton-domaine.fr` |

Fais d'abord tous les essais avec les réglages sandbox, puis remplace-les par la vraie clé et le vrai code marchand.

## Avant d'encaisser pour de vrai

- Pages **mentions légales**, **conditions de vente** et **confidentialité**, liées en bas du site. La page confidentialité dit que le mail sert seulement à envoyer le lien, et qu'il passe par Brevo et SumUp.
- Reçus SumUp avec « EI », ton SIRET et « TVA non applicable, art. 293 B du CGI ».

## Tests

```bash
npm test
```

Les tests simulent SumUp : aucun réseau, aucune clé.
