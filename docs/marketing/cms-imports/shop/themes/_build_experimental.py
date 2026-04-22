#!/usr/bin/env python3
"""Generate six experimental, vibrant CMS themes for the shop demo.

Reuses the base CSS, button/hero/cta/card rules, and menu-width logic
from the main plugin generator so these experimental themes ship with
the same primitives — we only swap palettes + punchier shadows /
accent glows.

Each theme is output as a stand-alone JSON file under this directory so
an admin can drag-drop a single file into the Styles → Import UI.

    python3 docs/marketing/cms-imports/shop/themes/_build_experimental.py

Outputs:
    <slug>.json              — one per theme, admin-import compatible
    all.json                 — {"themes": [...]}, for bulk import

Fancy names, high contrast, gradient-heavy, subtle card shadows.
3 narrow (1100px) + 3 fullwidth (100%).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

# Reuse the canonical base CSS + palette tokens helper from the plugin
PLUGIN_IMPORT_DIR = (
    Path(__file__).resolve().parents[5]
    / "vbwd-backend" / "plugins" / "cms" / "docs" / "imports"
)
sys.path.insert(0, str(PLUGIN_IMPORT_DIR))
from _build_theme_styles import BASE_CSS, tokens, _menu_rules_for  # type: ignore


OUT = Path(__file__).parent

# ── Experimental palettes (modern, high-contrast, gradient-led) ─────────────

EXPERIMENTS = [
    # ── Narrow (1100px) ─────────────────────────────────────────────────────
    {
        "slug": "aurora-nebula-narrow",
        "name": "Aurora Nebula — Narrow",
        "width_slug": "narrow",
        "width_max": "1100px",
        "tokens": {
            "color-accent": "#7c3aed",
            "color-accent-soft": "#ede9fe",
            "color-accent-dark": "#5b21b6",
            "color-accent-fg": "#ffffff",
            "color-contrast-bg": "#0f172a",
            "color-contrast-fg": "#f8fafc",
            "color-contrast-hover-bg": "#1e293b",
            "color-link": "#6d28d9",
            "color-link-hover": "#4c1d95",
            "color-bg": "#fafafe",
            "color-surface": "#ffffff",
            "color-surface-soft": "#f5f3ff",
            "color-border": "#ddd6fe",
            "color-text": "#1f1036",
            "color-text-muted": "#5b4a73",
            "color-heading": "#0f051f",
            "color-gradient": "linear-gradient(135deg, #6d28d9 0%, #db2777 50%, #f59e0b 100%)",
        },
        "extras": """\
/* Aurora Nebula — tri-stop gradient + lifted cards */
.card { box-shadow: 0 6px 18px -4px rgba(109,40,217,0.18), 0 3px 6px -2px rgba(219,39,119,0.12); border-color: rgba(221,214,254,0.7); }
.card:hover { box-shadow: 0 14px 32px -8px rgba(109,40,217,0.28), 0 6px 12px -4px rgba(219,39,119,0.20); transform: translateY(-2px); transition: transform 0.18s, box-shadow 0.18s; }
.hero { box-shadow: 0 20px 50px -12px rgba(109,40,217,0.35); }
.btn { transition: transform 0.12s ease, box-shadow 0.18s ease, background 0.15s; }
.btn--accent:hover { box-shadow: 0 8px 18px -4px rgba(109,40,217,0.45); transform: translateY(-1px); }
""",
    },
    {
        "slug": "sunset-arcade-narrow",
        "name": "Sunset Arcade — Narrow",
        "width_slug": "narrow",
        "width_max": "1100px",
        "tokens": {
            "color-accent": "#e11d48",
            "color-accent-soft": "#ffe4e6",
            "color-accent-dark": "#9f1239",
            "color-accent-fg": "#ffffff",
            "color-contrast-bg": "#083344",
            "color-contrast-fg": "#ecfeff",
            "color-contrast-hover-bg": "#164e63",
            "color-link": "#9f1239",
            "color-link-hover": "#881337",
            "color-bg": "#fff8f1",
            "color-surface": "#ffffff",
            "color-surface-soft": "#fff1e6",
            "color-border": "#fed7aa",
            "color-text": "#2d1a12",
            "color-text-muted": "#7c4a30",
            "color-heading": "#1a0d08",
            "color-gradient": "linear-gradient(135deg, #f59e0b 0%, #e11d48 60%, #831843 100%)",
        },
        "extras": """\
/* Sunset Arcade — warm glow shadows */
.card { box-shadow: 0 4px 14px -4px rgba(225,29,72,0.15), 0 2px 6px -2px rgba(245,158,11,0.12); }
.card:hover { box-shadow: 0 12px 28px -8px rgba(225,29,72,0.28); transform: translateY(-2px); transition: transform 0.18s, box-shadow 0.18s; }
.hero { box-shadow: 0 24px 55px -14px rgba(225,29,72,0.32); }
.btn--accent:hover { box-shadow: 0 8px 18px -4px rgba(225,29,72,0.40); transform: translateY(-1px); }
.cta-band { box-shadow: 0 16px 40px -10px rgba(225,29,72,0.28); }
""",
    },
    {
        "slug": "mint-meridian-narrow",
        "name": "Mint Meridian — Narrow",
        "width_slug": "narrow",
        "width_max": "1100px",
        "tokens": {
            "color-accent": "#047857",
            "color-accent-soft": "#d1fae5",
            "color-accent-dark": "#064e3b",
            "color-accent-fg": "#ffffff",
            "color-contrast-bg": "#0f172a",
            "color-contrast-fg": "#ecfdf5",
            "color-contrast-hover-bg": "#1e293b",
            "color-link": "#047857",
            "color-link-hover": "#065f46",
            "color-bg": "#f6fbf8",
            "color-surface": "#ffffff",
            "color-surface-soft": "#ecfdf5",
            "color-border": "#a7f3d0",
            "color-text": "#052e1a",
            "color-text-muted": "#4b6b5b",
            "color-heading": "#032012",
            "color-gradient": "linear-gradient(135deg, #047857 0%, #0891b2 60%, #1e40af 100%)",
        },
        "extras": """\
/* Mint Meridian — cool teal→blue with crystalline lift */
.card { box-shadow: 0 4px 16px -4px rgba(4,120,87,0.14), 0 1px 3px rgba(8,145,178,0.08); border-color: rgba(167,243,208,0.65); }
.card:hover { box-shadow: 0 12px 30px -8px rgba(4,120,87,0.22); transform: translateY(-2px); transition: transform 0.18s, box-shadow 0.18s; }
.hero { box-shadow: 0 20px 46px -12px rgba(8,145,178,0.30); }
.btn--accent:hover { box-shadow: 0 8px 18px -4px rgba(4,120,87,0.38); transform: translateY(-1px); }
""",
    },
    # ── Fullwidth (100%) ────────────────────────────────────────────────────
    {
        "slug": "neon-boulevard-fullwidth",
        "name": "Neon Boulevard — Fullwidth",
        "width_slug": "fullwidth",
        "width_max": "100%",
        "tokens": {
            # Tuned: more saturated accent, clearer muted grey, deeper
            # gradient (prior 3rd stop #db2777 was too bright and bled
            # magenta over the white hero heading). New palette keeps the
            # cyberpunk feel but stays legible end-to-end.
            "color-accent": "#22d3ee",
            "color-accent-soft": "#155e75",
            "color-accent-dark": "#0e7490",
            "color-accent-fg": "#04131a",
            "color-contrast-bg": "#ecfeff",
            "color-contrast-fg": "#04131a",
            "color-contrast-hover-bg": "#cffafe",
            "color-link": "#67e8f9",
            "color-link-hover": "#a5f3fc",
            "color-bg": "#05070f",
            "color-surface": "#0d1526",
            "color-surface-soft": "#141f36",
            "color-border": "#223044",
            "color-text": "#e8ecf4",
            "color-text-muted": "#b7bdcc",
            "color-heading": "#f9fafb",
            "color-gradient": "linear-gradient(135deg, #083344 0%, #4c1d95 50%, #9d174d 100%)",
        },
        "extras": """\
/* Neon Boulevard — cyberpunk gradient + glowing edges */
.hero, .cta-band { color: #ffffff !important; }
.card { box-shadow: 0 0 0 1px rgba(34,211,238,0.14), 0 8px 24px -6px rgba(0,0,0,0.65); background: #0d1526; }
.card:hover { box-shadow: 0 0 0 1px rgba(34,211,238,0.40), 0 14px 32px -8px rgba(124,58,237,0.40); transform: translateY(-2px); transition: transform 0.18s, box-shadow 0.18s; }
.hero { box-shadow: 0 30px 80px -20px rgba(124,58,237,0.55); }
.btn--accent { box-shadow: 0 0 20px -4px rgba(34,211,238,0.55); }
.btn--accent:hover { box-shadow: 0 0 26px -2px rgba(34,211,238,0.82); transform: translateY(-1px); }
.cta-band { box-shadow: 0 20px 56px -16px rgba(157,23,77,0.45); }
a { color: #67e8f9; }
a:hover { color: #a5f3fc; }
""",
    },
    {
        "slug": "solaris-gold-fullwidth",
        "name": "Solaris Gold — Fullwidth",
        "width_slug": "fullwidth",
        "width_max": "100%",
        "tokens": {
            # Tuned: brighter heading / text for readability on the dark
            # cocoa surface; muted-text lifted from #a89a7f to #c6b99b for
            # AA contrast on the #1a1006 body; gradient end darkened from
            # #f59e0b to #d97706 so the hero white text doesn't wash out.
            "color-accent": "#f59e0b",
            "color-accent-soft": "#78350f",
            "color-accent-dark": "#b45309",
            "color-accent-fg": "#1c1105",
            "color-contrast-bg": "#fef3c7",
            "color-contrast-fg": "#1c1105",
            "color-contrast-hover-bg": "#fde68a",
            "color-link": "#fbbf24",
            "color-link-hover": "#fcd34d",
            "color-bg": "#180f05",
            "color-surface": "#2a1c0d",
            "color-surface-soft": "#3a2714",
            "color-border": "#4d3820",
            "color-text": "#f5eedd",
            "color-text-muted": "#c6b99b",
            "color-heading": "#fff8e6",
            "color-gradient": "linear-gradient(135deg, #451a03 0%, #9a3412 50%, #d97706 100%)",
        },
        "extras": """\
/* Solaris Gold — deep amber with gilded card edges */
.hero, .cta-band { color: #ffffff !important; }
.card { background: #2a1c0d; box-shadow: inset 0 0 0 1px rgba(251,191,36,0.12), 0 10px 26px -8px rgba(0,0,0,0.7); }
.card:hover { box-shadow: inset 0 0 0 1px rgba(251,191,36,0.32), 0 16px 36px -10px rgba(180,83,9,0.45); transform: translateY(-2px); transition: transform 0.18s, box-shadow 0.18s; }
.hero { box-shadow: 0 28px 70px -18px rgba(217,119,6,0.42); }
.btn--accent { box-shadow: 0 0 16px -3px rgba(251,191,36,0.45); }
.btn--accent:hover { box-shadow: 0 0 22px -1px rgba(251,191,36,0.72); transform: translateY(-1px); }
a { color: #fbbf24; }
a:hover { color: #fcd34d; }
""",
    },
    {
        "slug": "obsidian-coral-fullwidth",
        "name": "Obsidian Coral — Fullwidth",
        "width_slug": "fullwidth",
        "width_max": "100%",
        "tokens": {
            # Tuned: muted text #8a8ca1 fails AA against #0a0a0f — bumped to
            # #b4b8c9. Accent #f97373 → #fb7185 for a cleaner coral. Gradient
            # 3rd stop darkened from #f97373 to #be123c so white hero text
            # stays legible at the gradient end.
            "color-accent": "#fb7185",
            "color-accent-soft": "#881337",
            "color-accent-dark": "#e11d48",
            "color-accent-fg": "#1f0409",
            "color-contrast-bg": "#ffe4e6",
            "color-contrast-fg": "#1f0409",
            "color-contrast-hover-bg": "#fecdd3",
            "color-link": "#fda4af",
            "color-link-hover": "#fecdd3",
            "color-bg": "#0a0a0f",
            "color-surface": "#17172a",
            "color-surface-soft": "#20203a",
            "color-border": "#2e2e45",
            "color-text": "#ecedf2",
            "color-text-muted": "#b4b8c9",
            "color-heading": "#ffffff",
            "color-gradient": "linear-gradient(135deg, #0a0a0f 0%, #4c0519 50%, #be123c 100%)",
        },
        "extras": """\
/* Obsidian Coral — ink-black with coral spark */
.hero, .cta-band { color: #ffffff !important; }
.card { background: #17172a; box-shadow: 0 1px 0 rgba(251,113,133,0.10) inset, 0 10px 28px -10px rgba(251,113,133,0.22), 0 4px 10px -2px rgba(0,0,0,0.55); }
.card:hover { box-shadow: 0 1px 0 rgba(251,113,133,0.26) inset, 0 16px 38px -10px rgba(251,113,133,0.35); transform: translateY(-2px); transition: transform 0.18s, box-shadow 0.18s; }
.hero { box-shadow: 0 24px 60px -16px rgba(251,113,133,0.42); }
.btn--accent { box-shadow: 0 0 14px -3px rgba(251,113,133,0.55); }
.btn--accent:hover { box-shadow: 0 0 22px -1px rgba(251,113,133,0.85); transform: translateY(-1px); }
.cta-band { box-shadow: 0 20px 50px -14px rgba(225,29,72,0.45); }
a { color: #fda4af; }
a:hover { color: #fecdd3; }
""",
    },
]


def build_theme(spec: dict, sort_order: int) -> dict:
    width_css = f"/* width */\n:root {{\n  --container-max: {spec['width_max']};\n}}\n"
    source_css = (
        BASE_CSS
        + "\n"
        + tokens(**spec["tokens"])
        + "\n"
        + width_css
        + "\n"
        + _menu_rules_for(spec["width_slug"])
        + "\n"
        + spec.get("extras", "")
    )
    return {
        "slug": spec["slug"],
        "name": spec["name"],
        "source_css": source_css,
        "sort_order": sort_order,
        "is_active": True,
        "is_default": False,
    }


def main() -> None:
    themes: list[dict] = []
    for i, spec in enumerate(EXPERIMENTS, start=200):
        theme = build_theme(spec, sort_order=i)
        (OUT / f"{spec['slug']}.json").write_text(
            json.dumps(theme, indent=2, ensure_ascii=False) + "\n"
        )
        themes.append(theme)

    (OUT / "all.json").write_text(
        json.dumps(
            {
                "version": 1,
                "description": (
                    "Six experimental CMS themes (sprint 28). "
                    "3 narrow (1100px) + 3 fullwidth (100%)."
                ),
                "themes": themes,
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n"
    )
    print(f"Wrote {len(themes)} experimental themes to {OUT}")
    for t in themes:
        print(f"  {t['slug']:<34} {t['name']}")


if __name__ == "__main__":
    main()
