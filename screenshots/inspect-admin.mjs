import { chromium } from 'playwright';
const HOST = 'http://host.docker.internal';
const browser = await chromium.launch();
const page = await browser.newPage();
const auth = await page.request.post(HOST + ':5000/api/v1/auth/login', {
  data: { email: 'admin@example.com', password: 'AdminPass123@' },
  headers: { 'Content-Type': 'application/json' },
});
const body = await auth.json();
await page.goto(HOST + ':8081/admin/');
await page.evaluate((c) => {
  localStorage.setItem('admin_token', c.token);
  localStorage.setItem('admin_token_user', JSON.stringify(c.user));
}, body);
await page.goto(HOST + ':8081/admin/invoices/467d59d8-9dfd-4dfe-a54e-07338cc93a8c', {
  waitUntil: 'networkidle',
});
await page.waitForTimeout(2500);
const out = await page
  .locator('[data-testid="payment-data-block"]')
  .first()
  .evaluate((el) => ({
    html: el.outerHTML,
    parentClass: el.parentElement?.className,
    parentDisplay: getComputedStyle(el.parentElement).display,
    selfDisplay: getComputedStyle(el).display,
    rowDisplay: getComputedStyle(el.firstElementChild).display,
    rowJustify: getComputedStyle(el.firstElementChild).justifyContent,
  }))
  .catch((e) => ({ err: String(e) }));
console.log(JSON.stringify(out, null, 2));
await browser.close();
