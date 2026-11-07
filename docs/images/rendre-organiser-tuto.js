// Images du tuto de l'Organiser, dans les deux langues de l'app :
//   node docs/images/rendre-organiser-tuto.js     (depuis la racine du dépôt ; Playwright + Chromium)
// → Resources/fr.lproj/OrganiserTuto1-4.png et Resources/en.lproj/OrganiserTuto1-4.png (400 × 225 points, à 2×),
// choisies par macOS selon la langue du Mac.
const path = require('path');
const { chromium } = require('playwright');
(async () => {
  const racine = path.resolve(__dirname, '..', '..');
  const b = await chromium.launch(process.env.PW_CHROMIUM ? { executablePath: process.env.PW_CHROMIUM } : {});
  const p = await b.newPage({ viewport: { width: 400, height: 225 }, deviceScaleFactor: 2 });
  for (const lang of ['fr', 'en']) {
    for (const step of [1, 2, 3, 4]) {
      await p.goto('file://' + path.join(__dirname, 'organiser-tuto.html') + `#${lang}-${step}`);
      await p.reload();
      await p.waitForTimeout(150);
      const sortie = path.join(racine, 'Resources', `${lang}.lproj`, `OrganiserTuto${step}.png`);
      await p.locator('.scene').screenshot({ path: sortie, omitBackground: true });
      console.log(sortie);
    }
  }
  await b.close();
})();
