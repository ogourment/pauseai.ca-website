// CHAPTER-TORONTO-UI-01: read-only real-host regression, approved 2026-11-23.
const {chromium} = require('playwright');
const fs = require('node:fs/promises');
const assert = require('node:assert/strict');
(async () => {
  const base = process.env.TORONTO_BASE_URL;
  if (!base) throw new Error('Set TORONTO_BASE_URL to the integrated review host');
  const out = process.env.TORONTO_EVIDENCE_DIR || 'tmp/toronto-ui-feedback';
  await fs.mkdir(out, {recursive:true});
  const browser = await chromium.launch({headless:true});
  const results = [];
  try {
    for (const locale of ['en','fr']) for (const width of [390,1280]) {
      const context = await browser.newContext({viewport:{width,height:900}});
      const page = await context.newPage();
      const national = locale === 'fr' ? '/fr/faire-un-don' : '/en/donate';
      const geometry = async () => page.locator('#chapter-page-navigation').evaluate(nav => ({box: {x:nav.getBoundingClientRect().x,y:nav.getBoundingClientRect().y,width:nav.getBoundingClientRect().width,height:nav.getBoundingClientRect().height},links:[...nav.querySelectorAll('a')].map(a => ({text:a.textContent,top:a.getBoundingClientRect().top}))}));
      let homeGeometry;
      for (const slug of ['home','plan','governance','write-to-your-mp']) {
        const path = slug === 'home' ? '/groups/toronto' : `/groups/toronto/pages/${slug}`;
        await page.goto(`${base}${path}?locale=${locale}`, {waitUntil:'networkidle'});
        const nav = page.locator('#chapter-page-navigation');
        await nav.waitFor();
        assert.match(await nav.innerText(), /Toronto/);
        assert.equal(await nav.locator(`a[href="${national}"]`).count(),1);
        assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth),false);
        assert.equal(await page.locator('a[href*="stripe.com"], a[href*="manifund.org"]').count(),0);
        if (slug === 'home') homeGeometry = await geometry();
        if (slug === 'governance') {
          const rows = page.locator('.toronto-board-member');
          assert.ok(await rows.count() >= 3);
          const portraitSizes = [];
          for (const row of await rows.all()) {
            assert.equal(await row.locator('img').count(),1);
            assert.equal(await row.locator('h3').count(),1);
            assert.equal(await row.locator('img').evaluate(img => img.complete && img.naturalWidth > 0),true);
            assert.ok((await row.locator('div p').innerText()).trim().length > 0);
            const image = await row.locator('img').boundingBox();
            portraitSizes.push({width:image.width,height:image.height});
            const name = await row.locator('h3').boundingBox();
            assert.ok(image && name && name.x > image.x + image.width - 2);
          }
          for (const size of portraitSizes) {
            assert.ok(Math.abs(size.width - portraitSizes[0].width) <= 1);
            assert.ok(Math.abs(size.height - size.width) <= 1);
          }
          for (const role of ['Director of PauseAI UK','Founder of PauseAI Toronto','Founder and National Leader of PauseAI Canada']) assert.ok((await rows.allTextContents()).join(' ').includes(role));
        }
        await page.screenshot({path:`${out}/${slug}-${locale}-${width}.png`,fullPage:true});
        results.push({locale,width,slug,status:'passed'});
      }
      await page.goto(`${base}/groups/toronto?locale=${locale}`, {waitUntil:'networkidle'});
      await page.locator(`#chapter-page-navigation a[href="/groups/toronto/pages/write-to-your-mp?locale=${locale}"]`).click();
      await page.waitForLoadState('networkidle');
      const actionGeometry = await geometry();
      for (const dimension of ['x','y','width','height']) assert.ok(Math.abs(actionGeometry.box[dimension]-homeGeometry.box[dimension]) <= 1, `nav ${dimension} shifted`);
      assert.equal(actionGeometry.links.length, homeGeometry.links.length);
      actionGeometry.links.forEach((link,i) => {assert.equal(link.text,homeGeometry.links[i].text);assert.ok(Math.abs(link.top-homeGeometry.links[i].top)<=1,'nav link shifted');});
      results.push({locale,width,journey:'Home → Take action',homeGeometry,actionGeometry,status:'passed'});
      for (const fragment of ['monthly','once','one-off','donate']) {
        await page.goto(`${base}/groups/toronto/pages/donate?locale=${locale}#${fragment}`, {waitUntil:'networkidle'});
        assert.equal(new URL(page.url()).pathname,national);
        assert.equal(new URL(page.url()).hash, `#${fragment}`);
        await page.locator(`#${fragment}`).waitFor({state:'attached'});
        const arrival = await page.locator(`#${fragment}`).boundingBox();
        const headerBottom = await page.evaluate(() => Number.parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--header-bottom')) || 0);
        assert.ok(arrival && arrival.y >= headerBottom - 1 && arrival.y < 900, 'legacy bookmark hidden behind header');
        assert.equal(await page.locator('#toronto-giving-options').count(),0);
      }
      await context.close();
    }
    await fs.writeFile(`${out}/verification.json`,JSON.stringify({scenario:'CHAPTER-TORONTO-UI-01',base,role:'signed-out',completedAt:new Date().toISOString(),results},null,2));
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode=1; });
