// Images du README tirées de la page tuto (site/tuto.html), dans le style de l'app :
//   node docs/images/rendre-tuto.js        (depuis la racine du dépôt ; Playwright + Chromium)
// Une image par étape (sections marquées data-capture) et le titre, à 2× pour un écran Retina.
const path = require('path');
const { chromium } = require('playwright');
(async () => {
  const racine = path.resolve(__dirname, '..', '..');
  const b = await chromium.launch(process.env.PW_CHROMIUM ? { executablePath: process.env.PW_CHROMIUM } : {});
  const p = await b.newPage({ viewport: { width: 1100, height: 900 }, deviceScaleFactor: 2 });
  await p.goto('file://' + path.join(racine, 'site', 'tuto.html'));
  await p.waitForTimeout(400);
  // Le fond noir de la page autour de chaque carte : marge de 24 points.
  const marge = 24;
  const cibles = await p.$$eval('[data-capture], .hero', els => els.map(e => {
    const r = e.getBoundingClientRect();
    return { nom: e.dataset.capture || 'tuto-0-titre', x: r.x, y: r.y + window.scrollY, w: r.width, h: r.height };
  }));
  for (const c of cibles) {
    const sortie = path.join(racine, 'docs', 'images', c.nom + '.png');
    await p.screenshot({ path: sortie, fullPage: true,
      clip: { x: c.x - marge, y: c.y - marge, width: c.w + 2 * marge, height: c.h + 2 * marge } });
    console.log(sortie);
  }
  await b.close();
})();
