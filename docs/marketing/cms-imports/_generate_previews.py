#!/usr/bin/env python3
"""Generate preview.html for each vertical from its pages.json.

The existing preview.html files were static dumps of the original 4 pages
(about / features / integrations / payment-modules) and are now stale: they
don't include the 3 CTA pages added by _generate_ctas.py. This script
regenerates preview.html for each vertical from the live pages.json, so
all pages — original + CTA — render in one scrollable HTML file you can
open locally to eyeball the import before pushing to the CMS.

Run:
    python docs/marketing/cms-imports/_generate_previews.py
"""
import json
from pathlib import Path

OUTPUT_ROOT = Path(__file__).parent

VERTICALS = ["core", "softwarestore", "hotel", "doctor", "ghrm"]


def render_preview(vertical: str) -> str | None:
    pages_file = OUTPUT_ROOT / vertical / "pages.json"
    if not pages_file.exists():
        return None
    pages = json.loads(pages_file.read_text())

    # Emit a single preview.html with all pages stacked. Each page brings its
    # own scoped CSS; we include it once per page (cheap, since browsers
    # de-dupe identical text content easily).
    parts = [
        "<!doctype html>",
        "<html><head><meta charset=utf-8>",
        f"<title>Preview — {vertical} ({len(pages)} pages)</title>",
        '<style>body{margin:0;font-family:sans-serif;background:#eef2f7}',
        '.preview-toc{position:sticky;top:0;background:#0f172a;color:#fff;padding:.6rem 1rem;',
        'display:flex;gap:1rem;flex-wrap:wrap;z-index:1000;box-shadow:0 2px 8px rgba(0,0,0,.2)}',
        '.preview-toc a{color:#fff;text-decoration:none;font-size:.85rem;border:1px solid rgba(255,255,255,.25);',
        'padding:.3rem .7rem;border-radius:999px}.preview-toc a:hover{background:rgba(255,255,255,.15)}',
        '.preview-page{margin:2rem auto;max-width:1200px;background:#fff;border-radius:14px;',
        'box-shadow:0 4px 16px rgba(0,0,0,.08);overflow:hidden}',
        '.preview-label{background:#0f172a;color:#fff;padding:.5rem 1.5rem;font-size:.78rem;',
        'letter-spacing:.08em;text-transform:uppercase;font-weight:700}',
        "</style>",
        "</head><body>",
        "<nav class=\"preview-toc\">",
        f"<strong style=\"font-size:.85rem;letter-spacing:.08em\">{vertical.upper()}</strong>",
    ]
    for p in pages:
        parts.append(f'<a href="#{p["slug"]}">{p["slug"]}</a>')
    parts.append("</nav>")

    for p in pages:
        parts.append(f'<section class="preview-page" id="{p["slug"]}">')
        parts.append(f'<div class="preview-label">/{p["slug"]} &middot; {p["name"]}</div>')
        parts.append(f'<style>{p.get("source_css", "")}</style>')
        parts.append(p.get("content_html", ""))
        parts.append("</section>")

    parts.append("</body></html>")
    return "\n".join(parts)


if __name__ == "__main__":
    for v in VERTICALS:
        out = render_preview(v)
        if out is None:
            print(f"  skip {v} — no pages.json")
            continue
        target = OUTPUT_ROOT / v / "preview.html"
        target.write_text(out)
        size_kb = target.stat().st_size // 1024
        pages_count = out.count('class="preview-page"')
        print(f"  + {v}/preview.html — {pages_count} pages, {size_kb} KB")
    print("Done.")