/**
 * Capture screenshots of the URLs the user listed.
 * Run inside the official mcr.microsoft.com/playwright image (it ships with
 * Chromium + system libraries pre-installed — our Alpine dev container can't).
 */
import { chromium } from 'playwright';
import { writeFileSync } from 'fs';

const HOST = process.env.HOST_INTERNAL || 'http://host.docker.internal';
const FE_USER = `${HOST}:8080`;
const FE_ADMIN = `${HOST}:8081`;

const TARGETS = [
  { label: 'user-zero-price-c3841232', url: `${FE_USER}/dashboard/invoice/c3841232-f991-4c2d-ba2e-9e35b6f20bbe`, auth: 'user' },
  { label: 'user-tokens-a089c098',     url: `${FE_USER}/dashboard/invoice/a089c098-3b95-4e84-8efa-8fa10065da3c`, auth: 'user' },
  { label: 'admin-tokens-a089c098',    url: `${FE_ADMIN}/admin/invoices/a089c098-3b95-4e84-8efa-8fa10065da3c`,  auth: 'admin' },
  { label: 'admin-stripe-989d2831',    url: `${FE_ADMIN}/admin/invoices/989d2831-bb8a-4e82-b56d-0c49750abff9`,  auth: 'admin' },
  // Public checkout — to verify the Pay button label override
  { label: 'user-checkout-token',      url: `${FE_USER}/checkout?tarif_plan_id=pro`, auth: 'user', selectToken: true },
];

async function loginViaAuthApi(page, baseUrl, email, password) {
  const apiHost = `${HOST}:5000`;
  const resp = await page.request.post(`${apiHost}/api/v1/auth/login`, {
    data: { email, password },
    headers: { 'Content-Type': 'application/json' },
  });
  if (!resp.ok()) throw new Error(`login ${email}: ${resp.status()} ${await resp.text()}`);
  const body = await resp.json();

  await page.goto(`${baseUrl}/`, { waitUntil: 'domcontentloaded' });
  await page.evaluate((c) => {
    // fe-user keys
    localStorage.setItem('auth_token', c.token);
    localStorage.setItem('user_id', c.user.id);
    localStorage.setItem(
      'user_permissions',
      JSON.stringify(c.user.user_permissions || c.user.permissions || ['*']),
    );
    localStorage.setItem('user_email', c.user.email);
    // fe-admin keys
    localStorage.setItem('admin_token', c.token);
    localStorage.setItem('admin_token_user', JSON.stringify(c.user));
    // generic
    localStorage.setItem('token', c.token);
    localStorage.setItem('user', JSON.stringify(c.user));
  }, body);
}

(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1100 } });
  const page = await ctx.newPage();
  page.on('pageerror', (err) => console.log('  [pageerror]', err.message));

  // USER targets
  await loginViaAuthApi(page, FE_USER, 'test@example.com', 'TestPass123@');
  for (const target of TARGETS.filter((t) => t.auth === 'user')) {
    await page.goto(target.url, { waitUntil: 'networkidle' });
    await page.waitForTimeout(1200);
    if (target.selectToken) {
      // Wait for the payment-methods list, then click the Token balance row.
      const tokenRadio = page.locator('[data-testid="payment-method-token_balance"]').first();
      if (await tokenRadio.count()) {
        await tokenRadio.click().catch(() => {});
        await page.waitForTimeout(1500);
      }
    }
    const path = `/work/screenshots/${target.label}.png`;
    await page.screenshot({ path, fullPage: true });
    console.log(`  ✓ ${target.label} -> ${path}`);
  }

  // ADMIN targets
  await ctx.clearCookies();
  await page.evaluate(() => localStorage.clear());
  await loginViaAuthApi(page, FE_ADMIN, 'admin@example.com', 'AdminPass123@');
  for (const target of TARGETS.filter((t) => t.auth === 'admin')) {
    await page.goto(target.url, { waitUntil: 'networkidle' });
    await page.waitForTimeout(1200);
    const path = `/work/screenshots/${target.label}.png`;
    await page.screenshot({ path, fullPage: true });
    console.log(`  ✓ ${target.label} -> ${path}`);
  }

  await browser.close();
  writeFileSync('/work/screenshots/README.txt', `Captured ${TARGETS.length} screenshots at ${new Date().toISOString()}\n`);
})();
