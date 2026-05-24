# Sprint 05 — Backend: subscription email templates → plugin

**Phase:** 1 · **Repos:** `vbwd-backend`, `vbwd-backend/plugins/subscription`
**Effort:** S–M (~1–2 dev-days) · **Depends on:** 04 · **Blocks:** 09
**Engineering requirements:** [`_engineering-requirements.md`](../sprints/_engineering-requirements.md) — binding.

## Goal

Core `vbwd/templates/email/subscription_*.{html,txt}` are rendered by core
`email_service.py`. Move the templates into the plugin and make
`email_service` resolve templates through a **plugin-registered template
path**, so core ships no subscription email content.

Templates in scope: `subscription_activated.{html,txt}`,
`subscription_cancelled.{html,txt}` (+ any other `subscription_*` confirmed
in core `templates/email/`).

## Baseline (E1)

`test_subscription_email_render_char.py` — render each template with a fixed
context and assert the **exact rendered bytes** (subject + html + txt). GREEN
on `main` against the core-located templates. Unchanged after the move (E2:
identical output).

## Failure / architecture analysis

Report §3.1(a): 04c said to delete these; they stayed. `email_service`'s Jinja
environment is core-rooted, so the plugin can't own the content without a
generic loader extension point — exactly the §5 DI pattern in the inherited
reqs (`PdfService(template_env)` precedent: inject the env / add a loader).

## TDD plan

1. **RED:** `test_email_service_resolves_plugin_template` — `email_service`
   asked to render `subscription_activated` finds it via a registered plugin
   template directory while the core copy is absent. Red (no registration API
   yet).
2. Add a generic **template path registry** (DI: `email_service` takes a
   Jinja `ChoiceLoader`; plugins contribute a `FileSystemLoader` for their
   `templates/email/`). No subscription names in core. Plugin registers its
   dir in `on_enable`.
3. Move the 4 template files into
   `plugins/subscription/subscription/templates/email/`; delete from core.
4. Baseline `test_subscription_email_render_char` GREEN **unchanged** (same
   bytes, now loaded from the plugin).
5. **RED→GREEN** `test_core_has_no_subscription_email_templates` — assert no
   `subscription_*` file under `vbwd/templates/email/` and core's default
   loader can't resolve them.
6. Plugin-disabled: `test_email_service_without_plugin` — core renders its own
   (non-subscription) templates fine; requesting a subscription template
   raises a clear `TemplateNotFound`, not a 500 in an unrelated flow.

> Note `plugins/subscription/docs/imports/email/subscription-email-templates.json`
> already exists as *import data*; this sprint moves the **rendered Jinja
> templates**, and reconciles the two so there is one source (DRY) — the
> import JSON references the plugin templates, no divergent copies.

## SOLID / DI / clean-code notes

- **DI (§5):** the Jinja environment/loader is injected; tests pass a
  `DictLoader` — directly mirrors the `PdfService(template_env)` precedent.
- **OCP/SRP:** core email service knows *how to render*, not *which feature's
  templates exist*. Plugins extend by registering a loader.
- **DRY:** one subscription-email source (templates in plugin); the import
  JSON points at them, not a second copy.
- **Liskov (E2):** byte-identical render is the substitution contract.

## Acceptance criteria

- Templates live only in the plugin; core has none.
- Baseline render char test GREEN unchanged (identical bytes).
- Plugin-disabled core renders non-subscription emails; subscription template
  request fails cleanly and is never on a core-only path.
- `make pre-commit` green.

### E3 oracle slice made true

"no `subscription` template content in core `vbwd/templates/`".

## Risks

- A core flow still triggers a subscription email directly (should be none
  after Sprint 04 moved `/checkout`). Mitigation: grep `email_service`
  call sites for subscription template names; the plugin-disabled test
  catches a stray core trigger.

## Effort

S–M — ~1–2 dev-days (loader registry is small; precedent exists).
