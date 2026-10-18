import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';

const SCHEMA = `
CREATE TABLE IF NOT EXISTS restaurants (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  name TEXT NOT NULL,
  siret TEXT NOT NULL,
  theme TEXT NOT NULL,
  logo BLOB,
  logo_type TEXT,
  logo_version INTEGER NOT NULL DEFAULT 0,
  order_counter INTEGER NOT NULL DEFAULT 0,
  counter_day TEXT,
  plan TEXT,
  sub_status TEXT NOT NULL DEFAULT 'none',
  period_end INTEGER,
  stripe_customer_id TEXT,
  stripe_subscription_id TEXT,
  promo_code TEXT,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  restaurant_id TEXT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS orders (
  id TEXT PRIMARY KEY,
  restaurant_id TEXT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  token TEXT NOT NULL UNIQUE,
  number INTEGER NOT NULL,
  customer TEXT NOT NULL DEFAULT '',
  details TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'preparing',
  source TEXT NOT NULL DEFAULT 'bar',
  alert_on INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  ready_at INTEGER
);
CREATE INDEX IF NOT EXISTS orders_by_restaurant ON orders(restaurant_id, created_at);
CREATE TABLE IF NOT EXISTS popina (
  restaurant_id TEXT PRIMARY KEY REFERENCES restaurants(id) ON DELETE CASCADE,
  token TEXT NOT NULL UNIQUE,
  secret TEXT,
  enabled INTEGER NOT NULL DEFAULT 0,
  create_on TEXT NOT NULL DEFAULT 'sent',
  rooms TEXT NOT NULL DEFAULT '',
  last_at INTEGER,
  last_info TEXT
);
CREATE TABLE IF NOT EXISTS external_orders (
  restaurant_id TEXT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  external_id TEXT NOT NULL,
  order_id TEXT,
  seen_at INTEGER NOT NULL,
  PRIMARY KEY (restaurant_id, external_id)
);
CREATE TABLE IF NOT EXISTS push_subscriptions (
  endpoint TEXT PRIMARY KEY,
  order_id TEXT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  p256dh TEXT NOT NULL,
  auth TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS stripe_events (
  id TEXT PRIMARY KEY,
  received_at INTEGER NOT NULL
);
`;

const RESTAURANT_UPDATABLE = new Set([
  'name',
  'siret',
  'theme',
  'plan',
  'sub_status',
  'period_end',
  'stripe_customer_id',
  'stripe_subscription_id',
  'promo_code'
]);

export function openDatabase(file) {
  if (file !== ':memory:') fs.mkdirSync(path.dirname(file), { recursive: true });
  const db = new DatabaseSync(file);
  db.exec('PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;');
  if (file !== ':memory:') db.exec('PRAGMA journal_mode = WAL;');
  db.exec(SCHEMA);
  // Colonnes ajoutées après la première version : ajoutées aux bases déjà créées.
  const hasColumn = (table, column) => db.prepare(`PRAGMA table_info(${table})`).all().some((c) => c.name === column);
  if (!hasColumn('orders', 'source')) db.exec("ALTER TABLE orders ADD COLUMN source TEXT NOT NULL DEFAULT 'bar'");

  const q = (sql) => db.prepare(sql);
  // Toutes les colonnes sauf l'image du logo, lue seulement quand on la sert.
  const R = `id, email, password_hash, name, siret, theme, logo_type, logo_version, order_counter, counter_day,
    plan, sub_status, period_end, stripe_customer_id, stripe_subscription_id, promo_code, created_at`;
  const st = {
    insertRestaurant: q(`INSERT INTO restaurants (id, email, password_hash, name, siret, theme, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)`),
    restaurantById: q(`SELECT ${R} FROM restaurants WHERE id = ?`),
    restaurantByEmail: q(`SELECT ${R} FROM restaurants WHERE email = ?`),
    restaurantByCustomer: q(`SELECT ${R} FROM restaurants WHERE stripe_customer_id = ?`),
    restaurantBySubscription: q(`SELECT ${R} FROM restaurants WHERE stripe_subscription_id = ?`),
    setLogo: q('UPDATE restaurants SET logo = ?, logo_type = ?, logo_version = logo_version + 1 WHERE id = ?'),
    logo: q('SELECT logo, logo_type FROM restaurants WHERE id = ?'),
    nextNumber: q(`UPDATE restaurants
      SET order_counter = CASE WHEN counter_day = ? THEN order_counter % 999 + 1 ELSE 1 END, counter_day = ?
      WHERE id = ? RETURNING order_counter`),

    insertSession: q('INSERT INTO sessions (token_hash, restaurant_id, expires_at) VALUES (?, ?, ?)'),
    session: q('SELECT * FROM sessions WHERE token_hash = ? AND expires_at > ?'),
    deleteSession: q('DELETE FROM sessions WHERE token_hash = ?'),
    purgeSessions: q('DELETE FROM sessions WHERE expires_at <= ?'),

    insertOrder: q(`INSERT INTO orders (id, restaurant_id, token, number, customer, details, source, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)`),
    updateOrderText: q('UPDATE orders SET customer = ?, details = ? WHERE id = ?'),
    orderById: q('SELECT * FROM orders WHERE id = ? AND restaurant_id = ?'),
    orderByToken: q('SELECT * FROM orders WHERE token = ?'),
    ordersOf: q('SELECT * FROM orders WHERE restaurant_id = ? ORDER BY created_at'),
    markReady: q("UPDATE orders SET status = 'ready', ready_at = ? WHERE id = ?"),
    markAlertOn: q('UPDATE orders SET alert_on = 1 WHERE id = ?'),
    deleteOrder: q('DELETE FROM orders WHERE id = ?'),
    staleOrders: q('SELECT * FROM orders WHERE created_at <= ?'),

    insertPush: q(`INSERT INTO push_subscriptions (endpoint, order_id, p256dh, auth) VALUES (?, ?, ?, ?)
      ON CONFLICT(endpoint) DO UPDATE SET order_id = excluded.order_id, p256dh = excluded.p256dh, auth = excluded.auth`),
    pushOf: q('SELECT * FROM push_subscriptions WHERE order_id = ?'),
    countPush: q('SELECT COUNT(*) AS n FROM push_subscriptions WHERE order_id = ?'),
    deletePush: q('DELETE FROM push_subscriptions WHERE endpoint = ?'),

    popina: q('SELECT * FROM popina WHERE restaurant_id = ?'),
    popinaByToken: q('SELECT * FROM popina WHERE token = ?'),
    insertPopina: q('INSERT INTO popina (restaurant_id, token) VALUES (?, ?) ON CONFLICT(restaurant_id) DO NOTHING'),
    externalOrder: q('SELECT * FROM external_orders WHERE restaurant_id = ? AND external_id = ?'),
    rememberExternal: q(`INSERT INTO external_orders (restaurant_id, external_id, order_id, seen_at) VALUES (?, ?, ?, ?)
      ON CONFLICT(restaurant_id, external_id) DO UPDATE SET order_id = excluded.order_id, seen_at = excluded.seen_at`),
    purgeExternal: q('DELETE FROM external_orders WHERE seen_at <= ?'),

    getSetting: q('SELECT value FROM settings WHERE key = ?'),
    setSetting: q('INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value'),

    insertStripeEvent: q('INSERT OR IGNORE INTO stripe_events (id, received_at) VALUES (?, ?)'),
    purgeStripeEvents: q('DELETE FROM stripe_events WHERE received_at <= ?')
  };

  return {
    raw: db,
    close: () => db.close(),

    createRestaurant: (r) =>
      st.insertRestaurant.run(r.id, r.email, r.passwordHash, r.name, r.siret, r.theme, r.createdAt),
    restaurant: (id) => st.restaurantById.get(id),
    restaurantByEmail: (email) => st.restaurantByEmail.get(email),
    restaurantByCustomer: (id) => st.restaurantByCustomer.get(id),
    restaurantBySubscription: (id) => st.restaurantBySubscription.get(id),
    updateRestaurant(id, fields) {
      const keys = Object.keys(fields).filter((k) => RESTAURANT_UPDATABLE.has(k));
      if (!keys.length) return;
      const sql = `UPDATE restaurants SET ${keys.map((k) => `${k} = ?`).join(', ')} WHERE id = ?`;
      db.prepare(sql).run(...keys.map((k) => fields[k] ?? null), id);
    },
    setLogo: (id, data, type) => st.setLogo.run(data, type, id),
    logo: (id) => st.logo.get(id),
    nextOrderNumber: (id, day) => st.nextNumber.get(day, day, id).order_counter,

    createSession: (tokenHash, restaurantId, expiresAt) => st.insertSession.run(tokenHash, restaurantId, expiresAt),
    session: (tokenHash, now) => st.session.get(tokenHash, now),
    deleteSession: (tokenHash) => st.deleteSession.run(tokenHash),
    purgeSessions: (now) => st.purgeSessions.run(now),

    createOrder: (o) =>
      st.insertOrder.run(o.id, o.restaurantId, o.token, o.number, o.customer, o.details, o.source || 'bar', o.createdAt),
    updateOrderText: (id, customer, details) => st.updateOrderText.run(customer, details, id),
    order: (id, restaurantId) => st.orderById.get(id, restaurantId),
    orderByToken: (token) => st.orderByToken.get(token),
    orders: (restaurantId) => st.ordersOf.all(restaurantId),
    markReady: (id, at) => st.markReady.run(at, id),
    markAlertOn: (id) => st.markAlertOn.run(id),
    deleteOrder: (id) => st.deleteOrder.run(id),
    staleOrders: (before) => st.staleOrders.all(before),

    addPushSubscription: (orderId, sub) => st.insertPush.run(sub.endpoint, orderId, sub.p256dh, sub.auth),
    pushSubscriptions: (orderId) => st.pushOf.all(orderId),
    countPushSubscriptions: (orderId) => st.countPush.get(orderId).n,
    deletePushSubscription: (endpoint) => st.deletePush.run(endpoint),

    popina: (restaurantId) => st.popina.get(restaurantId),
    popinaByToken: (token) => st.popinaByToken.get(token),
    ensurePopina: (restaurantId, token) => st.insertPopina.run(restaurantId, token),
    updatePopina(restaurantId, fields) {
      const allowed = ['token', 'secret', 'enabled', 'create_on', 'rooms', 'last_at', 'last_info'];
      const keys = Object.keys(fields).filter((k) => allowed.includes(k));
      if (!keys.length) return;
      const sql = `UPDATE popina SET ${keys.map((k) => `${k} = ?`).join(', ')} WHERE restaurant_id = ?`;
      db.prepare(sql).run(...keys.map((k) => fields[k] ?? null), restaurantId);
    },
    externalOrder: (restaurantId, externalId) => st.externalOrder.get(restaurantId, externalId),
    rememberExternalOrder: (restaurantId, externalId, orderId, now) =>
      st.rememberExternal.run(restaurantId, externalId, orderId, now),
    purgeExternalOrders: (before) => st.purgeExternal.run(before),

    getSetting: (key) => st.getSetting.get(key)?.value,
    setSetting: (key, value) => st.setSetting.run(key, value),

    // Vrai la première fois qu'un événement Stripe est vu (Stripe peut renvoyer le même).
    claimStripeEvent: (id, now) => st.insertStripeEvent.run(id, now).changes === 1,
    purgeStripeEvents: (before) => st.purgeStripeEvents.run(before)
  };
}
