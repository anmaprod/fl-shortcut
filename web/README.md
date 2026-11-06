# Site FL Shortcuts (Cloudflare + SumUp)

Ce dossier contient le site public : la page (`public/index.html`) et un petit serveur (`src/worker.js`) qui prépare le paiement chez SumUp. Il est hébergé gratuitement sur **Cloudflare Workers**.

Le dossier `site/` reste l'ancienne page de téléchargement (GitHub Pages) tant que ce site n'est pas en ligne.

## Le parcours d'achat

1. On choisit son prix (prix libre, de 0 à 999 €) et son système (Mac ou Windows).
2. **0 €** : le téléchargement s'affiche tout de suite.
3. **1 € ou plus** : on coche la case de renonciation au droit de rétractation (obligatoire pour un produit numérique livré tout de suite), puis « Payer X € sur SumUp » envoie sur la **page de paiement de SumUp** (`checkout.sumup.com` : carte, Apple Pay, Google Pay). Le numéro de carte ne passe jamais par le site. La page SumUp reste ouverte 30 minutes.
4. Après le paiement, le bouton de retour de la page SumUp ramène sur le site. Le serveur demande à SumUp si le paiement est bien reçu, puis la fenêtre « merci » donne le téléchargement et le mode d'emploi du bon système.

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

Fais d'abord tous les essais avec les réglages sandbox, puis remplace-les par la vraie clé et le vrai code marchand.

## Avant d'encaisser pour de vrai

- Pages **mentions légales**, **conditions de vente** et **confidentialité**, liées en bas du site.
- Reçus SumUp avec « EI », ton SIRET et « TVA non applicable, art. 293 B du CGI ».

## Tests

```bash
npm test
```

Les tests simulent SumUp : aucun réseau, aucune clé.
