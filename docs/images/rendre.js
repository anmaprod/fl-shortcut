// Rend une page HTML en PNG à 2× (fond transparent) : node rendre.js <page.html> <sortie.png>
const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 714, height: 842 }, deviceScaleFactor: 2 });
  await p.goto('file://' + process.argv[2]);
  await p.waitForTimeout(300);
  await p.screenshot({ path: process.argv[3], omitBackground: true });
  await b.close();
})();
