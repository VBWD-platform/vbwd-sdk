#!/bin/bash
# Show the latest GitHub Actions run for every VBWD-platform repo.
# Usage: ./recipes/ci-status.sh

ORG="VBWD-platform"

# ── Expected plugin repos ─────────────────────────────────────────────────────
# New plugin repos scaffolded locally that should exist on GitHub. Repos in
# this list that are NOT found in the org surface as "not created" (magenta)
# so you can tell at a glance which still need `gh repo create`.
EXPECTED=(
  # Sprint 31 — 2C2P (ASEAN aggregator)
  vbwd-plugin-c2p2
  vbwd-fe-user-plugin-c2p2-payment
  vbwd-fe-admin-plugin-c2p2-admin
  # Sprint 32 — TrueMoney (Thailand direct)
  vbwd-plugin-truemoney
  vbwd-fe-user-plugin-truemoney-payment
  vbwd-fe-admin-plugin-truemoney-admin
  # Sprint 33 — Mercado Pago (LATAM)
  vbwd-plugin-mercado-pago
  vbwd-fe-user-plugin-mercado-pago-payment
  vbwd-fe-admin-plugin-mercado-pago-admin
  # Sprint 34 — Toss Payments (Korea)
  vbwd-plugin-toss-payments
  vbwd-fe-user-plugin-toss-payments-payment
  vbwd-fe-admin-plugin-toss-payments-admin
  # Sprint 35 — Conekta (Mexico)
  vbwd-plugin-conekta
  vbwd-fe-user-plugin-conekta-payment
  vbwd-fe-admin-plugin-conekta-admin
  # Sprint 41 — PromptPay (Thailand direct)
  vbwd-plugin-promptpay
  vbwd-fe-user-plugin-promptpay-payment
  vbwd-fe-admin-plugin-promptpay-admin
  # Sprint 57 — meinchat (nickname directory + messaging + token transfer)
  vbwd-plugin-meinchat
  vbwd-fe-user-plugin-meinchat
  vbwd-fe-admin-plugin-meinchat
)

# ── Colours ───────────────────────────────────────────────────────────────────
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
WHITE="\033[37m"
MAGENTA="\033[35m"

# ── Header ────────────────────────────────────────────────────────────────────
printf "${BOLD}${WHITE}%-45s  %-22s  %-15s  %s${RESET}\n" "REPO" "STATUS/CONCLUSION" "BRANCH" "DATE"
printf "${DIM}%-45s  %-22s  %-15s  %s${RESET}\n"          "----" "-----------------" "------" "----"

# ── Gather repo list (org discovery ∪ expected, deduped) ──────────────────────
discovered=$(gh api "orgs/${ORG}/repos?per_page=100" --jq '.[].name' 2>/dev/null)
expected_list=$(printf '%s\n' "${EXPECTED[@]}")
all_repos=$(printf '%s\n%s\n' "$discovered" "$expected_list" | awk 'NF' | sort -u)

# ── Rows ──────────────────────────────────────────────────────────────────────
for repo in $all_repos; do
  # `gh api` writes error JSON to stdout on HTTP failure (404 etc.), so we
  # must also check the exit code — not just `-z`.
  result=$(gh api "repos/${ORG}/${repo}/actions/runs?per_page=1" \
    --jq '.workflow_runs[0] | [.status, .conclusion, .head_branch, (.updated_at | split("T")[0])] | @tsv' 2>/dev/null)
  rc=$?

  if [ $rc -ne 0 ] || [ -z "$result" ]; then
    # Disambiguate "repo exists, no CI yet" from "repo not on GitHub".
    if gh api "repos/${ORG}/${repo}" >/dev/null 2>&1; then
      printf "%-45s  ${DIM}%s${RESET}\n" "$repo" "— no runs"
    else
      printf "${MAGENTA}%-45s${RESET}  ${YELLOW}%s${RESET}\n" "$repo" "not created"
    fi
    continue
  fi

  run_status=$(echo "$result" | cut -f1)
  conclusion=$(echo "$result" | cut -f2)
  branch=$(echo "$result"     | cut -f3)
  date=$(echo "$result"       | cut -f4)

  label="${run_status}/${conclusion}"

  # Colour the status/conclusion cell
  if   [ "$conclusion" = "success" ];    then color="$GREEN"
  elif [ "$conclusion" = "failure" ];    then color="$RED"
  elif [ "$conclusion" = "cancelled" ];  then color="$YELLOW"
  elif [ "$run_status" = "in_progress" ]; then color="$CYAN"
  else                                        color="$DIM"
  fi

  # Dim the repo name for non-main branches
  if [ "$branch" = "main" ]; then repo_color="$WHITE"; else repo_color="$DIM"; fi

  printf "${repo_color}%-45s${RESET}  ${color}%-22s${RESET}  ${DIM}%-15s${RESET}  %s\n" \
    "$repo" "$label" "$branch" "$date"
done
