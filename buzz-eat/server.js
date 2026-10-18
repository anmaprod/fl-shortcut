import path from 'node:path';
import { createApp } from './src/app.js';
import { loadConfig } from './src/config.js';
import { openDatabase } from './src/db.js';
import { createPushSender } from './src/push.js';
import { createStripe } from './src/stripe.js';

const config = loadConfig();
const db = openDatabase(path.join(config.dataDir, 'buzz-eat.db'));
const push = createPushSender({ config, db });
const stripe = config.stripeSecretKey ? createStripe({ secretKey: config.stripeSecretKey }) : null;
const app = createApp({ config, db, push, stripe });

app.server.listen(config.port, config.host, () => {
  console.log(`${config.appName} : http://localhost:${config.port}`);
  if (!config.publicUrl) console.log('PUBLIC_URL non défini : les QR codes utiliseront l’adresse ouverte dans le navigateur.');
  if (!stripe) console.log('STRIPE_SECRET_KEY non défini : paiement en ligne désactivé (les codes promo fonctionnent).');
  if (!config.freePromoCodes.length) console.log('PROMO_CODES_GRATUITS non défini : aucun code promo actif.');
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, async () => {
    await app.close();
    db.close();
    process.exit(0);
  });
}
