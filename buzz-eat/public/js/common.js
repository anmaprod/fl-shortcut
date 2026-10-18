import { getTheme } from './themes.js';

export async function api(method, path, body) {
  const init = { method, credentials: 'same-origin', headers: {} };
  if (method !== 'GET') {
    init.headers['Content-Type'] = 'application/json';
    init.body = JSON.stringify(body ?? {});
  }
  let res;
  try {
    res = await fetch(path, init);
  } catch {
    throw Object.assign(new Error('Pas de connexion internet.'), { status: 0 });
  }
  let data = null;
  try {
    data = await res.json();
  } catch {}
  if (!res.ok) throw Object.assign(new Error(data?.error || `Erreur ${res.status}`), { status: res.status });
  return data;
}

export function applyTheme(themeId) {
  const t = getTheme(themeId);
  const s = document.documentElement.style;
  s.setProperty('--primary', t.primary);
  s.setProperty('--on-primary', t.onPrimary);
  s.setProperty('--soft', t.soft);
  s.setProperty('--ink', t.ink);
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', t.primary);
  return t;
}

// Petit constructeur d'éléments : le texte passe toujours par textContent, jamais par innerHTML.
export function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === false || v === null || v === undefined) continue;
    if (k === 'class') el.className = v;
    else if (k === 'text') el.textContent = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const c of children.flat()) {
    if (c === null || c === undefined || c === false) continue;
    el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return el;
}

export const $ = (selector, root = document) => root.querySelector(selector);

let toastTimer;
export function toast(message, { error = false } = {}) {
  let el = $('.toast');
  if (!el) {
    el = h('div', { class: 'toast', role: 'status', 'aria-live': 'polite' });
    document.body.append(el);
  }
  el.textContent = message;
  el.classList.toggle('is-error', error);
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (el.hidden = true), 3500);
}

export function formatPrice(cents) {
  return new Intl.NumberFormat('fr-FR', {
    style: 'currency',
    currency: 'EUR',
    minimumFractionDigits: cents % 100 ? 2 : 0
  }).format(cents / 100);
}

export function elapsed(since, now = Date.now()) {
  const min = Math.floor((now - since) / 60000);
  if (min < 1) return 'à l’instant';
  if (min < 60) return `il y a ${min} min`;
  const hours = Math.floor(min / 60);
  return `il y a ${hours} h ${String(min % 60).padStart(2, '0')}`;
}

export function clock(ts) {
  return new Date(ts).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
}

export function renderBrand(container, restaurant) {
  container.replaceChildren(
    restaurant.logoUrl
      ? h('img', { class: 'brand-logo', src: restaurant.logoUrl, alt: '' })
      : h('span', { class: 'brand-mark', 'aria-hidden': 'true', text: '🔔' }),
    h('span', { class: 'brand-name', text: restaurant.name })
  );
}

export async function registerServiceWorker() {
  if (!('serviceWorker' in navigator)) return null;
  try {
    return await navigator.serviceWorker.register('/sw.js', { scope: '/' });
  } catch {
    return null;
  }
}
