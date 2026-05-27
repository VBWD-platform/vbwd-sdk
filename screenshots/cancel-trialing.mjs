import { chromium } from 'playwright';

const HOST = 'http://host.docker.internal';
const FE_USER = `${HOST}:8080`;
const FE_ADMIN = `${HOST}:8081`;

async function seedAuth(page, baseUrl, email, password) {
  const resp = await page.request.post(`${HOST}:5000/api/v1/auth/login`, {
    data: { email, password },
    headers: { 'Content-Type': 'application/json' },
  });
  const body = await resp.json();
  await page.goto(`${baseUrl}/`, { waitUntil: 'domcontentloaded' });
  await page.evaluate((c) => {
    localStorage.setItem('auth_token', c.token);
    localStorage.setItem('user_id', c.user.id);
    localStorage.setItem(
      'user_permissions',
      JSON.stringify(c.user.user_permissions || c.user.permissions || ['*']),
    );
    localStorage.setItem('user_email', c.user.email);
    localStorage.setItem('admin_token', c.token);
    localStorage.setItem('admin_token_user', JSON.stringify(c.user));
  }, body);
}

(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1400 } });
  const page = await ctx.newPage();
  page.on('pageerror', (err) => console.log('  [pageerror]', err.message));

  await seedAuth(page, FE_USER, 'test@example.com', 'TestPass123@');
  await page.goto(`${FE_USER}/dashboard/subscription`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(1500);
  await page.screenshot({ path: '/work/screenshots/user-subscriptions-cancel.png', fullPage: true });
  console.log('  ✓ user-subscriptions-cancel.png');

  await ctx.clearCookies();
  await page.evaluate(() => localStorage.clear());
  await seedAuth(page, FE_ADMIN, 'admin@example.com', 'AdminPass123@');
  // Look up the first TRIALING subscription via the user API (admin filter
  // doesn't accept ``trialing`` as a param value), then navigate to its admin
  // detail page.
  const trialingResp = await page.request.get(
    `${HOST}:5000/api/v1/user/subscriptions/active-all`,
    { headers: { Authorization: `Bearer ${(await page.evaluate(() => localStorage.getItem('admin_token')))}` } },
  );
  const trialingBody = await trialingResp.json().catch(() => ({}));
  const trialingId =
    (trialingBody.subscriptions || []).find((s) => (s.status || '').toUpperCase() === 'TRIALING')?.id ||
    '5b180d52-3e0d-4af5-92e2-32abec8f78b8';
  if (trialingId) {
    await page.goto(`${FE_ADMIN}/admin/subscriptions/${trialingId}`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(1500);
    await page.screenshot({
      path: '/work/screenshots/admin-subscription-trialing.png',
      fullPage: true,
    });
    console.log(`  ✓ admin-subscription-trialing.png (${trialingId})`);
  } else {
    console.log('  ! no TRIALING subscription found in admin list');
  }

  await browser.close();
})();
