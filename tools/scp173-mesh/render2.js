const { chromium } = require('playwright'); const fs = require('fs');
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const p = await b.newPage({ viewport: { width: 1200, height: 750 }, deviceScaleFactor: 2 });
  p.on('pageerror', e => console.log('err:', e.message));
  await p.setContent(`<html><body style="margin:0;background:#000"></body></html>`);
  await p.addScriptTag({ path: 'node_modules/three/build/three.min.js' });
  await p.addScriptTag({ path: 'scene2.js' });
  await p.waitForFunction('window.DONE', null, { timeout: 60000 });
  console.log('tris', await p.evaluate('window.TRIS'));
  fs.writeFileSync(process.argv[3], await p.evaluate('window.OBJ'));
  await p.evaluate(() => {
    const d = document.createElement('div');
    d.innerHTML = '<div style="position:absolute;left:16px;top:12px;font:600 18px monospace;color:#ddd">SCP-173 v2</div><div style="position:absolute;left:616px;top:12px;font:600 18px monospace;color:#ddd">GROS PLAN VISAGE</div><div style="position:absolute;left:599px;top:0;width:2px;height:750px;background:#000"></div>';
    document.body.appendChild(d);
  });
  await p.screenshot({ path: process.argv[2] });
  await b.close();
})();
