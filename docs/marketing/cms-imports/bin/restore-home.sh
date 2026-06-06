#!/usr/bin/env bash
#
# Restore the prod /home page to its canonical design + content.
#
# Why this exists: the home record was once edited in the admin WYSIWYG, which
# flattened its rich marketing HTML to bare paragraphs and (via the "About"
# category) re-slugged it so vbwd.cc/home went blank. This re-applies the
# canonical content from core/home.json.
#
# NEW CMS data structure: home is a `cms_post` of type "page", slug "home", and
# POST /api/v1/admin/cms/posts/import is an UPSERT keyed on (type, slug) — so
# importing core/home.json *updates* the existing record in place (no duplicate,
# no surgical PUT, no hardcoded record id needed). core/home.json carries its own
# `source_css` and `terms: []` (no category → no `about/` slug prefix).
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

SRC="$(cd "$(dirname "$0")/.." && pwd)/core/home.json"
[ -f "$SRC" ] || { echo "error: $SRC not found" >&2; exit 1; }

echo "==> Logging in to $BASE"
TOKEN=$(curl -fsS -X POST "$BASE/api/v1/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PW\"}" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('access_token') or d['token'])")

echo "==> POST /api/v1/admin/cms/posts/import  (upsert home from $SRC)"
curl -fsS -X POST "$BASE/api/v1/admin/cms/posts/import" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  --data-binary "@$SRC" \
  | python3 -c "
import sys, json
r = json.load(sys.stdin)
created, updated = r.get('created', 0), r.get('updated', 0)
print('  created   :', created)
print('  updated   :', updated)
ok = (created + updated) >= 1
print('  RESULT    :', 'OK — open https://vbwd.cc/  and  https://vbwd.cc/home' if ok else f'CHECK — unexpected response: {r}')
"
