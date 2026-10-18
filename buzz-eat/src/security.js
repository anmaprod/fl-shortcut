import crypto from 'node:crypto';
import { promisify } from 'node:util';

const scrypt = promisify(crypto.scrypt);
const SCRYPT = { N: 16384, r: 8, p: 1 };

export function randomToken(bytes = 16) {
  return crypto.randomBytes(bytes).toString('base64url');
}

export function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

// Comparaison à durée constante, quelle que soit la longueur des deux chaînes.
export function safeEqual(a, b) {
  const ha = crypto.createHash('sha256').update(String(a)).digest();
  const hb = crypto.createHash('sha256').update(String(b)).digest();
  return crypto.timingSafeEqual(ha, hb);
}

export async function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const key = await scrypt(password, salt, 32, SCRYPT);
  return `scrypt$${SCRYPT.N}$${SCRYPT.r}$${SCRYPT.p}$${salt.toString('base64url')}$${key.toString('base64url')}`;
}

export async function verifyPassword(password, stored) {
  const [kind, N, r, p, salt, key] = String(stored).split('$');
  if (kind !== 'scrypt' || !key) return false;
  const expected = Buffer.from(key, 'base64url');
  const actual = await scrypt(password, Buffer.from(salt, 'base64url'), expected.length, {
    N: Number(N),
    r: Number(r),
    p: Number(p)
  });
  return crypto.timingSafeEqual(expected, actual);
}

// Limiteur simple en mémoire : au plus `max` essais par fenêtre de `windowMs`.
export class RateLimiter {
  constructor(now = () => Date.now()) {
    this.now = now;
    this.hits = new Map();
  }

  allow(key, max, windowMs) {
    const t = this.now();
    const entry = this.hits.get(key);
    if (!entry || entry.reset <= t) {
      this.hits.set(key, { count: 1, reset: t + windowMs });
      return true;
    }
    entry.count += 1;
    return entry.count <= max;
  }

  sweep() {
    const t = this.now();
    for (const [key, entry] of this.hits) if (entry.reset <= t) this.hits.delete(key);
  }
}
