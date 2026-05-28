import { chromium } from 'playwright';
const HOST = 'http://host.docker.internal';
const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1440, height: 1400 } });
const page = await ctx.newPage();
page.on('pageerror', (err) => console.log('  [pageerror]', err.message));
const auth = await page.request.post(HOST + ':5000/api/v1/auth/login', {
  data: { email: 'test@example.com', password: 'TestPass123@' },
  headers: { 'Content-Type': 'application/json' },
});
const body = await auth.json();
await page.goto(HOST + ':8080/');
await page.evaluate((c) => {
  localStorage.setItem('auth_token', c.token);
  localStorage.setItem('user_id', c.user.id);
  localStorage.setItem('user_permissions', JSON.stringify(c.user.user_permissions || c.user.permissions || ['*']));
}, body);
await page.goto(HOST + ':8080/dashboard/profile', { waitUntil: 'networkidle' });
await page.waitForTimeout(2000);
await page.screenshot({ path: '/work/screenshots/profile-nickname.png', fullPage: true });
console.log('saved profile-nickname.png');
const visible = await page.locator('[data-testid="profile-nickname-section"]').isVisible().catch(() => false);
console.log('section visible:', visible);
await browser.close();
