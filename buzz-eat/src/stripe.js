import crypto from 'node:crypto';

// Encode un objet à la manière de Stripe : a[b][0][c]=v.
export function encodeForm(value, prefix = '', out = new URLSearchParams()) {
  if (value === undefined || value === null) return out;
  if (Array.isArray(value)) {
    value.forEach((v, i) => encodeForm(v, `${prefix}[${i}]`, out));
  } else if (typeof value === 'object') {
    for (const [k, v] of Object.entries(value)) encodeForm(v, prefix ? `${prefix}[${k}]` : k, out);
  } else {
    out.append(prefix, String(value));
  }
  return out;
}

export function createStripe({ secretKey, fetchImpl = globalThis.fetch }) {
  async function call(method, path, params) {
    const res = await fetchImpl(`https://api.stripe.com/v1${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${secretKey}`,
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      body: params ? encodeForm(params).toString() : undefined
    });
    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
      const err = new Error(json.error?.message || `Stripe a répondu ${res.status}`);
      err.status = res.status;
      throw err;
    }
    return json;
  }

  return {
    createCheckoutSession: (params) => call('POST', '/checkout/sessions', params),
    retrieveCheckoutSession: (id) => call('GET', `/checkout/sessions/${encodeURIComponent(id)}?expand[]=subscription`),
    createPortalSession: (params) => call('POST', '/billing_portal/sessions', params)
  };
}

// Vérifie l'en-tête Stripe-Signature (t=…,v1=…) : HMAC-SHA256 de « t.corps » avec le secret du webhook.
export function verifyWebhook(rawBody, header, secret, { toleranceSec = 300, now = Date.now() } = {}) {
  const parts = String(header || '')
    .split(',')
    .map((p) => p.split('='));
  const t = parts.find(([k]) => k === 't')?.[1];
  const signatures = parts.filter(([k]) => k === 'v1').map(([, v]) => v);
  if (!t || !signatures.length) throw new Error('Signature Stripe absente');
  if (Math.abs(now / 1000 - Number(t)) > toleranceSec) throw new Error('Signature Stripe trop ancienne');
  const expected = crypto.createHmac('sha256', secret).update(`${t}.`).update(rawBody).digest();
  const ok = signatures.some((s) => {
    const given = Buffer.from(s, 'hex');
    return given.length === expected.length && crypto.timingSafeEqual(given, expected);
  });
  if (!ok) throw new Error('Signature Stripe invalide');
  return JSON.parse(rawBody.toString('utf8'));
}

export function signWebhookPayload(payload, secret, timestamp = Math.floor(Date.now() / 1000)) {
  const sig = crypto.createHmac('sha256', secret).update(`${timestamp}.${payload}`).digest('hex');
  return `t=${timestamp},v1=${sig}`;
}
