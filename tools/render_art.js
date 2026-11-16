// Перетворює вихідні SVG каменів, бустерів і перешкод (art_src/glow) на PNG для гри: імпорт Godot не вміє розмиття.
// Запуск із кореня репозиторію: node tools/render_art.js (потрібен playwright).
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const src = 'art_src/glow/', out = 'assets/art/';
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 256, height: 256 }, deviceScaleFactor: 1 });
  const shot = async (n, svg, filter) => {
    await p.setContent('<html><body style="margin:0;background:transparent"><div id="d" style="width:256px;height:256px;filter:' + filter + '">' + svg + '</div></body></html>');
    await p.locator('#d').screenshot({ path: out + n + '.png', omitBackground: true });
  };
  // камені й бустери: яскравість 105%, насиченість 120%; тінь малює сама гра
  for (const n of ['piece_0','piece_1','piece_2','piece_3','bar','bar_v','bomb','star','shur']) {
    let svg = fs.readFileSync(src + n + '.svg', 'utf8');
    const before = svg.length;
    svg = svg.replace('<ellipse cx="50" cy="93" rx="30" ry="4.5" fill="#000" opacity=".4" filter="url(#b2)"/>', '');
    if (svg.length === before) throw new Error('no shadow ' + n);
    await shot(n, svg, 'brightness(1.05) saturate(1.2)');
  }
  // перешкоди: яскравість 89%
  for (const n of ['crate1','crate2','ice1','ice2','chain']) await shot(n, fs.readFileSync(src + n + '.svg', 'utf8'), 'brightness(0.89)');
  await b.close();
})();
