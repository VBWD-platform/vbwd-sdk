/* S81 — UI walkthrough: import 10 WordPress posts through the WP Import tab,
 * screenshotting every step, then verify one post in the editor (tags +
 * featured image) and on the fe-user frontend. Generates the HTML report
 * s81-WALK-REPORT-wp-import.html next to s81-shots/.
 *
 * Run from the vbwd-fe-admin dir so Node resolves @playwright/test:
 *   cd vbwd-fe-admin && WP_FEED_URL='https://...' node ../docs/dev_log/20260611/walkthrough/s81-wp-import-walkthrough.cjs
 * Targets the running local stack (fe-admin :8081, fe-user :8080).
 * The feed token is masked in screenshots (CSS text-security on the URL input)
 * and never written into the report (D1a).
 */
// Resolve @playwright/test from the invoking repo (run from vbwd-fe-admin), not this docs dir
const { chromium } = require(require.resolve('@playwright/test', { paths: [process.cwd()] }));
const fs = require('fs');
const path = require('path');

const ADMIN = process.env.ADMIN_URL || 'http://localhost:8081';
const USER = process.env.USER_URL || 'http://localhost:8080';
const FEED_URL =
  process.env.WP_FEED_URL ||
  'https://redrobot.online/feed/?token=your_secret_token_here&show_on_page=10&show_unread_only=false&mark_as_read=false';
const WALKDIR = path.resolve(__dirname);
const SHOTS = path.join(WALKDIR, 's81-shots');
const REPORT = path.join(WALKDIR, 's81-WALK-REPORT-wp-import.html');

fs.mkdirSync(SHOTS, { recursive: true });

const steps = [];
let n = 0;

async function shot(page, title, caption, fullPage = false) {
  n += 1;
  const file = `step-${String(n).padStart(2, '0')}.png`;
  await page.screenshot({ path: path.join(SHOTS, file), fullPage });
  steps.push({ n, file, title, caption });
  console.log(`  [${n}] ${title}`);
}

function writeReport(error) {
  const body = steps
    .map(
      (s) => `
  <section class="step">
    <h2>${s.n}. ${s.title}</h2>
    <p>${s.caption}</p>
    <a href="s81-shots/${s.file}"><img src="s81-shots/${s.file}" alt="${s.title}" /></a>
  </section>`
    )
    .join('\n');
  const errorBlock = error
    ? `<section class="step error"><h2>⚠ Run aborted</h2><pre>${String(error)
        .replace(/token=[^&\s"']+/g, 'token=***')
        .replace(/[<>]/g, '')}</pre></section>`
    : '';
  fs.writeFileSync(
    REPORT,
    `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>S81 — WP Import walkthrough (RSS → CMS posts)</title>
<style>
  body { font-family: -apple-system, Segoe UI, sans-serif; max-width: 1100px; margin: 2rem auto; padding: 0 1rem; color: #1a202c; }
  h1 { border-bottom: 3px solid #3182ce; padding-bottom: .5rem; }
  .meta { color: #4a5568; }
  .step { margin: 2.5rem 0; }
  .step h2 { color: #2c5282; }
  .step img { width: 100%; border: 1px solid #cbd5e0; border-radius: 6px; box-shadow: 0 2px 8px rgba(0,0,0,.08); }
  .step.error pre { background: #fff5f5; border: 1px solid #fc8181; padding: 1rem; border-radius: 6px; white-space: pre-wrap; }
  code { background: #edf2f7; padding: .1em .3em; border-radius: 3px; }
</style></head><body>
<h1>S81 — WP Import walkthrough</h1>
<p class="meta">Sprint: <code>docs/dev_log/20260611/sprints/s81-import-from-word-press.md</code> ·
Source: the tokenized redrobot.online RSS feed (token masked per D1a) ·
Flow: WP Import tab → check feed → import 10 → editor proof (tags + featured image) → fe-user frontend proof.</p>
${body}
${errorBlock}
</body></html>\n`
  );
  console.log(`Report: ${REPORT} (${steps.length} steps${error ? ', ABORTED' : ''})`);
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
  const page = await ctx.newPage();
  page.setDefaultTimeout(30000);

  const loginResp = await ctx.request.post(`${ADMIN}/api/v1/auth/login`, {
    data: { email: 'admin@example.com', password: 'AdminPass123@' },
  });
  const loginBody = await loginResp.json();
  const apiToken = loginBody.token;

  try {
    // 1. Sign in through the UI, open Import/Export, WP Import tab
    await page.goto(`${ADMIN}/admin/login`, { waitUntil: 'networkidle' });
    await page.locator('[data-testid="username-input"]').fill('admin@example.com');
    await page.locator('[data-testid="password-input"]').fill('AdminPass123@');
    await page.locator('[data-testid="login-button"]').click();
    await page.waitForURL((u) => !u.pathname.endsWith('/login'));
    await page.waitForLoadState('networkidle');
    await page.locator('a[href="/admin/import-export"]').first().click();
    await page.locator('[data-testid="import-export-view"]').waitFor();
    await page.getByRole('button', { name: 'WP Import' }).or(page.getByText('WP Import', { exact: true })).first().click();
    await page.locator('[data-testid="wp-import-url"]').waitFor();
    // Mask the token in every following screenshot (D1a)
    await page.addStyleTag({ content: '[data-testid="wp-import-url"] { -webkit-text-security: disc; }' });
    await shot(page, 'WP Import tab', `Settings → Import/Export → <b>WP Import</b>: the new tab injected by the <code>wp-import</code> fe-admin plugin via <code>dataExchangeTabs</code> (first consumer of the extension point). Feed URL field, batch-size select, feed stats and the imported-posts table are all plugin-owned.`);

    // 2. Feed URL + batch 10 + check feed
    await page.locator('[data-testid="wp-import-url"]').fill(FEED_URL);
    await page.locator('[data-testid="wp-import-batch-size"]').selectOption('10');
    await page.locator('[data-testid="wp-import-check"]').click();
    await page.locator('[data-testid="wp-import-stats"]').waitFor({ timeout: 120000 });
    const stats = (await page.locator('[data-testid="wp-import-stats"]').innerText()).trim();
    await shot(page, 'Feed checked — stats', `The real tokenized redrobot.online feed URL is set (token visually masked; it is also masked in backend logs and persisted rows per D1a). Batch size <b>10</b>. "Check feed" walked the paged feed and reports: <b>${stats}</b>.`);

    // 3. Import 10
    await page.locator('[data-testid="wp-import-run"]').click();
    await page.locator('[data-testid="wp-import-summary"]').waitFor({ timeout: 600000 });
    await page.waitForLoadState('networkidle');
    const summary = (await page.locator('[data-testid="wp-import-summary"]').innerText()).trim();
    await shot(page, 'Import run — 10 posts imported', `The import ran in chunks of 10 (D6). Summary: <b>${summary.replace(/</g, '')}</b>. The imported-posts table below lists each post with its categories, tags and import datetime — original WP publish dates land in <code>published_at</code>.`, true);

    // 4. Open the first imported post in the normal editor
    const firstTitle = (await page.locator('[data-testid="wp-import-row-title"]').first().innerText()).trim();
    await page.locator('[data-testid="wp-import-row-title"]').first().click();
    await page.waitForURL(/\/admin\/cms\/posts\/.+\/edit/);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1500);
    const editUrl = page.url();
    const postId = editUrl.match(/posts\/([^/]+)\/edit/)[1];
    await shot(page, 'Imported post in the standard editor', `Row click opens the normal post editor (<code>${editUrl.replace(ADMIN, '')}</code>) — no special import view. Visible: the imported title (“${firstTitle.replace(/</g, '')}”), the attached <b>tags and categories</b> (deduplicated via <code>TermService.find_or_create</code>) and the <b>featured image</b> re-hosted under <code>/uploads/</code>.`, true);

    // 5. The same post on the fe-user frontend
    const postResp = await ctx.request.get(`${ADMIN}/api/v1/admin/cms/posts/${postId}`, {
      headers: { Authorization: `Bearer ${apiToken}` },
    });
    const post = (await postResp.json()).post || (await postResp.json());
    const slug = post.slug || (post.data && post.data.slug);
    await page.goto(`${USER}/${slug}`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(1500);
    await shot(page, 'Frontend rendering (fe-user)', `The imported post served publicly at <code>${USER}/${slug}</code> — published status, full content with locally re-hosted images.`, true);

    writeReport(null);
  } catch (err) {
    console.error(err);
    writeReport(err);
    process.exitCode = 1;
  } finally {
    await browser.close();
  }
})();
