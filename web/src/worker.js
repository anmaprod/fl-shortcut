// Site FL Shortcuts sur Cloudflare : les fichiers de public/ et deux adresses pour le paiement SumUp.
//
//   POST /api/paiement        { montant, systeme }  crée un paiement SumUp et renvoie l'adresse de sa page
//                                                   de paiement (checkout.sumup.com), où le navigateur part payer
//   GET  /api/paiement/<id>                          renvoie l'état du paiement chez SumUp (PAID, PENDING…)
//   POST /api/lien            { mail, systeme, paiement? }  envoie le lien de téléchargement par mail (Brevo)
//
// Réglages du Worker (Cloudflare › Workers › fl-shortcuts › Settings › Variables and Secrets) :
//   SUMUP_API_KEY        secret : clé API SumUp (sup_sk_…), jamais dans le code ni dans le dépôt
//   SUMUP_MERCHANT_CODE  code marchand SumUp (commence par M)
//   BREVO_API_KEY        secret : clé API Brevo (xkeysib-…), pour envoyer le lien par mail
//   MAIL_EXPEDITEUR      adresse d'envoi validée dans Brevo, par exemple bonjour@ton-domaine.fr
// Sans SumUp, /api/paiement répond 503 et le site propose le téléchargement gratuit.
// Sans Brevo, /api/lien répond { envoye: false } et le site ne parle pas de mail.
// LIMITE_MAIL (wrangler.jsonc) : au plus 3 mails par minute pour une même adresse IP et une même adresse mail.

const SUMUP = 'https://api.sumup.com/v0.1/checkouts';
const BREVO = 'https://api.brevo.com/v3/smtp/email';
const MIN = 1;
const MAX = 999;
const ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAIL = /^[^\s@<>"]+@[^\s@<>"]+\.[^\s@<>"]{2,}$/;
const VERSIONS = 'https://github.com/anmaprod/fl-shortcut/releases/latest/download/';
const SYSTEMES = {
  mac: {
    nom: 'Mac',
    fichier: 'FLShortcut.dmg',
    detail: 'macOS 13 ou plus récent',
    etapes: [
      'Ouvre FLShortcut.dmg et glisse FL Shortcut dans Applications.',
      "Lance FL Shortcut : il s'installe dans la barre des menus.",
      'Clique sur Autoriser… puis active FL Shortcut dans Réglages Système › Confidentialité et sécurité › Accessibilité.',
    ],
    aide: "Si macOS dit qu'il ne peut pas vérifier l'app : Réglages Système › Confidentialité et sécurité, tout en bas, Ouvrir quand même.",
  },
  windows: {
    nom: 'Windows',
    fichier: 'FLShortcut-Windows-Setup.exe',
    detail: 'Windows 10 ou 11',
    etapes: [
      "Double-clique sur l'installeur, puis Installer. Aucun droit administrateur demandé.",
      "FL Shortcut se range dans la zone de notification, à côté de l'horloge.",
      'Ouvre FL Studio et utilise tes raccourcis.',
    ],
    aide: 'Si Windows affiche « Windows a protégé votre ordinateur » : Informations complémentaires, puis Exécuter quand même.',
  },
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/api/paiement') {
      if (request.method !== 'POST') return json({ erreur: 'Méthode non autorisée.' }, 405, { Allow: 'POST' });
      return creer(request, env, url);
    }
    if (url.pathname.startsWith('/api/paiement/')) {
      if (request.method !== 'GET') return json({ erreur: 'Méthode non autorisée.' }, 405, { Allow: 'GET' });
      return etat(decodeURIComponent(url.pathname.slice('/api/paiement/'.length)), env);
    }
    if (url.pathname === '/api/lien') {
      if (request.method !== 'POST') return json({ erreur: 'Méthode non autorisée.' }, 405, { Allow: 'POST' });
      return lien(request, env, url);
    }
    if (url.pathname.startsWith('/api/')) return json({ erreur: 'Adresse inconnue.' }, 404);
    return env.ASSETS.fetch(request);
  },
};

async function creer(request, env, url) {
  // Seul le site lui-même peut lancer un paiement.
  const origine = request.headers.get('Origin');
  if (origine && origine !== url.origin) return json({ erreur: 'Origine refusée.' }, 403);
  if (!env.SUMUP_API_KEY || !env.SUMUP_MERCHANT_CODE) return json({ erreur: "Le paiement n'est pas encore ouvert." }, 503);

  let demande;
  try { demande = await request.json(); } catch { return json({ erreur: 'Demande illisible.' }, 400); }
  const montant = demande?.montant;
  if (!Number.isInteger(montant) || montant < MIN || montant > MAX) {
    return json({ erreur: `Le montant doit être un nombre entier entre ${MIN} et ${MAX} €.` }, 400);
  }
  const systeme = demande?.systeme === 'windows' ? 'Windows' : 'Mac';

  const reponse = await fetch(SUMUP, {
    method: 'POST',
    headers: { Authorization: `Bearer ${env.SUMUP_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      checkout_reference: crypto.randomUUID(),
      amount: montant,
      currency: 'EUR',
      merchant_code: env.SUMUP_MERCHANT_CODE,
      description: `FL Shortcuts pour ${systeme}, prix libre`,
      // Page de paiement de SumUp (carte, Apple Pay, Google Pay), ouverte 30 minutes.
      hosted_checkout: { enabled: true },
      // Après le paiement, le bouton de retour de SumUp ramène ici ; la page vérifie alors le paiement.
      redirect_url: `${url.origin}/?paiement=retour`,
    }),
  }).catch(() => null);

  const echec = () => json({ erreur: "Le paiement n'a pas pu démarrer. Réessaie dans un instant." }, 502);
  if (!reponse || !reponse.ok) {
    console.error('SumUp, création refusée', reponse?.status, reponse ? await reponse.text() : 'réseau');
    return echec();
  }
  const paiement = await reponse.json();
  const page = pageSumup(paiement.hosted_checkout_url);
  if (!paiement.id || !page) {
    console.error('SumUp, réponse sans page de paiement');
    return echec();
  }
  return json({ id: paiement.id, montant, url: page });
}

// Le navigateur ne part que vers une adresse https de SumUp, jamais ailleurs.
function pageSumup(adresse) {
  try {
    const u = new URL(adresse);
    const chezSumup = u.hostname === 'sumup.com' || u.hostname.endsWith('.sumup.com');
    return u.protocol === 'https:' && chezSumup ? u.href : null;
  } catch {
    return null;
  }
}

async function etat(id, env) {
  if (!ID.test(id)) return json({ erreur: 'Paiement inconnu.' }, 404);
  if (!env.SUMUP_API_KEY) return json({ erreur: "Le paiement n'est pas encore ouvert." }, 503);
  const reponse = await fetch(`${SUMUP}/${id}`, {
    headers: { Authorization: `Bearer ${env.SUMUP_API_KEY}` },
  }).catch(() => null);
  if (reponse?.status === 404) return json({ erreur: 'Paiement inconnu.' }, 404);
  if (!reponse || !reponse.ok) {
    console.error('SumUp, lecture refusée', reponse?.status);
    return json({ erreur: 'SumUp ne répond pas pour le moment.' }, 502);
  }
  const paiement = await reponse.json();
  // Seulement l'état et le montant : rien d'autre ne sort de chez SumUp.
  return json({ statut: paiement.status, montant: paiement.amount });
}

// Envoie le lien de téléchargement par mail. Le contenu est toujours le même (lien, étapes d'installation) :
// rien de ce qu'envoie le navigateur n'est recopié dans le mail, à part le montant d'un paiement vérifié chez SumUp.
async function lien(request, env, url) {
  const origine = request.headers.get('Origin');
  if (origine && origine !== url.origin) return json({ erreur: 'Origine refusée.' }, 403);

  let demande;
  try { demande = await request.json(); } catch { return json({ erreur: 'Demande illisible.' }, 400); }
  const mail = typeof demande?.mail === 'string' ? demande.mail.trim() : '';
  if (mail.length > 254 || !MAIL.test(mail)) return json({ erreur: 'Adresse mail invalide.' }, 400);
  const systeme = demande?.systeme === 'windows' ? 'windows' : 'mac';

  if (!env.BREVO_API_KEY || !env.MAIL_EXPEDITEUR) return json({ envoye: false });

  // Pas plus de quelques mails par minute depuis une même connexion, ni vers une même adresse.
  if (env.LIMITE_MAIL) {
    const ip = request.headers.get('CF-Connecting-IP') || 'inconnue';
    for (const key of [`ip:${ip}`, `mail:${mail.toLowerCase()}`]) {
      const { success } = await env.LIMITE_MAIL.limit({ key });
      if (!success) return json({ envoye: false, erreur: 'Trop de demandes. Réessaie dans une minute.' }, 429);
    }
  }

  // Paiement annoncé : on remercie pour le montant seulement s'il est bien payé chez SumUp.
  let montant = null;
  if (typeof demande?.paiement === 'string' && ID.test(demande.paiement) && env.SUMUP_API_KEY) {
    const r = await fetch(`${SUMUP}/${demande.paiement}`, {
      headers: { Authorization: `Bearer ${env.SUMUP_API_KEY}` },
    }).catch(() => null);
    const paiement = r?.ok ? await r.json().catch(() => null) : null;
    if (paiement?.status === 'PAID' && Number.isFinite(paiement.amount)) montant = paiement.amount;
  }

  const contenu = courriel(systeme, montant, url.origin);
  const reponse = await fetch(BREVO, {
    method: 'POST',
    headers: { 'api-key': env.BREVO_API_KEY, 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({
      sender: { name: 'FL Shortcuts', email: env.MAIL_EXPEDITEUR },
      to: [{ email: mail }],
      subject: contenu.sujet,
      htmlContent: contenu.html,
      textContent: contenu.texte,
      tags: ['lien-telechargement'],
    }),
  }).catch(() => null);
  if (!reponse || !reponse.ok) {
    console.error('Brevo, envoi refusé', reponse?.status, reponse ? await reponse.text() : 'réseau');
    return json({ envoye: false }, 502);
  }
  return json({ envoye: true });
}

function courriel(systeme, montant, site) {
  const s = SYSTEMES[systeme] || SYSTEMES.mac;
  const adresse = VERSIONS + s.fichier;
  const euros = montant === null ? null : `${Number.isInteger(montant) ? montant : montant.toFixed(2).replace('.', ',')} €`;
  const merci = euros ? `Merci pour ton soutien de ${euros} !` : 'Merci de soutenir FL Shortcuts !';
  const sujet = `Ton lien FL Shortcuts pour ${s.nom}`;
  const texte = [
    'Salut,',
    '',
    `Voici ton lien pour télécharger FL Shortcuts pour ${s.nom} (${s.fichier}, ${s.detail}) :`,
    adresse,
    '',
    'Installer :',
    ...s.etapes.map((e, i) => `${i + 1}. ${e}`),
    '',
    s.aide,
    '',
    merci,
    'fl shortcuts.',
    '',
    `Tu reçois ce mail parce que tu as demandé l'app sur ${site}. Ton adresse ne sert qu'à cet envoi.`,
  ].join('\n');
  const html = `<!doctype html><html lang="fr"><body style="margin:0;background:#ffffff;color:#000000;font:16px/1.5 'Helvetica Neue',Helvetica,Arial,sans-serif">
<div style="max-width:520px;margin:0 auto;padding:32px 20px">
<p style="margin:0 0 24px;font:700 26px/1 'Helvetica Neue',Helvetica,Arial,sans-serif;letter-spacing:-1px">fl shortcuts<span style="color:#FF3B1F">.</span></p>
<p style="margin:0 0 20px">Salut,<br>voici ton lien pour télécharger FL Shortcuts pour ${s.nom}.</p>
<p style="margin:0 0 28px"><a href="${adresse}" style="display:inline-block;background:#000000;color:#ffffff;padding:16px 24px;font-weight:700;letter-spacing:1px;text-transform:uppercase;text-decoration:none;box-shadow:6px 6px 0 #FF3B1F">Télécharger pour ${s.nom}</a></p>
<p style="margin:0 0 6px;color:#6E6E6E;font-size:13px">${s.fichier} · ${s.detail}</p>
<p style="margin:24px 0 8px;font-weight:700;font-size:12px;letter-spacing:1.4px;text-transform:uppercase;color:#6E6E6E">Installer</p>
<ol style="margin:0 0 16px;padding-left:20px">${s.etapes.map((e) => `<li style="margin:0 0 6px">${e}</li>`).join('')}</ol>
<p style="margin:0 0 24px;color:#6E6E6E;font-size:14px">${s.aide}</p>
<p style="margin:0 0 32px;font-weight:700">${merci}</p>
<p style="margin:0;color:#8C8C8C;font-size:12px">Tu reçois ce mail parce que tu as demandé l'app sur ${site}. Ton adresse ne sert qu'à cet envoi.</p>
</div></body></html>`;
  return { sujet, texte, html };
}

function json(donnees, statut = 200, entetes = {}) {
  return new Response(JSON.stringify(donnees), {
    status: statut,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...entetes },
  });
}
