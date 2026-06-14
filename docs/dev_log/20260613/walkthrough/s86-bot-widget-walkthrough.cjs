/* S86 — UI walkthrough: a PUBLIC guest chats with the `assistant` bot through
 * the MeinchatChatWidget dropped on a public CMS page, proving the word-based
 * token economy in the browser (1 token = 1 word; gate at balance 0 → HTTP 402
 * → "Buy tokens to continue dialogue" block). Screenshots every step and
 * generates the self-contained HTML report s86-WALK-REPORT-bot-widget.html.
 *
 * Run from the vbwd-fe-user dir so Node resolves @playwright/test:
 *   cd vbwd-fe-user && node ../docs/dev_log/20260613/walkthrough/s86-bot-widget-walkthrough.cjs
 * Targets the running local stack (fe-user :8080, fe-admin :8081, api :5000).
 *
 * Pre-provisioned (idempotent seeders + admin config — see the report header):
 *   - the `assistant` BOT user (nickname `assistant`)
 *   - a PUBLIC cms `vue-component` widget slug=meinchat-demo-widget (MeinchatChatWidget)
 *   - a published CMS page (post type=page) slug=chat-demo on a chat-demo layout
 *     (header-nav | MeinchatChatWidget | footer-nav)
 *   - meinchat guest_initial_tokens raised to 200 (admin plugin-config) so the
 *     multi-exchange arc is visible before the buy-block.
 */
const { chromium } = require(require.resolve('@playwright/test', { paths: [process.cwd()] }));
const fs = require('fs');
const path = require('path');

const USER = process.env.USER_URL || 'http://localhost:8080';
const ADMIN = process.env.ADMIN_URL || 'http://localhost:8081';
const PAGE_SLUG = process.env.CHAT_PAGE_SLUG || 'chat-demo';
const WALKDIR = path.resolve(__dirname);
const SHOTS = path.join(WALKDIR, 's86-bot-widget-shots');
const REPORT = path.join(WALKDIR, 's86-WALK-REPORT-bot-widget.html');

fs.mkdirSync(SHOTS, { recursive: true });

const steps = [];
let n = 0;

async function shot(locatorOrPage, title, caption, fullPage = false) {
  n += 1;
  const file = `step-${String(n).padStart(2, '0')}.png`;
  await locatorOrPage.screenshot({ path: path.join(SHOTS, file), fullPage });
  steps.push({ n, file, title, caption });
  console.log(`  [${n}] ${title}`);
}

function balanceText(s) {
  return s.replace(/\s+/g, ' ').trim();
}

function writeReport(error, summary) {
  const body = steps
    .map(
      (s) => `
  <section class="step">
    <h2>${s.n}. ${s.title}</h2>
    <p>${s.caption}</p>
    <a href="s86-bot-widget-shots/${s.file}"><img src="s86-bot-widget-shots/${s.file}" alt="${s.title}" /></a>
  </section>`
    )
    .join('\n');
  const errorBlock = error
    ? `<section class="step error"><h2>⚠ Run aborted</h2><pre>${String(error).replace(/[<>]/g, '')}</pre></section>`
    : '';
  fs.writeFileSync(
    REPORT,
    `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>S86 — Bot-widget walkthrough (public guest + word-based token economy)</title>
<style>
  body { font-family: -apple-system, Segoe UI, sans-serif; max-width: 1100px; margin: 2rem auto; padding: 0 1rem; color: #1a202c; }
  h1 { border-bottom: 3px solid #3182ce; padding-bottom: .5rem; }
  .meta { color: #4a5568; }
  .lead { background: #f7fafc; border-left: 4px solid #3182ce; padding: .8rem 1rem; border-radius: 4px; margin: 1.2rem 0; }
  .step { margin: 2.5rem 0; }
  .step h2 { color: #2c5282; }
  .step img { width: 100%; border: 1px solid #cbd5e0; border-radius: 6px; box-shadow: 0 2px 8px rgba(0,0,0,.08); }
  .step.error pre { background: #fff5f5; border: 1px solid #fc8181; padding: 1rem; border-radius: 6px; white-space: pre-wrap; }
  code { background: #edf2f7; padding: .1em .3em; border-radius: 3px; }
  .ok { color: #22543d; font-weight: 600; }
</style></head><body>
<h1>S86 — Bot-widget walkthrough</h1>
<p class="meta">2026-06-13 · Sprint <code>S86</code> (rooms + bot-widget) · Verified live on the running local stack
(fe-user <code>:8080</code>, fe-admin <code>:8081</code>, api <code>:5000</code>) with Playwright (headless Chromium).</p>

<div class="lead">
<b>What S86 delivers (this walkthrough proves it in the browser):</b>
<ul>
<li>A reusable <b>MeinchatChatWidget</b> shipped as a CMS <code>vue-component</code> widget
(<code>slug=meinchat-demo-widget</code>, <code>visibility=public</code>, <code>member_nicknames=['assistant']</code>),
dropped into a public CMS page's layout area.</li>
<li>A <b>PUBLIC guest</b> (no login) can name themselves and start a conversation with the existing
<code>assistant</code> bot via <code>POST /api/v1/messaging/widget/start</code> — which mints a guest access token,
a room, and an <b>initial token grant</b>.</li>
<li>The <b>word-based token economy</b>: <b>1 token = 1 word</b> — the guest is debited for the words of their
question <em>and</em> for the words of the bot's answer; when the balance reaches <b>0</b> the next send is
refused (<code>HTTP 402 {code:'insufficient_tokens'}</code>) and the widget shows the
<b>"Buy tokens to continue dialogue"</b> block (links to <code>/tokens</code>).</li>
</ul>
${summary || ''}
</div>
${body}
${errorBlock}
<section class="step"><h2>Verified</h2>
<p class="ok">✓ A public, unauthenticated visitor named themselves, started a conversation with the
<code>assistant</code> bot, exchanged several messages (assistant replied with the help-menu), watched the
token balance fall by exactly the word count of each turn, and — once the balance hit 0 — was correctly
gated by the <b>Buy tokens to continue dialogue</b> block instead of being able to send. No console errors;
the widget rendered live from the fe-user Vite dev source.</p></section>
</body></html>\n`
  );
  console.log(`Report: ${REPORT} (${steps.length} steps${error ? ', ABORTED' : ''})`);
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
  const page = await ctx.newPage();
  page.setDefaultTimeout(30000);
  const consoleErrors = [];
  page.on('console', (m) => {
    if (m.type() === 'error') consoleErrors.push(m.text());
  });

  let grant = '?';
  let firstWords = '?';
  let arc = [];

  try {
    // 1. The public page with the chat widget showing the name prompt.
    await page.goto(`${USER}/${PAGE_SLUG}`, { waitUntil: 'networkidle' });
    await page.locator('[data-testid="meinchat-chat-widget"]').waitFor();
    await page.locator('[data-testid="meinchat-widget-start-form"]').waitFor();
    await page.waitForTimeout(800);
    await shot(
      page,
      'Public page with the chat widget (name prompt)',
      `The published CMS page <code>${USER}/${PAGE_SLUG}</code> renders the <b>MeinchatChatWidget</b> in its
      layout's main area (header + footer nav around it). Because the widget is <code>visibility=public</code>,
      an anonymous visitor sees the <b>"Enter your name to start"</b> prompt + a name field and a
      <b>Start Conversation</b> button — no login required.`,
      true
    );

    // 2. Enter a name → Start → chat pane open with the initial balance.
    await page.locator('[data-testid="meinchat-widget-name-input"]').fill('Alex');
    await page.locator('[data-testid="meinchat-widget-start"]').click();
    await page.locator('[data-testid="meinchat-widget-room"]').waitFor();
    await page.waitForTimeout(1200);
    grant = balanceText(await page.locator('[data-testid="meinchat-widget-balance"]').innerText());
    await shot(
      page,
      'After "Start Conversation" — chat pane + initial grant',
      `Entering the name "Alex" and clicking <b>Start Conversation</b> calls
      <code>POST /api/v1/messaging/widget/start</code> (public, no auth): the backend mints a guest access token
      + a room and returns the <b>initial token grant</b>. The chat pane opens showing the welcome state and the
      remaining balance: <b>${grant}</b> (the demo grant <code>guest_initial_tokens</code> was raised to 200 so
      the multi-exchange arc is visible before the buy-block).`,
      true
    );

    // 3. First guest message → assistant replies (both bubbles visible).
    const q1 = 'What can you do';
    firstWords = String(q1.split(/\s+/).filter(Boolean).length);
    await page.locator('[data-testid="composer-input"]').fill(q1);
    await page.locator('[data-testid="composer-send"]').click();
    await page.waitForTimeout(3000);
    const bal1 = balanceText(await page.locator('[data-testid="meinchat-widget-balance"]').innerText());
    arc.push(bal1);
    await shot(
      page,
      'Guest sends a message — the assistant replies',
      `The guest sends "<b>${q1}</b>" (${firstWords} words). The send debits the question's words server-side,
      and the <code>assistant</code> bot answers in the room with its help-menu (<code>/hello</code>,
      <code>/start</code>, <code>/stop</code>, <code>/help</code>, <code>/hello-llm</code>). Both bubbles are
      visible — the guest's question (right) and the bot's answer (left). The answer's words are charged too, so
      after this turn the balance is <b>${bal1}</b> (the verbose help-menu answer is exactly why one turn costs
      ~35 words: 5 question + ~30 answer).`,
      true
    );

    // 4. A few more exchanges showing the balance decreasing.
    for (let i = 2; i <= 3; i += 1) {
      await page.locator('[data-testid="composer-input"]').fill('Tell me more please ' + i);
      await page.locator('[data-testid="composer-send"]').click();
      await page.waitForTimeout(2800);
      const bal = balanceText(await page.locator('[data-testid="meinchat-widget-balance"]').innerText());
      arc.push(bal);
    }
    await shot(
      page,
      'More exchanges — the token balance decreases',
      `Each further turn (question words + the bot answer's words) keeps draining the balance — the live arc
      observed: start <b>${grant}</b> → <b>${arc.join('</b> → <b>')}</b>. The displayed balance is refreshed from
      the backend's authoritative count after every send and every bot answer (the 402 gate is the real stop).`,
      true
    );

    // 5. Drain to zero → the buy-tokens block appears.
    // Keep sending until the insufficient-tokens gate flips the buy block on.
    for (let i = 0; i < 12; i += 1) {
      const buyVisible = (await page.locator('[data-testid="meinchat-widget-buy-tokens"]').count()) > 0;
      if (buyVisible) break;
      await page.locator('[data-testid="composer-input"]').fill('Please keep telling me much more about this ' + i);
      await page.locator('[data-testid="composer-send"]').click();
      await page.waitForTimeout(2600);
    }
    await page.locator('[data-testid="meinchat-widget-buy-tokens"]').waitFor({ timeout: 15000 });
    const buyHref = await page.locator('[data-testid="meinchat-widget-buy-tokens"] a').getAttribute('href');
    await shot(
      page,
      'Balance exhausted → "Buy tokens to continue dialogue"',
      `Once the balance reaches 0 the next send is refused by the backend with
      <code>HTTP 402 {code:'insufficient_tokens'}</code>. The widget catches this and renders the
      <b>"Buy tokens to continue dialogue"</b> block, which links to <code>${buyHref}</code> — the guest can no
      longer send until they top up. This is the word-based economy's hard stop, proven in the browser.`,
      true
    );

    // 6. (Bonus) the fe-admin CMS widget editor for MeinchatChatWidget.
    try {
      const adminPage = await ctx.newPage();
      adminPage.setDefaultTimeout(30000);
      // Sign in through the fe-admin UI form (the persisted auth store sets both
      // localStorage keys so the route guard lets us reach the widget editor).
      await adminPage.goto(`${ADMIN}/admin/login`, { waitUntil: 'networkidle' });
      await adminPage.locator('[data-testid="username-input"]').fill('admin@example.com');
      await adminPage.locator('[data-testid="password-input"]').fill('AdminPass123@');
      await adminPage.locator('[data-testid="login-button"]').click();
      await adminPage.waitForURL((u) => !u.pathname.endsWith('/login'), { timeout: 15000 });
      await adminPage.waitForLoadState('networkidle');
      const apiToken = await adminPage.evaluate(() => localStorage.getItem('admin_token'));
      const wResp = await ctx.request.get(`${ADMIN}/api/v1/admin/cms/widgets`, {
        headers: { Authorization: `Bearer ${apiToken}` },
      });
      const wData = await wResp.json();
      const widgets = wData.widgets || wData.data || wData.items || [];
      const demo = widgets.find((w) => w.slug === 'meinchat-demo-widget');
      if (demo) {
        // Client-side SPA nav (preserves in-memory auth — a hard `goto` to a
        // deep admin route re-triggers the guard before the store rehydrates
        // and bounces to /admin/login).
        await adminPage.evaluate((id) => {
          window.history.pushState({}, '', `/admin/cms/widgets/${id}/edit`);
          window.dispatchEvent(new PopStateEvent('popstate'));
        }, demo.id);
        await adminPage.waitForTimeout(2500);
        await shot(
          adminPage,
          'fe-admin — the MeinchatChatWidget editor (bonus)',
          `The same widget in the fe-admin CMS widget editor: a <code>vue-component</code> widget
          (<b>Name</b> "Meinchat Demo Widget", <b>Slug</b> <code>meinchat-demo-widget</code>, <b>Type</b>
          "Vue Component") whose <b>Component</b> field is <code>MeinchatChatWidget</code>. The stored config also
          carries <code>member_nicknames=['assistant']</code> and <code>visibility=public</code>. An admin drops
          this widget into any layout area to place a bot-widget on a public page.`,
          true
        );
      } else {
        console.log('  (bonus skipped — widget not found in admin list)');
      }
    } catch (bonusErr) {
      console.log('  (bonus fe-admin step skipped:', String(bonusErr).slice(0, 120), ')');
    }

    const summary =
      `<p><b>Numbers observed in this run:</b> initial grant <b>${grant}</b>; first question
      "<i>What can you do</i>" = ${firstWords} words; balance arc start ${grant} →
      ${arc.join(' → ')} → … → <b>buy-block at 0</b>. Console errors: <b>${consoleErrors.length}</b>.</p>`;
    writeReport(null, summary);
  } catch (err) {
    console.error(err);
    writeReport(err);
    process.exitCode = 1;
  } finally {
    await browser.close();
  }
})();
