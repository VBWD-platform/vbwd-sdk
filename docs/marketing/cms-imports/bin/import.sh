#!/usr/bin/env bash
# Import a vertical's pages.json into a running VBWD instance.
#
# Usage:
#   ./import.sh <vertical> <base-url> <admin-email> <admin-password>
#
# Example:
#   ./import.sh main http://localhost:5000 admin@example.com 'AdminPass123@'
#
# Requires: curl, jq

set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <vertical> <base-url> <admin-email> <admin-password>" >&2
  echo "Verticals: main | shop | hotel | doctor | ghrm" >&2
  exit 2
fi

VERTICAL="$1"
BASE_URL="${2%/}"
EMAIL="$3"
PASSWORD="$4"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAGES_FILE="${SCRIPT_DIR}/../${VERTICAL}/pages.json"

if [ ! -f "$PAGES_FILE" ]; then
  echo "error: pages.json not found for vertical '$VERTICAL' at $PAGES_FILE" >&2
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

echo "=> importing $PAGES_FILE into $BASE_URL ($VERTICAL)"
RESULT=$(curl -sS -X POST "$BASE_URL/api/v1/admin/cms/pages/import" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary "@$PAGES_FILE")

echo "=> server response:"
echo "$RESULT" | jq .
