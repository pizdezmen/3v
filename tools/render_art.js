// Перетворює вихідні SVG каменів і бустерів (art_src/glow) на PNG для гри: імпорт Godot не вміє розмиття.
// Запуск із кореня репозиторію: node tools/render_art.js (потрібен playwright).
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const src = 'art_src/glow/', out = 'assets/art/';
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 256, height: 256 }, deviceScaleFactor: 1 });
  for (const n of ['piece_0','piece_1','piece_2','piece_3','bar','bar_v','bomb','star','shur']) {
    let svg = fs.readFileSync(src + n + '.svg', 'utf8');
    const before = svg.length;
    svg = svg.replace('<ellipse cx="50" cy="93" rx="30" ry="4.5" fill="#000" opacity=".4" filter="url(#b2)"/>', '');
    if (svg.length === before) throw new Error('no shadow ' + n);
    await p.setContent('<html><body style="margin:0;background:transparent"><div id="d" style="width:256px;height:256px;filter:brightness(1.05) saturate(1.2)">' + svg + '</div></body></html>');
    await p.locator('#d').screenshot({ path: out + n + '.png', omitBackground: true });
  }
  await b.close();
})();
