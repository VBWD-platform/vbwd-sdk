import { chromium } from 'playwright';
const HOST = 'http://host.docker.internal';
const browser = await chromium.launch();
const page = await browser.newPage();
const auth = await page.request.post(HOST + ':5000/api/v1/auth/login', {
  data: { email: 'test@example.com', password: 'TestPass123@' },
  headers: { 'Content-Type': 'application/json' },
});
const body = await auth.json();
await page.goto(HOST + ':8080/');
await page.evaluate((c) => {
  localStorage.setItem('auth_token', c.token);
  localStorage.setItem('user_id', c.user.id);
  localStorage.setItem(
    'user_permissions',
    JSON.stringify(c.user.user_permissions || c.user.permissions || ['*']),
  );
}, body);
await page.goto(
  HOST + ':8080/dashboard/invoice/467d59d8-9dfd-4dfe-a54e-07338cc93a8c',
  { waitUntil: 'networkidle' },
);
await page.waitForTimeout(2000);

const blockHtml = await page
  .locator('[data-testid="payment-data-block"]')
  .first()
  .evaluate((el) => el.outerHTML)
  .catch(() => '(no block)');
console.log('=== payment-data-block ===');
console.log(blockHtml);

const rowComputed = await page
  .locator('[data-testid="payment-data-tokens_paid"]')
  .first()
  .evaluate((el) => {
    const s = getComputedStyle(el);
    return {
      display: s.display,
      justifyContent: s.justifyContent,
      attrs: el.getAttributeNames(),
    };
  })
  .catch((e) => ({ error: String(e) }));
console.log('=== payment-data-tokens_paid computed ===');
console.log(JSON.stringify(rowComputed, null, 2));

await browser.close();
