// Run: node --test test/javascript/donation_tracking_test.cjs
// Execute the shipped hook in a real browser; intercept the external destination.
const {test} = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const {createRequire} = require('node:module')
const {resolve} = require('node:path')
const {chromium} = createRequire(resolve('assets/package.json'))('playwright')
const layouts = fs.readFileSync('lib/pauseai_ca_web/components/layouts.ex', 'utf8')
const hook = layouts.match(/name="\.TrackOutbound">\s*export default ([\s\S]*?)\s*<\/script>/)[1]
const locationSource = fs.readFileSync('assets/js/public_analytics_location.js', 'utf8').replace('export ', '')
const signupSource = fs.readFileSync('assets/js/signup_analytics.js', 'utf8').replace(/^import .*\n/, '').replaceAll('export ', '')

test('donation new-tab tracking preserves navigation, consent and public-only payloads', async () => {
  const browser = await chromium.launch({headless: true})
  try {
    for (const [path, consent, destination] of [['/en/donate', 'granted', 'manifund'], ['/fr/faire-un-don', 'refused', 'manifund'], ['/en/donate', 'granted', 'brochure'], ['/fr/faire-un-don', 'refused', 'brochure']]) {
      const context = await browser.newContext()
      const posts = []
      const external = []
      await context.route('**/*', async route => {
        const request = route.request()
        if (request.url().startsWith('https://manifund.org/') || request.url().startsWith('https://drive.google.com/')) {
          external.push(request.url())
          await route.fulfill({body: 'Intercepted synthetic donation destination'})
        } else if (request.method() === 'POST') {
          posts.push({url: request.url(), headers: request.headers()})
          await route.fulfill({status: 204})
        } else {
          await route.fulfill({contentType: 'text/html', body: '<meta name="csrf-token" content="synthetic-csrf"><a id="donate" href="https://manifund.org/projects/synthetic" target="_blank" rel="noopener noreferrer" data-donation="manifund">Donate</a>'})
        }
      })
      const page = await context.newPage()
      await page.goto(`http://donation.test${path}?email=secret%40example.org&token=private#private`)
      await page.evaluate(({hook, locationSource, signupSource, consent, destination}) => {
        localStorage.setItem('pauseai-ca:analytics-consent', consent)
        document.querySelector('#donate').dataset.donation = destination
        if (destination === 'brochure') document.querySelector('#donate').href = 'https://drive.google.com/file/d/1AzvdAml-q0DAWhhSu-Q7K5RiTvFObFXu/view'
        window.calls = []
        window.gtag = (...args) => window.calls.push(args)
        window.eval(locationSource + '\n' + signupSource)
        window.eval(`(${hook}).mounted.call({el: document.querySelector('#donate')})`)
      }, {hook, locationSource, signupSource, consent, destination})
      const popupPromise = page.waitForEvent('popup')
      await page.locator('#donate').click()
      const popup = await popupPromise
      await popup.waitForLoadState()
      await page.waitForFunction(destination => performance.getEntriesByType('resource').some(r => r.name.endsWith(`/engagement/donation-links/${destination}`)), destination)
      assert.equal(posts.length, 1)
      assert.equal(posts[0].headers['x-csrf-token'], 'synthetic-csrf')
      assert.equal(external.length, 1)
      assert.equal(await popup.evaluate(() => window.opener), null)
      const calls = await page.evaluate(() => window.calls)
      assert.deepEqual(calls, consent === 'granted' ? [['event', destination === 'brochure' ? 'brochure_opened' : 'donation_link_opened', {
        destination, page_location: `http://donation.test${path}`, page_referrer: 'http://donation.test'
      }]] : [])
      assert.equal(await page.evaluate(() => window.pauseaiSignupAnalytics.publicPage('/users/settings')), false)
      assert.equal(await page.evaluate(() => window.pauseaiSignupAnalytics.publicPage('/fr/faire-un-don')), true)
      // Unknown attributes must create neither first-party nor GA signals.
      await page.evaluate(() => {
        const link = document.querySelector('#donate')
        link.dataset.donation = 'unknown'
        link.dispatchEvent(new MouseEvent('click'))
      })
      assert.equal(posts.length, 1)
      assert.deepEqual(await page.evaluate(() => window.calls), calls)
      // Middle-click uses the same signal without cancelling native navigation.
      assert.equal(await page.evaluate(destination => {
        const link = document.querySelector('#donate')
        link.dataset.donation = destination
        return link.dispatchEvent(new MouseEvent('auxclick', {button: 1, cancelable: true}))
      }, destination), true)
      await context.close()
    }
  } finally { await browser.close() }
})
