# Payment-method scope freeze — 2026-05-28

## Decision

Demo instances will support **only four** payment methods going forward:

| Method | Backend plugin | fe-user plugin | fe-admin plugin |
|---|---|---|---|
| Stripe | `stripe` | `stripe-payment` | _(none)_ |
| PayPal | `paypal` | `paypal-payment` | _(none)_ |
| Token balance | `token_payment` | `token-payment` | `token-payment-admin` |
| Invoice (manual bank transfer) | _core_ — `payment_method = "invoice"` | _core checkout_ | _core admin_ |

Everything else is **frozen** — repos kept on the org for archival but
**excluded from CI, deploy builds, and all demo instance plugin enablement
lists.** Further development on these is paused until an explicit
un-freeze decision.

## Frozen payment plugins

| Backend | fe-user | fe-admin |
|---|---|---|
| `vbwd-plugin-c2p2` | `vbwd-fe-user-plugin-c2p2-payment` | `vbwd-fe-admin-plugin-c2p2-admin` |
| `vbwd-plugin-conekta` | `vbwd-fe-user-plugin-conekta-payment` | `vbwd-fe-admin-plugin-conekta-admin` |
| `vbwd-plugin-mercado-pago` | `vbwd-fe-user-plugin-mercado-pago-payment` | `vbwd-fe-admin-plugin-mercado-pago-admin` |
| `vbwd-plugin-promptpay` | `vbwd-fe-user-plugin-promptpay-payment` | `vbwd-fe-admin-plugin-promptpay-admin` |
| `vbwd-plugin-toss-payments` | `vbwd-fe-user-plugin-toss-payments-payment` | `vbwd-fe-admin-plugin-toss-payments-admin` |
| `vbwd-plugin-truemoney` | `vbwd-fe-user-plugin-truemoney-payment` | `vbwd-fe-admin-plugin-truemoney-admin` |
| `vbwd-plugin-yookassa` | `vbwd-fe-user-plugin-yookassa-payment` | _(no admin plugin existed)_ |

Total frozen: **7 backend × 7 fe-user × 6 fe-admin = 20 repos**.

## Why

Every "active" payment integration brings:
- Sandbox + production credential management per instance.
- Webhook signing-secret + endpoint plumbing.
- Per-provider integration-test maintenance.
- Per-provider Liskov contract review (capture/release/refund semantics).

Maintaining 10 active providers when demo deployments only ever exercise
3 of them (+ the core invoice path) is pure carrying cost. Freeze the
unused ones until a real business case re-activates them.

## Enforcement (technical)

### vbwd-backend CI workflows

- `tests.yml` — both `Install plugins` blocks clone 17 plugins (not 24).
- `plugin-tests.yml`
  - unit matrix: 17 entries (was 24 briefly; was 11 originally).
  - "Install ALL plugins (full SDK)" block: 17 plugins.
  - `DEPS` map drops `yookassa` (no longer in the matrix).

The shared `REPO_OVERRIDES` bash map now only carries `token_payment →
token-payment` (the other two snake↔kebab overrides — `mercado_pago` and
`toss_payments` — went away with the freeze).

### vbwd-demo-instances deploy.yml

- Backend image clones the same 17 plugins.
- fe-user image clones 14 plugins (was 21 briefly).
- fe-admin image clones 11 plugins (was 17 briefly).

### Instance plugins.json + config.json

- All 6 instances now have **`stripe` + `paypal` + `token_payment`**
  enabled in `backend/plugins.json`.
- All 6 instances have **`stripe-payment` + `paypal-payment` +
  `token-payment`** enabled in `fe-user/plugins.json`.
- `saas` lost `yookassa` + `yookassa-payment` (the only instance that
  had them).
- `backend/config.json` for each instance gained a default `paypal:
  { sandbox: true, test_client_id: "", test_client_secret: "", ... }`
  block (operator fills in credentials before going live).

### Invoice "method"

Already supported by core via `payment_method = "invoice"` on the
`UserInvoice` row (admin marks the invoice as paid when the bank
transfer clears). No plugin, no `PaymentMethod` registry entry, no
SDK adapter — handled by `vbwd/routes/admin/invoices.py::mark_paid`.

## Reversal procedure (if a frozen provider needs re-activation)

1. **Pick the provider** (e.g. yookassa) and confirm credentials are
   available + an instance needs it.
2. **CI** — add it back to (in order):
   - `vbwd-backend/.github/workflows/tests.yml` (both `BACKEND_PLUGINS`
     strings)
   - `vbwd-backend/.github/workflows/plugin-tests.yml` (unit matrix +
     "Install ALL plugins" + `DEPS` if it consumes
     `resolve_subscription_lifecycle`)
   - Add the override to `REPO_OVERRIDES` if the dir↔repo name differs
     (e.g. `mercado_pago → mercado-pago`).
3. **Deploy** — add it back to (in order):
   - `vbwd-demo-instances/.github/workflows/deploy.yml` backend +
     fe-user + fe-admin clone blocks.
4. **Instance(s)** — enable it in the target instance's:
   - `backend/plugins.json` (snake-case key, `enabled: true`)
   - `backend/config.json` (sandbox creds first; production via
     env-only / secrets manager)
   - `fe-user/plugins.json` (kebab-case `<provider>-payment` key)
   - `fe-admin/plugins.json` if the per-provider admin UI is needed
5. **Verify** — run `bin/pre-commit-check.sh --plugin <name> --quick`
   locally, then push and observe the CI matrix.

## Rollout

Commit lands the CI + deploy + instance changes in one push. The new
backend image (built by the demo-instances deploy workflow on push)
contains exactly the 17-plugin set; instances already enabling
`paypal` (saas) keep working, others will pick up paypal on first
fresh deploy.

For **already-deployed** instances: the per-instance `${VAR_DIR}/plugins/`
files on the VPS won't auto-update (the deploy seed only writes missing
files). Either bump the on-disk `backend-plugins.json` manually or
toggle in the admin UI.
