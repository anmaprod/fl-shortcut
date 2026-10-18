import { loadConfig } from '../src/config.js';
import { createApp } from '../src/app.js';
import { openDatabase } from '../src/db.js';

export const VALID_SIRET = '44306184100047';
export const silentLog = { info() {}, warn() {}, error() {} };

// Application complète sur un port libre, base en mémoire, notifications et Stripe simulés.
export async function startTestApp({ env = {}, stripeResponses = {}, withStripe = true } = {}) {
  const config = loadConfig({
    PROMO_CODES_GRATUITS: 'NOTRE-BOITE',
    STRIPE_WEBHOOK_SECRET: 'whsec_test',
    SIGNUPS_PER_HOUR: '1000',
    ...env
  });
  const db = openDatabase(':memory:');
  const pushes = [];
  const push = { publicKey: 'cle-publique', send: async (subs, payload) => pushes.push({ subs, payload }) };
  const stripeCalls = [];
  const stripe = {
    createCheckoutSession: async (p) => (stripeCalls.push(['checkout', p]), { url: 'https://checkout.stripe.test/s' }),
    retrieveCheckoutSession: async (id) => (stripeCalls.push(['retrieve', id]), stripeResponses.retrieve(id)),
    createPortalSession: async (p) => (stripeCalls.push(['portal', p]), { url: 'https://billing.stripe.test/p' })
  };
  let now = Date.UTC(2026, 9, 18, 12, 0, 0);
  const clock = () => now;
  const app = createApp({ config, db, push, stripe: withStripe ? stripe : null, clock, log: silentLog });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${app.server.address().port}`;

  async function request(method, path, body, { cookie, headers = {} } = {}) {
    const res = await fetch(base + path, {
      method,
      headers: {
        ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
        ...(cookie ? { Cookie: cookie } : {}),
        ...headers
      },
      body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body)
    });
    const text = await res.text();
    let json = null;
    try {
      json = JSON.parse(text);
    } catch {}
    const setCookie = res.headers.get('set-cookie');
    return { status: res.status, json, text, headers: res.headers, cookie: setCookie?.split(';')[0] };
  }

  async function signup(email = 'bar@example.fr', extra = {}) {
    const res = await request('POST', '/api/signup', {
      email,
      password: 'motdepasse',
      name: 'Le Comptoir',
      siret: VALID_SIRET,
      ...extra
    });
    return { ...res, cookie: res.cookie };
  }

  return {
    base,
    app,
    db,
    config,
    pushes,
    stripeCalls,
    request,
    signup,
    advance: (ms) => (now += ms),
    now: () => now,
    close: async () => {
      await app.close();
      db.close();
    }
  };
}

// Lit un flux SSE et rend les événements au fur et à mesure.
export async function openEvents(url, cookie) {
  const controller = new AbortController();
  const res = await fetch(url, { headers: cookie ? { Cookie: cookie } : {}, signal: controller.signal });
  const events = [];
  const waiters = [];
  let ended = false;
  if (res.ok) {
    (async () => {
      const decoder = new TextDecoder();
      let buffer = '';
      try {
        for await (const chunk of res.body) {
          buffer += decoder.decode(chunk, { stream: true });
          let i;
          while ((i = buffer.indexOf('\n\n')) >= 0) {
            const block = buffer.slice(0, i);
            buffer = buffer.slice(i + 2);
            const event = /^event: (.*)$/m.exec(block)?.[1];
            const data = /^data: (.*)$/m.exec(block)?.[1];
            if (event) events.push({ event, data: JSON.parse(data) });
            for (const w of waiters.splice(0)) w();
          }
        }
      } catch {}
      ended = true;
      for (const w of waiters.splice(0)) w();
    })();
  }
  return {
    status: res.status,
    events,
    get ended() {
      return ended;
    },
    async next(name, timeout = 2000) {
      const start = Date.now();
      for (;;) {
        const idx = events.findIndex((e) => e.event === name);
        if (idx >= 0) return events.splice(idx, 1)[0].data;
        if (ended) throw new Error(`flux terminé sans « ${name} »`);
        if (Date.now() - start > timeout) throw new Error(`« ${name} » jamais reçu`);
        await new Promise((resolve) => {
          waiters.push(resolve);
          setTimeout(resolve, 50);
        });
      }
    },
    async waitEnd(timeout = 2000) {
      const start = Date.now();
      while (!ended) {
        if (Date.now() - start > timeout) throw new Error('flux toujours ouvert');
        await new Promise((r) => setTimeout(r, 20));
      }
    },
    close: () => controller.abort()
  };
}
