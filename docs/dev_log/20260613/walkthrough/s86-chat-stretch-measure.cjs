/* S86 — inline chat-widget STRETCH bug reproduction / verification.
 * Opens /home1 (meinchat-bot-widget placed inline), starts a public guest chat,
 * sends several messages, and measures the widget bounding height after each
 * send to show whether it GROWS (bug) or stays BOUNDED (fixed).
 *
 *   cd vbwd-fe-user && node ../docs/dev_log/20260613/walkthrough/s86-chat-stretch-measure.cjs <before|after>
 */
const { chromium } = require(require.resolve('@playwright/test', { paths: [process.cwd()] }));
const path = require('path');

const PHASE = process.argv[2] === 'after' ? 'after' : 'before';
const USER = process.env.USER_URL || 'http://localhost:8080';
const PAGE_SLUG = process.env.CHAT_PAGE_SLUG || 'home1';
const SHOTS = path.resolve(__dirname, 's86-chat-stretch-shots');

const WIDGET = '[data-testid="meinchat-chat-widget"]';

async function widgetHeight(page) {
  return page.evaluate((sel) => {
    const el = document.querySelector(sel);
    return el ? Math.round(el.getBoundingClientRect().height) : -1;
  }, WIDGET);
}

async function messagesScroll(page) {
  return page.evaluate(() => {
    const el = document.querySelector('[data-testid="meinchat-widget-messages"]');
    if (!el) return null;
    return { scrollHeight: el.scrollHeight, clientHeight: el.clientHeight, scrolls: el.scrollHeight > el.clientHeight };
  });
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  page.setDefaultTimeout(30000);
  const consoleErrors = [];
  page.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(m.text()); });

  const viewportH = 900;
  const cap70vh = Math.round(viewportH * 0.7);
  const heights = [];

  try {
    await page.goto(`${USER}/${PAGE_SLUG}`, { waitUntil: 'networkidle' });
    await page.locator(WIDGET).waitFor();
    await page.locator('[data-testid="meinchat-widget-start-form"]').waitFor();
    await page.waitForTimeout(600);

    await page.locator('[data-testid="meinchat-widget-name-input"]').fill('StretchTester');
    await page.locator('[data-testid="meinchat-widget-start"]').click();
    await page.locator('[data-testid="meinchat-widget-room"]').waitFor();
    await page.waitForTimeout(1000);

    const h0 = await widgetHeight(page);
    heights.push(h0);
    console.log(`[${PHASE}] after start: widget height = ${h0}px`);
    await page.screenshot({ path: path.join(SHOTS, `${PHASE}-00-start.png`), fullPage: true });

    for (let i = 1; i <= 8; i += 1) {
      await page.locator('[data-testid="composer-input"]').fill(
        `Tell me much more about everything you can possibly do please number ${i}`,
      );
      await page.locator('[data-testid="composer-send"]').click();
      await page.waitForTimeout(2600);
      const h = await widgetHeight(page);
      heights.push(h);
      const sc = await messagesScroll(page);
      console.log(`[${PHASE}] after msg ${i}: widget height = ${h}px | messages scrolls=${sc && sc.scrolls} (${sc && sc.scrollHeight}/${sc && sc.clientHeight})`);
    }

    await page.screenshot({ path: path.join(SHOTS, `${PHASE}-01-after-8-msgs.png`), fullPage: true });
    // a viewport-only shot too, to show the box bound on screen
    await page.locator(WIDGET).screenshot({ path: path.join(SHOTS, `${PHASE}-02-widget.png`) }).catch(() => {});

    const first = heights[0];
    const last = heights[heights.length - 1];
    const grew = last > first + 20;
    const sc = await messagesScroll(page);
    console.log(`\n[${PHASE}] SUMMARY heights: ${heights.join(' -> ')}`);
    console.log(`[${PHASE}] first=${first}px last=${last}px grew=${grew} | 70vh cap=${cap70vh}px | bounded(last<=cap+5)=${last <= cap70vh + 5}`);
    console.log(`[${PHASE}] messages scrolls=${sc && sc.scrolls} (scrollHeight ${sc && sc.scrollHeight} > clientHeight ${sc && sc.clientHeight})`);
    console.log(`[${PHASE}] consoleErrors=${consoleErrors.length}`);
    if (consoleErrors.length) console.log(consoleErrors.slice(0, 5).join('\n'));
  } catch (err) {
    console.error('ABORTED:', err);
    await page.screenshot({ path: path.join(SHOTS, `${PHASE}-ERROR.png`), fullPage: true }).catch(() => {});
    process.exitCode = 1;
  } finally {
    await browser.close();
  }
})();
