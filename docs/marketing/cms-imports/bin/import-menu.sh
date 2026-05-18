#!/usr/bin/env bash
# Replace the header-nav + footer-nav menu trees of a running VBWD instance
# from <vertical>/menu.json.
#
# Menus are NOT part of the pages-import pipeline (import.sh): a menu lives on
# a cms_widget of type=menu, not on a page. This script resolves the
# header-nav / footer-nav widget IDs by slug, then PUTs each menu tree to
# /api/v1/admin/cms/widgets/<widget_id>/menu (replace-tree — idempotent).
#
# IMPORTANT: replace_tree does NOT recurse into a nested "children" key. The
# menu arrays in menu.json are FLAT: every item has a placeholder string
# "id"; sub-items reference their parent via "parent_id". replace_tree
# remaps the placeholder ids to real UUIDs and rewires parent_id. "children"
# arrays would be silently dropped (only top-level items would land).
#
# Usage:
#   ./import-menu.sh <vertical> <base-url> <admin-email> <admin-password>
#
# Example:
#   ./import-menu.sh core https://vbwd.cc admin@example.com 'AdminPass123@'
#
# Requires: curl, jq

set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <vertical> <base-url> <admin-email> <admin-password>" >&2
  exit 2
fi

VERTICAL="$1"
BASE_URL="${2%/}"
EMAIL="$3"
PASSWORD="$4"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MENU_FILE="${SCRIPT_DIR}/../${VERTICAL}/menu.json"

if [ ! -f "$MENU_FILE" ]; then
  echo "error: menu.json not found for vertical '$VERTICAL' at $MENU_FILE" >&2
  exit 1
fi

echo "=> logging in as $EMAIL at $BASE_URL"
LOGIN_RESPONSE=$(curl -sS -X POST "$BASE_URL/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p}')")
TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.access_token // .token // empty')

if [ -z "$TOKEN" ]; then
  echo "error: login failed — response was:" >&2
  echo "$LOGIN_RESPONSE" >&2
  exit 1
fi

# Pull every widget once; resolve the menu widget IDs by slug.
WIDGETS=$(curl -sS "$BASE_URL/api/v1/admin/cms/widgets?per_page=100&type=menu" \
  -H "Authorization: Bearer $TOKEN")

apply_menu() {
  local slug="$1"
  local widget_id
  widget_id=$(echo "$WIDGETS" | jq -r \
    --arg s "$slug" '(.items // .data // .)[]? | select(.slug == $s) | .id' | head -n1)

  if [ -z "$widget_id" ] || [ "$widget_id" = "null" ]; then
    echo "  ! widget slug '$slug' not found — skipping (create it in the CMS first)" >&2
    return
  fi

  echo "=> replacing '$slug' menu (widget $widget_id)"
  jq ".\"$slug\"" "$MENU_FILE" | curl -sS -X PUT \
    "$BASE_URL/api/v1/admin/cms/widgets/$widget_id/menu" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary @- | jq 'length as $n | "  ok — \($n) top-level item(s) written"'
}

apply_menu "header-nav"
apply_menu "footer-nav"
echo "Done."
