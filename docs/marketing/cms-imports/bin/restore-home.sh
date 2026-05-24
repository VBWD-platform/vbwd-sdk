#!/usr/bin/env bash
#
# Restore the prod /home page to its original design + content.
#
# Why this exists: the page record b9b10e9f was edited in the admin WYSIWYG,
# which (a) flattened its rich marketing HTML to bare paragraphs and (b) via
# the "About" category, re-slugged it to `about/home` — so vbwd.cc/home went
# blank. This re-applies the canonical content from core/home.json, restores
# slug `home`, detaches the category (which forces the `about/` prefix), and
# keeps the marketing Style record that carries the vbwd-* CSS.
#
# Surgical PUT — does NOT create a duplicate. CMS import is create-only and
# cannot update an existing record, hence the direct PUT.
#
# Usage:
#   bash docs/marketing/cms-imports/bin/restore-home.sh <BASE_URL> <EMAIL> <PASSWORD>
#   e.g.
#   bash docs/marketing/cms-imports/bin/restore-home.sh https://vbwd.cc admin@vbwd.cc 'REAL_PROD_PASSWORD'
#
set -euo pipefail

BASE="${1:?base url, e.g. https://vbwd.cc}"
EMAIL="${2:?admin email}"
PW="${3:?admin password}"

PAGE_ID="b9b10e9f-d886-4a95-a0c2-32ad8eca21ad"
# Marketing style record that /about renders correctly with (contains the
# full vbwd-hero/vbwd-card/vbwd-stat CSS). Verified on prod: /css = 200, 12KB.
STYLE_ID="247cacb0-12e2-4dc5-b6bb-2f14965afde6"
SRC="$(cd "$(dirname "$0")/.." && pwd)/core/home.json"

echo "==> Logging in to $BASE"
TOKEN=$(curl -fsS -X POST "$BASE/api/v1/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PW\"}" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")

echo "==> Building payload from $SRC"
PAYLOAD=$(python3 - "$SRC" "$STYLE_ID" <<'PY'
import json, sys
src = json.load(open(sys.argv[1]))[0]
print(json.dumps({
    "slug": "home",                 # back to the homepage slug
    "category_id": None,            # detach "About" so slug is not re-prefixed
    "style_id": sys.argv[2],        # keep the marketing style (vbwd-* CSS)
    "content_html": src["content_html"],          # original rich markup
    "content_json": {"type": "doc", "content": []},  # empty: renderer uses content_html
    "source_css": src.get("source_css", ""),
    "use_theme_switcher_styles": False,
    "is_published": True,
    "name": src.get("name"),
    "meta_title": src.get("meta_title", ""),
    "meta_description": src.get("meta_description", ""),
    "meta_keywords": src.get("meta_keywords", ""),
    "og_title": src.get("og_title", ""),
    "og_description": src.get("og_description", ""),
    "robots": src.get("robots", "index,follow"),
}))
PY
)

echo "==> PUT /api/v1/admin/cms/pages/$PAGE_ID"
curl -fsS -X PUT "$BASE/api/v1/admin/cms/pages/$PAGE_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "$PAYLOAD" \
  | python3 -c "
import sys, json
p = json.load(sys.stdin)
print('  slug      :', p.get('slug'))
print('  html_len  :', len(p.get('content_html') or ''))
print('  style_id  :', p.get('style_id'))
print('  category  :', p.get('category_id'))
ok = p.get('slug') == 'home' and len(p.get('content_html') or '') > 4000 and p.get('style_id')
print('  RESULT    :', 'OK — open https://vbwd.cc/  and  https://vbwd.cc/home' if ok else 'CHECK — unexpected response')
"
