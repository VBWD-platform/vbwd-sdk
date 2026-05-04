#!/bin/bash
set -e

# Push all plugin source directories to their VBWD-platform repos.
# Run after review. Idempotent — safe to re-run.
#
# Usage: ./recipes/push-plugins.sh
#        ./recipes/push-plugins.sh ghrm          # push single backend plugin
#        ./recipes/push-plugins.sh fe-user chat   # push single fe-user plugin

push_plugin() {
  local dir="$1"
  local repo="$2"    # e.g. VBWD-platform/vbwd-plugin-ghrm
  local msg="${3:-initial: publish plugin source}"

  echo ""
  echo "── $repo"

  cd "$dir"

  # Stage everything (respects .gitignore)
  git add -A

  # Only commit if there's something staged
  if git diff --cached --quiet; then
    echo "  nothing to commit"
  else
    git commit -m "$msg"
  fi

  # Force-push: remote has only an auto-generated README commit from repo
  # creation; our local source is authoritative.
  git push -u origin main --force

  echo "  ✓ pushed"
  cd - > /dev/null
}

BACKEND="$(cd "$(dirname "$0")/../vbwd-backend" && pwd)"
FE_USER="$(cd "$(dirname "$0")/../vbwd-fe-user" && pwd)"
FE_ADMIN="$(cd "$(dirname "$0")/../vbwd-fe-admin" && pwd)"

# Filter mode: single plugin
if [ -n "$1" ]; then
  case "$1" in
    fe-user)
      push_plugin "$FE_USER/plugins/$2" "VBWD-platform/vbwd-fe-user-plugin-$2"
      exit 0
      ;;
    fe-admin)
      push_plugin "$FE_ADMIN/plugins/$2" "VBWD-platform/vbwd-fe-admin-plugin-$2"
      exit 0
      ;;
    *)
      push_plugin "$BACKEND/plugins/$1" "VBWD-platform/vbwd-plugin-$1"
      exit 0
      ;;
  esac
fi

# ── Backend plugins ───────────────────────────────────────────────────────────
# Note: multi-word directory slugs use underscores; GitHub repo slugs use
# dashes (e.g., mercado_pago → vbwd-plugin-mercado-pago).
echo "=== Backend plugins ==="
for plugin in analytics chat cms email ghrm mailchimp paypal stripe taro yookassa \
              c2p2 truemoney conekta promptpay meinchat; do
  push_plugin "$BACKEND/plugins/$plugin" "VBWD-platform/vbwd-plugin-$plugin"
done
for mapping in "mercado_pago:mercado-pago" "toss_payments:toss-payments"; do
  dir_slug="${mapping%%:*}"; gh_slug="${mapping##*:}"
  push_plugin "$BACKEND/plugins/$dir_slug" "VBWD-platform/vbwd-plugin-$gh_slug"
done

# ── fe-user plugins ───────────────────────────────────────────────────────────
echo ""
echo "=== fe-user plugins ==="
for slug in chat checkout cms ghrm landing1 paypal-payment stripe-payment taro \
            theme-switcher yookassa-payment \
            c2p2-payment truemoney-payment mercado-pago-payment \
            toss-payments-payment conekta-payment promptpay-payment \
            meinchat; do
  push_plugin "$FE_USER/plugins/$slug" "VBWD-platform/vbwd-fe-user-plugin-$slug"
done

# ── fe-admin plugins ──────────────────────────────────────────────────────────
echo ""
echo "=== fe-admin plugins ==="
for slug in analytics-widget cms-admin email-admin ghrm-admin taro-admin \
            c2p2-admin truemoney-admin mercado-pago-admin \
            toss-payments-admin conekta-admin promptpay-admin \
            meinchat-admin; do
  push_plugin "$FE_ADMIN/plugins/$slug" "VBWD-platform/vbwd-fe-admin-plugin-$slug"
done

echo ""
echo "Done. All plugins pushed."
