import { $, api, applyTheme, formatPrice, h, renderBrand, toast } from './common.js';
import { THEMES } from './themes.js';

let me = null;

function show(next) {
  me = next;
  const r = me.restaurant;
  applyTheme(r.theme);
  renderBrand($('#brand'), r);
  document.title = `Réglages · ${r.name}`;
  renderLogo();
  renderPlan();
  for (const input of document.querySelectorAll('input[name="theme"]')) input.checked = input.value === r.theme;
}

// ---------- Établissement ----------

const infoForm = $('#info-form');
infoForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  const error = infoForm.querySelector('.error');
  error.textContent = '';
  try {
    show(await api('PUT', '/api/restaurant', { name: infoForm.name.value, siret: infoForm.siret.value }));
    infoForm.siret.value = me.restaurant.siretFormatted;
    toast('Enregistré.');
  } catch (err) {
    error.textContent = err.message;
  }
});

// ---------- Logo ----------

function renderLogo() {
  const { logoUrl } = me.restaurant;
  $('#logo-preview').replaceChildren(logoUrl ? h('img', { src: logoUrl, alt: 'Logo actuel' }) : 'Aucun logo');
  $('#logo-remove').hidden = !logoUrl;
}

function loadImage(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('Cette image ne peut pas être lue.'));
    img.src = url;
  });
}

// L'image est réduite (512 px au plus) et réencodée ici : le serveur ne reçoit qu'une image simple et légère.
async function prepareLogo(file) {
  const img = await loadImage(file);
  const scale = Math.min(1, 512 / Math.max(img.naturalWidth, img.naturalHeight));
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(1, Math.round(img.naturalWidth * scale));
  canvas.height = Math.max(1, Math.round(img.naturalHeight * scale));
  const ctx = canvas.getContext('2d');
  ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
  let url = canvas.toDataURL('image/webp', 0.9);
  if (!url.startsWith('data:image/webp')) url = canvas.toDataURL('image/png');
  if (url.length > 1_000_000) {
    ctx.globalCompositeOperation = 'destination-over';
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    url = canvas.toDataURL('image/jpeg', 0.85);
  }
  URL.revokeObjectURL(img.src);
  return url;
}

$('#logo-pick').addEventListener('click', () => $('#logo-input').click());
$('#logo-input').addEventListener('change', async (e) => {
  const file = e.target.files[0];
  e.target.value = '';
  if (!file) return;
  try {
    show(await api('PUT', '/api/restaurant/logo', { dataUrl: await prepareLogo(file) }));
    toast('Logo enregistré.');
  } catch (err) {
    toast(err.message, { error: true });
  }
});
$('#logo-remove').addEventListener('click', async () => {
  try {
    show(await api('DELETE', '/api/restaurant/logo'));
  } catch (err) {
    toast(err.message, { error: true });
  }
});

// ---------- Couleurs ----------

function buildPalettes() {
  const set = $('#palettes');
  for (const t of THEMES) {
    const top = h('div', { class: 'palette-top' }, h('span', { text: 'Aa' }), h('span', { text: '🔔', 'aria-hidden': 'true' }));
    top.style.background = t.primary;
    top.style.color = t.onPrimary;
    const name = h('div', { class: 'palette-name' }, h('span', { text: t.name }), h('span', { class: 'palette-check', text: '✓', 'aria-hidden': 'true' }));
    name.style.background = t.soft;
    name.style.color = t.ink;
    const input = h('input', { type: 'radio', name: 'theme', value: t.id, 'aria-label': t.name });
    input.addEventListener('change', async () => {
      const previous = me.restaurant.theme;
      applyTheme(t.id);
      try {
        show(await api('PUT', '/api/restaurant', { theme: t.id }));
      } catch (err) {
        toast(err.message, { error: true });
        applyTheme(previous);
        show(me);
      }
    });
    set.append(h('label', { class: 'palette' }, input, top, name));
  }
}

// ---------- Abonnement ----------

function dateText(ts) {
  return new Date(ts).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' });
}

async function redirectTo(path, button) {
  button.disabled = true;
  try {
    const { url } = await api('POST', path);
    location.href = url;
  } catch (err) {
    toast(err.message, { error: true });
    button.disabled = false;
  }
}

function renderPlan() {
  const s = me.subscription;
  let title;
  let text;
  let price = `${formatPrice(s.priceCents)} / mois`;
  let action = null;
  if (s.active && s.plan === 'promo') {
    title = '✓ Abonnement offert';
    text = 'Code promo appliqué : rien à payer.';
  } else if (s.active) {
    title = '✓ Abonnement actif';
    text =
      s.status === 'past_due'
        ? 'Le dernier paiement a échoué : mettez à jour votre carte.'
        : s.periodEnd
          ? `Prochain renouvellement le ${dateText(s.periodEnd)}.`
          : 'Merci pour votre confiance !';
    if (s.canManage) {
      action = h('button', { class: 'btn btn-secondary', type: 'button', text: 'Gérer mon abonnement' });
      action.addEventListener('click', () => redirectTo('/api/billing/portal', action));
    }
  } else {
    title = { canceled: 'Abonnement résilié', unpaid: 'Paiement refusé', incomplete_expired: 'Paiement non abouti' }[s.status] || 'Pas encore d’abonnement';
    price = `${formatPrice(s.listPriceCents)} / mois`;
    if (s.onlinePayment) {
      text = 'Sans engagement, résiliable à tout moment. Paiement sécurisé par Stripe.';
      action = h('button', { class: 'btn btn-primary btn-lg', type: 'button', text: 'S’abonner' });
      action.addEventListener('click', () => redirectTo('/api/billing/checkout', action));
    } else {
      text = 'Le paiement en ligne n’est pas encore ouvert sur ce serveur. Un code promo permet de commencer.';
    }
  }
  $('#plan').replaceChildren(
    h('div', {}, h('strong', { text: title }), h('div', { class: 'small', text })),
    h('div', { class: 'row' }, h('span', { class: 'plan-price', text: price }), action)
  );
  $('#promo-block').hidden = s.active;
}

$('#promo-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  $('#promo-error').textContent = '';
  try {
    show(await api('POST', '/api/billing/promo', { code: $('#promo').value }));
    $('#promo').value = '';
    toast('Code promo appliqué : abonnement offert.');
  } catch (err) {
    $('#promo-error').textContent = err.message;
  }
});

$('#logout').addEventListener('click', async () => {
  await api('POST', '/api/logout').catch(() => {});
  location.href = '/';
});

async function init() {
  try {
    me = await api('GET', '/api/me');
  } catch (err) {
    if (err.status === 401) location.href = '/';
    else toast(err.message, { error: true });
    return;
  }
  buildPalettes();
  infoForm.name.value = me.restaurant.name;
  infoForm.siret.value = me.restaurant.siretFormatted;
  infoForm.email.value = me.restaurant.email;
  show(me);

  const params = new URLSearchParams(location.search);
  if (params.has('bienvenue')) $('#welcome').hidden = false;
  if (params.get('abonnement') === 'annule') toast('Paiement annulé : rien n’a été prélevé.');
  if (params.get('abonnement') === 'ok' && params.get('session_id')) {
    try {
      show(await api('POST', '/api/billing/confirm', { sessionId: params.get('session_id') }));
      toast(me.subscription.active ? 'Abonnement activé, merci !' : 'Paiement en cours de validation…');
    } catch (err) {
      toast(err.message, { error: true });
    }
  }
  if (location.search) history.replaceState(null, '', `/reglages${location.hash}`);
  if (location.hash === '#abonnement') $('#abonnement').scrollIntoView();
}

init();
