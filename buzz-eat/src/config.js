import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// Codes promo « abonnement offert » : jamais écrits dans le dépôt (il est public), seulement dans l'environnement.
export function normalizeCode(code) {
  return String(code || '').toUpperCase().replace(/\s+/g, '');
}

export function loadConfig(env = process.env) {
  return {
    root,
    port: Number(env.PORT) || 3000,
    host: env.HOST || '0.0.0.0',
    publicUrl: (env.PUBLIC_URL || '').trim().replace(/\/+$/, ''),
    dataDir: env.DATA_DIR || path.join(root, 'data'),
    production: env.NODE_ENV === 'production',
    trustProxy: env.TRUST_PROXY === '1' || env.TRUST_PROXY === 'true',
    appName: env.APP_NAME || 'Buzz Eat',
    priceCents: 500,
    currency: 'eur',
    freePromoCodes: String(env.PROMO_CODES_GRATUITS || '')
      .split(',')
      .map(normalizeCode)
      .filter(Boolean),
    stripeSecretKey: env.STRIPE_SECRET_KEY || '',
    stripeWebhookSecret: env.STRIPE_WEBHOOK_SECRET || '',
    stripePriceId: env.STRIPE_PRICE_ID || '',
    vapidSubject: env.VAPID_SUBJECT || 'mailto:contact@example.com',
    vapidPublicKey: env.VAPID_PUBLIC_KEY || '',
    vapidPrivateKey: env.VAPID_PRIVATE_KEY || '',
    signupsPerHour: Number(env.SIGNUPS_PER_HOUR) || 10,
    // Une commande jamais récupérée s'efface d'elle-même au bout de ce délai.
    orderMaxAgeMs: 12 * 60 * 60 * 1000,
    sessionMaxAgeMs: 30 * 24 * 60 * 60 * 1000
  };
}
