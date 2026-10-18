import { normalizeCode } from './config.js';
import { HttpError } from './http.js';
import { safeEqual } from './security.js';

// « past_due » : Stripe retente le prélèvement ; l'établissement continue de travailler pendant ce temps.
const ACTIVE_STATUSES = new Set(['active', 'trialing', 'past_due']);

export function isSubscribed(r) {
  return ACTIVE_STATUSES.has(r.sub_status);
}

export function subscriptionView(r, { priceCents, onlinePayment }) {
  return {
    active: isSubscribed(r),
    plan: r.plan,
    status: r.sub_status,
    periodEnd: r.period_end,
    priceCents: r.plan === 'promo' ? 0 : priceCents,
    listPriceCents: priceCents,
    onlinePayment,
    canManage: Boolean(onlinePayment && r.plan === 'stripe' && r.stripe_customer_id)
  };
}

function periodEndOf(sub) {
  const seconds = sub.current_period_end ?? sub.items?.data?.[0]?.current_period_end;
  return seconds ? seconds * 1000 : null;
}

function idOf(value) {
  return typeof value === 'string' ? value : value?.id;
}

export function createBilling({ config, db, stripe, limiter, log = console }) {
  function requireStripe() {
    if (!stripe) throw new HttpError(503, 'Le paiement en ligne n’est pas encore configuré sur ce serveur.');
    return stripe;
  }

  function applySubscription(r, sub, customerId) {
    db.updateRestaurant(r.id, {
      plan: 'stripe',
      sub_status: sub.status,
      period_end: periodEndOf(sub),
      stripe_customer_id: customerId || idOf(sub.customer) || r.stripe_customer_id,
      stripe_subscription_id: sub.id,
      promo_code: null
    });
  }

  function onSubscriptionEvent(sub) {
    const r =
      db.restaurantBySubscription(sub.id) ||
      (sub.metadata?.restaurant_id && db.restaurant(sub.metadata.restaurant_id)) ||
      db.restaurantByCustomer(idOf(sub.customer));
    if (!r || r.plan === 'promo') return;
    // Un ancien abonnement qui se termine ne doit pas couper le nouveau.
    if (r.stripe_subscription_id && r.stripe_subscription_id !== sub.id && !ACTIVE_STATUSES.has(sub.status)) return;
    applySubscription(r, sub);
  }

  function onCheckoutCompleted(session) {
    if (session.mode !== 'subscription') return;
    const r = db.restaurant(session.client_reference_id || session.metadata?.restaurant_id);
    if (!r || r.plan === 'promo') return;
    const sub = typeof session.subscription === 'object' ? session.subscription : null;
    if (sub) return applySubscription(r, sub, idOf(session.customer));
    const paid = session.payment_status === 'paid' || session.payment_status === 'no_payment_required';
    db.updateRestaurant(r.id, {
      plan: 'stripe',
      sub_status: paid ? 'active' : r.sub_status,
      stripe_customer_id: idOf(session.customer),
      stripe_subscription_id: idOf(session.subscription),
      promo_code: null
    });
  }

  return {
    applyPromo(r, code, limiterKey) {
      if (!limiter.allow(`promo:${limiterKey}`, 8, 15 * 60 * 1000)) {
        throw new HttpError(429, 'Trop d’essais. Réessayez dans quelques minutes.');
      }
      const wanted = normalizeCode(code);
      if (!wanted || wanted.length > 64) throw new HttpError(400, 'Saisissez un code promo.');
      let match = null;
      for (const c of config.freePromoCodes) if (safeEqual(c, wanted)) match = c;
      if (!match) throw new HttpError(400, 'Ce code promo n’existe pas.');
      if (r.plan === 'stripe' && isSubscribed(r)) {
        throw new HttpError(
          409,
          'Un abonnement payant est en cours : résiliez-le dans « Gérer mon abonnement », puis appliquez le code.'
        );
      }
      db.updateRestaurant(r.id, { plan: 'promo', sub_status: 'active', period_end: null, promo_code: match });
    },

    async checkout(r, baseUrl) {
      const s = requireStripe();
      if (isSubscribed(r)) throw new HttpError(409, 'L’abonnement est déjà actif.');
      const lineItem = config.stripePriceId
        ? { price: config.stripePriceId, quantity: 1 }
        : {
            quantity: 1,
            price_data: {
              currency: config.currency,
              unit_amount: config.priceCents,
              recurring: { interval: 'month' },
              product_data: { name: `Abonnement ${config.appName}` }
            }
          };
      const session = await s.createCheckoutSession({
        mode: 'subscription',
        locale: 'fr',
        client_reference_id: r.id,
        ...(r.stripe_customer_id ? { customer: r.stripe_customer_id } : { customer_email: r.email }),
        line_items: [lineItem],
        metadata: { restaurant_id: r.id },
        subscription_data: { metadata: { restaurant_id: r.id } },
        success_url: `${baseUrl}/reglages?abonnement=ok&session_id={CHECKOUT_SESSION_ID}#abonnement`,
        cancel_url: `${baseUrl}/reglages?abonnement=annule#abonnement`
      });
      return session.url;
    },

    // Retour de la page de paiement : on lit la session sans attendre le webhook.
    async confirm(r, sessionId) {
      const s = requireStripe();
      if (typeof sessionId !== 'string' || !/^cs_[A-Za-z0-9_]{10,200}$/.test(sessionId)) {
        throw new HttpError(400, 'Session de paiement inconnue.');
      }
      const session = await s.retrieveCheckoutSession(sessionId);
      if (session.client_reference_id !== r.id) throw new HttpError(404, 'Session de paiement inconnue.');
      if (session.status === 'complete') onCheckoutCompleted(session);
    },

    async portal(r, baseUrl) {
      const s = requireStripe();
      if (!r.stripe_customer_id) throw new HttpError(409, 'Aucun abonnement payant à gérer.');
      const portal = await s.createPortalSession({
        customer: r.stripe_customer_id,
        return_url: `${baseUrl}/reglages#abonnement`
      });
      return portal.url;
    },

    handleEvent(event, now) {
      if (!db.claimStripeEvent(event.id, now)) return;
      const obj = event.data?.object;
      if (!obj) return;
      switch (event.type) {
        case 'checkout.session.completed':
          onCheckoutCompleted(obj);
          break;
        case 'customer.subscription.created':
        case 'customer.subscription.updated':
        case 'customer.subscription.deleted':
          onSubscriptionEvent(obj);
          break;
        default:
          log.info?.(`Événement Stripe ignoré : ${event.type}`);
      }
    }
  };
}
