import { $, api, applyTheme, elapsed, formatPrice, h, icon, toast } from './common.js';
import { THEMES } from './themes.js';

let me = null;
let popina = null;

function show(next) {
  me = next;
  const r = me.restaurant;
  applyTheme(r.theme);
  document.title = `Réglages · ${r.name}`;
  $('#profile-name').textContent = r.name;
  $('#profile-sub').textContent = `SIRET ${r.siretFormatted}`;
  $('#profile-logo').replaceChildren(r.logoUrl ? h('img', { src: r.logoUrl, alt: 'Logo' }) : icon('store'));
  $('#logo-remove').hidden = !r.logoUrl;
  for (const input of document.querySelectorAll('input[name="theme"]')) input.checked = input.value === r.theme;
  renderPlan();
}

// ---------- Établissement : enregistré dès qu'on quitte le champ ----------

const infoForm = $('#info-form');
const infoFooter = $('#info-footer');
const infoHint = infoFooter.textContent;

async function saveInfo() {
  const name = infoForm.name.value;
  const siret = infoForm.siret.value;
  if (name === me.restaurant.name && siret.replace(/\s/g, '') === me.restaurant.siret) return;
  try {
    show(await api('PUT', '/api/restaurant', { name, siret }));
    infoForm.siret.value = me.restaurant.siretFormatted;
    infoFooter.textContent = infoHint;
    infoFooter.classList.remove('is-error');
    toast('Enregistré');
  } catch (err) {
    infoFooter.textContent = err.message;
    infoFooter.classList.add('is-error');
  }
}

infoForm.addEventListener('change', saveInfo);
infoForm.addEventListener('submit', (e) => {
  e.preventDefault();
  document.activeElement?.blur();
  saveInfo();
});

// ---------- Logo ----------

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
    toast('Logo enregistré');
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

// ---------- Couleur ----------

function buildSwatches() {
  const set = $('#palettes');
  for (const t of THEMES) {
    const input = h('input', { type: 'radio', name: 'theme', value: t.id });
    const dot = h('span', { class: 'swatch-dot' }, icon('check'));
    dot.style.background = t.tint;
    const label = h('label', { class: 'swatch' }, input, dot, h('span', { text: t.name }));
    label.style.setProperty('--swatch', t.tint);
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
    set.append(label);
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

function buttonRow(text, path) {
  const button = h('button', { class: 'row row-button', type: 'button', text });
  button.addEventListener('click', () => redirectTo(path, button));
  return button;
}

function renderPlan() {
  const s = me.subscription;
  const price = `${formatPrice(s.active ? s.priceCents : s.listPriceCents)} par mois`;
  const [state, stateClass] = s.active
    ? s.status === 'past_due'
      ? ['Paiement en attente', 'warn']
      : ['Actif', 'ok']
    : [{ canceled: 'Résilié', unpaid: 'Paiement refusé', incomplete_expired: 'Non abouti' }[s.status] || 'Inactif', ''];
  const rows = [
    h(
      'div',
      { class: 'row' },
      h('span', { class: 'row-icon' }, icon('creditcard')),
      h('span', { class: 'row-label' }, 'Buzz Eat', h('span', { class: 'row-sub', text: s.plan === 'promo' ? `${price} · code promo` : price })),
      h('span', { class: `row-value ${stateClass}`.trim(), text: state })
    )
  ];
  if (s.active && s.plan === 'stripe' && s.periodEnd) {
    rows.push(
      h(
        'div',
        { class: 'row' },
        h('span', { class: 'row-icon gray' }, icon('clock')),
        h('span', { class: 'row-label', text: 'Renouvellement' }),
        h('span', { class: 'row-value', text: dateText(s.periodEnd) })
      )
    );
  }
  if (!s.active && s.onlinePayment) rows.push(buttonRow('S’abonner', '/api/billing/checkout'));
  if (s.canManage) rows.push(buttonRow('Gérer l’abonnement', '/api/billing/portal'));
  $('#plan').replaceChildren(...rows);
  $('#plan-footer').textContent = s.active
    ? s.plan === 'promo'
      ? 'Abonnement offert grâce à un code promo.'
      : s.status === 'past_due'
        ? 'Le dernier paiement a échoué : mettez votre carte à jour dans « Gérer l’abonnement ».'
        : 'Sans engagement : résiliable à tout moment dans « Gérer l’abonnement ».'
    : s.onlinePayment
      ? 'Sans engagement. Paiement sécurisé par Stripe.'
      : 'Le paiement en ligne n’est pas encore ouvert sur ce serveur. Un code promo permet de commencer.';
  $('#promo-block').hidden = s.active;
}

$('#promo-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  $('#promo-error').textContent = '';
  try {
    show(await api('POST', '/api/billing/promo', { code: $('#promo').value }));
    $('#promo').value = '';
    toast('Abonnement offert');
  } catch (err) {
    $('#promo-error').textContent = err.message;
  }
});

// ---------- Popina ----------

function renderPopina(view) {
  popina = view;
  $('#popina-enabled').checked = view.enabled;
  $('#popina-details').hidden = !view.enabled;
  for (const b of document.querySelectorAll('#popina-create-on button')) {
    b.setAttribute('aria-pressed', String(b.dataset.value === view.createOn));
  }
  if (document.activeElement !== $('#popina-rooms')) $('#popina-rooms').value = view.rooms;
  $('#popina-url').textContent = view.webhookUrl || '';
  $('#popina-secret').placeholder = view.hasSecret ? 'Enregistrée' : 'Coller la clé';
  $('#popina-last').textContent = view.lastAt ? `${view.lastInfo} · ${elapsed(view.lastAt)}` : 'Aucun';
}

async function savePopina(fields, message) {
  try {
    renderPopina(await api('PUT', '/api/popina', fields));
    if (message) toast(message);
  } catch (err) {
    toast(err.message, { error: true });
    renderPopina(popina);
  }
}

$('#popina-enabled').addEventListener('change', (e) => savePopina({ enabled: e.target.checked }));
for (const b of document.querySelectorAll('#popina-create-on button')) {
  b.addEventListener('click', () => savePopina({ createOn: b.dataset.value }));
}
$('#popina-rooms').addEventListener('change', (e) => savePopina({ rooms: e.target.value }, 'Enregistré'));
$('#popina-secret').addEventListener('change', async (e) => {
  const secret = e.target.value.trim();
  if (!secret) return;
  await savePopina({ secret }, 'Clé secrète enregistrée');
  e.target.value = '';
});
for (const id of ['#popina-rooms', '#popina-secret']) {
  $(id).addEventListener('keydown', (e) => {
    if (e.key === 'Enter') e.target.blur();
  });
}
$('#popina-copy').addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(popina.webhookUrl);
    toast('Adresse copiée');
  } catch {
    getSelection().selectAllChildren($('#popina-url'));
  }
});
$('#popina-renew').addEventListener('click', async () => {
  if (!confirm('L’adresse actuelle ne marchera plus. Il faudra donner la nouvelle au support Popina. Continuer ?')) return;
  try {
    renderPopina(await api('POST', '/api/popina/address'));
    toast('Nouvelle adresse créée');
  } catch (err) {
    toast(err.message, { error: true });
  }
});

// ---------- Compte ----------

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
  buildSwatches();
  infoForm.name.value = me.restaurant.name;
  infoForm.siret.value = me.restaurant.siretFormatted;
  $('#email').textContent = me.restaurant.email;
  show(me);
  api('GET', '/api/popina').then(renderPopina, () => {});
  // Le dernier envoi reçu de Popina se met à jour tout seul pendant qu'on règle la connexion.
  setInterval(() => {
    if (document.visibilityState === 'visible' && popina?.enabled) api('GET', '/api/popina').then(renderPopina, () => {});
  }, 15000);

  const params = new URLSearchParams(location.search);
  if (params.has('bienvenue')) $('#welcome').hidden = false;
  if (params.get('abonnement') === 'annule') toast('Paiement annulé : rien n’a été prélevé');
  if (params.get('abonnement') === 'ok' && params.get('session_id')) {
    try {
      show(await api('POST', '/api/billing/confirm', { sessionId: params.get('session_id') }));
      toast(me.subscription.active ? 'Abonnement activé, merci' : 'Paiement en cours de validation');
    } catch (err) {
      toast(err.message, { error: true });
    }
  }
  if (location.search) history.replaceState(null, '', `/reglages${location.hash}`);
  if (location.hash) document.querySelector(location.hash)?.scrollIntoView();
}

init();
