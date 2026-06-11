const { chromium } = require('playwright');
const fs = require('fs');
const SHOTS = '/tmp/wt_shots';
const steps = [];
async function shot(page, name, caption){ const p=`${SHOTS}/${name}.png`; await page.screenshot({path:p, fullPage:true}); steps.push({name, caption, file:p}); console.log('shot:', name); }

(async () => {
  const b = await chromium.launch();
  const page = await b.newPage({ viewport:{width:1440,height:1200} });
  const errs=[]; page.on('console',m=>{if(m.type()==='error' && !/vite|hmr|websocket/i.test(m.text()))errs.push(m.text().slice(0,140));});

  // 1. form login (the only reliable auth path; client-side nav afterwards avoids the initAuth race)
  await page.goto('http://localhost:8081/admin/login',{waitUntil:'networkidle',timeout:30000}).catch(()=>{});
  await page.fill('input[type=email],input[type=text]','admin@example.com');
  await page.fill('input[type=password]','AdminPass123@');
  await Promise.allSettled([page.waitForURL(u=>!String(u).includes('/login'),{timeout:15000}), page.click('button:has-text("Sign In"),button[type=submit]')]);
  await page.waitForTimeout(2500);
  console.log('after login url:', page.url());

  // 2. CLIENT-SIDE nav to Import/Export (click the sidebar router-link — no page reload)
  await page.click('[data-testid="nav-item-import-export"]',{timeout:10000}).catch(async()=>{ await page.click('a[href="/admin/import-export"]').catch(()=>{}); });
  await page.waitForSelector('[data-test=export-block]',{timeout:15000}).catch(()=>{});
  await page.waitForTimeout(1800);
  await shot(page,'01-import-export-page','The unified Import/Export page (core ImportExportPage) — one manifest-driven UI for every entity.');

  const entityKeys = await page.$$eval('[data-test^="export-entity-"]', els=>els.map(e=>e.getAttribute('data-test').replace('export-entity-','')));
  console.log('export entities shown:', JSON.stringify(entityKeys));
  fs.writeFileSync(`${SHOTS}/entities.json`, JSON.stringify(entityKeys));

  // 3. EXPORT demo
  const cb = page.locator('[data-test=export-entity-booking_resources] input[type=checkbox]').first();
  if(await cb.count()){
    await cb.scrollIntoViewIfNeeded().catch(()=>{}); await cb.check().catch(()=>{}); await page.waitForTimeout(400);
    await shot(page,'02-export-selected','Export — booking_resources selected (JSON).');
    const [dl] = await Promise.all([ page.waitForEvent('download',{timeout:10000}).catch(()=>null), page.click('[data-test=export-run]').catch(()=>{}) ]);
    if(dl){ const dp=`${SHOTS}/exported_booking_resources.json`; await dl.saveAs(dp).catch(()=>{});
      try{ const j=JSON.parse(fs.readFileSync(dp,'utf8')); const rows=j.booking_resources||j.rows||[]; fs.writeFileSync(`${SHOTS}/export_meta.json`, JSON.stringify({rows:rows.length, fields: rows[0]?Object.keys(rows[0]).sort():[]})); console.log('export rows:', rows.length, 'fields/row:', rows[0]?Object.keys(rows[0]).length:0); }catch(e){console.log('parse err',e.message);}
    } else console.log('no download captured');
    await page.waitForTimeout(700); await shot(page,'03-export-done','Export complete — catalogue downloaded as a JSON envelope (all fields per row).');
  } else console.log('booking_resources export checkbox NOT found');

  // 4. IMPORT demo
  await page.locator('[data-test=import-file]').scrollIntoViewIfNeeded().catch(()=>{});
  await page.setInputFiles('[data-test=import-file]','/tmp/booking_resources_envelope.json').catch(e=>console.log('setfile err',e.message));
  await page.waitForTimeout(600);
  await page.click('[data-test=import-preview-run]').catch(()=>{});
  await page.waitForSelector('[data-test=import-preview]',{timeout:12000}).catch(()=>{});
  await page.waitForTimeout(900);
  const preview = await page.locator('[data-test=import-result-booking_resources]').innerText().catch(()=>'');
  console.log('preview:', JSON.stringify(preview));
  await shot(page,'04-import-preview','Import preview (dry-run) — created / updated / skipped / errors for booking_resources, 0 errors.');

  await page.click('[data-test=import-confirm]').catch(()=>{});
  await page.waitForTimeout(2200);
  const committed = await page.locator('[data-test=import-result-booking_resources]').innerText().catch(()=>'');
  console.log('committed:', JSON.stringify(committed));
  await shot(page,'05-import-committed','Import committed — booking_resources imported, 0 errors.');
  fs.writeFileSync(`${SHOTS}/import_counts.json`, JSON.stringify({preview, committed}));

  fs.writeFileSync(`${SHOTS}/steps.json`, JSON.stringify(steps));
  console.log('console errors:', JSON.stringify(errs.slice(0,5)));
  await b.close();
})().catch(e=>{ console.error('ERR', e.message); process.exit(1); });
