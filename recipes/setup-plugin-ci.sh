#!/bin/bash
set -e

# Creates .github/workflows/tests.yml locally inside every plugin directory
# AND syncs it to the corresponding VBWD-platform GitHub repo.
# Idempotent — safe to re-run.

ORG="VBWD-platform"
SDK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$SDK_ROOT/vbwd-backend"
FE_USER="$SDK_ROOT/vbwd-fe-user"
FE_ADMIN="$SDK_ROOT/vbwd-fe-admin"

# ── Templates (PLUGIN_NAME is the substitution token) ─────────────────────────

cat << 'YAML' > /tmp/vbwd_backend_workflow.yml
name: Tests

on:
  push:
    branches: ['*']
  pull_request:
    branches: [main]
  workflow_dispatch:

jobs:
  ci:
    name: CI — PLUGIN_NAME
    runs-on: ubuntu-latest

    steps:
      # ── 1. Clone vbwd-backend ──────────────────────────────────────────────
      - name: Clone vbwd-backend
        uses: actions/checkout@v4
        with:
          repository: VBWD-platform/vbwd-backend
          path: vbwd-backend

      # ── 2. Clone plugin directly into vbwd-backend/plugins/PLUGIN_NAME ────
      - name: Clone plugin
        uses: actions/checkout@v4
        with:
          path: vbwd-backend/plugins/PLUGIN_NAME

      # ── 3. Style checks (black · flake8 · mypy) ───────────────────────────
      - name: Set up Python 3.11
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
          cache: 'pip'
          cache-dependency-path: vbwd-backend/requirements.txt

      - name: Install Python dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r vbwd-backend/requirements.txt

      - name: Style check — Black
        run: |
          black --check --diff \
            vbwd-backend/plugins/PLUGIN_NAME/ \
            --exclude='/(\.git|\.github|__pycache__|\.pytest_cache)/'

      - name: Style check — Flake8
        run: |
          flake8 vbwd-backend/plugins/PLUGIN_NAME/ \
            --max-line-length=120 \
            --extend-ignore=E203,W503 \
            --exclude=.git,.github,__pycache__,.pytest_cache

      - name: Style check — Mypy
        run: |
          PLUGIN_SRC=vbwd-backend/plugins/PLUGIN_NAME/src
          if [ -d "$PLUGIN_SRC" ]; then
            mypy "$PLUGIN_SRC" \
              --ignore-missing-imports \
              --no-error-summary \
              --python-version=3.11
          else
            echo "No src/ directory — skipping mypy."
          fi

      # ── 4. Start docker compose stack (API + postgres + redis) ────────────
      - name: Start services
        working-directory: vbwd-backend
        run: docker compose up -d --build

      - name: Wait for API health
        run: |
          echo "Waiting for API..."
          for i in $(seq 1 30); do
            if curl -sf http://localhost:5000/api/v1/health > /dev/null 2>&1; then
              echo "API ready after ${i} attempts."
              break
            fi
            [ $i -eq 30 ] && echo "API did not become healthy." && exit 1
            sleep 3
          done

      # ── 5. Install and activate plugin ────────────────────────────────────
      - name: Enable plugin
        working-directory: vbwd-backend
        run: |
          docker compose exec -T api flask plugins enable PLUGIN_NAME \
            && echo "Plugin PLUGIN_NAME enabled." \
            || echo "Plugin PLUGIN_NAME already enabled or not registerable — continuing."

      # ── 6. Unit tests ──────────────────────────────────────────────────────
      - name: Run unit tests
        working-directory: vbwd-backend
        run: |
          mkdir -p test-results
          if [ -d "plugins/PLUGIN_NAME/tests/unit" ]; then
            TESTS_DIR="plugins/PLUGIN_NAME/tests/unit/"
          elif [ -d "plugins/PLUGIN_NAME/tests" ]; then
            TESTS_DIR="plugins/PLUGIN_NAME/tests/"
            IGNORE="--ignore=plugins/PLUGIN_NAME/tests/integration/"
          else
            echo "No unit tests — skipping."
            exit 0
          fi
          docker compose --profile test run --rm -T test \
            pytest $TESTS_DIR ${IGNORE:-} \
            -v --tb=short \
            --junit-xml=/app/test-results/unit.xml

      # ── 7. Integration tests ───────────────────────────────────────────────
      - name: Run integration tests
        if: always()
        working-directory: vbwd-backend
        run: |
          if [ -d "plugins/PLUGIN_NAME/tests/integration" ]; then
            docker compose --profile test run --rm -T test \
              pytest plugins/PLUGIN_NAME/tests/integration/ \
              -v --tb=short \
              --junit-xml=/app/test-results/integration.xml
          else
            echo "No integration tests — skipping."
          fi

      # ── 8. Upload artifacts ────────────────────────────────────────────────
      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results-PLUGIN_NAME-${{ github.run_number }}
          path: vbwd-backend/test-results/
          if-no-files-found: ignore
          retention-days: 14

      # ── 9. Cleanup ─────────────────────────────────────────────────────────
      - name: Cleanup
        if: always()
        working-directory: vbwd-backend
        run: docker compose down -v
YAML

cat << 'YAML' > /tmp/vbwd_fe_user_workflow.yml
name: Tests

on:
  push:
    branches: ['*']
  pull_request:
    branches: [main]
  workflow_dispatch:

jobs:
  test:
    name: Unit Tests
    runs-on: ubuntu-latest
    steps:
      - name: Checkout plugin
        uses: actions/checkout@v4
        with:
          path: plugin-src

      - name: Checkout vbwd-fe-user
        uses: actions/checkout@v4
        with:
          repository: VBWD-platform/vbwd-fe-user
          path: vbwd-fe-user
          submodules: recursive

      - name: Overlay plugin source
        run: cp -r plugin-src/. vbwd-fe-user/plugins/PLUGIN_NAME/

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: vbwd-fe-user/package-lock.json

      - name: Build vbwd-fe-core submodule
        run: |
          cd vbwd-fe-user/vbwd-fe-core
          npm install
          npm run build

      - name: Install dependencies
        run: |
          cd vbwd-fe-user
          npm install

      - name: Run plugin tests
        run: |
          cd vbwd-fe-user
          if find plugins/PLUGIN_NAME -name "*.spec.ts" -o -name "*.test.ts" | grep -q .; then
            npx vitest run plugins/PLUGIN_NAME --reporter=verbose
          else
            echo "No tests found for PLUGIN_NAME — skipping."
          fi
YAML

cat << 'YAML' > /tmp/vbwd_fe_admin_workflow.yml
name: Tests

on:
  push:
    branches: ['*']
  pull_request:
    branches: [main]
  workflow_dispatch:

jobs:
  test:
    name: Unit Tests
    runs-on: ubuntu-latest
    steps:
      - name: Checkout plugin
        uses: actions/checkout@v4
        with:
          path: plugin-src

      - name: Checkout vbwd-fe-admin
        uses: actions/checkout@v4
        with:
          repository: VBWD-platform/vbwd-fe-admin
          path: vbwd-fe-admin
          submodules: recursive

      - name: Overlay plugin source
        run: cp -r plugin-src/. vbwd-fe-admin/plugins/PLUGIN_NAME/

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: vbwd-fe-admin/package-lock.json

      - name: Build vbwd-fe-core submodule
        run: |
          cd vbwd-fe-admin/vbwd-fe-core
          npm install
          npm run build

      - name: Install dependencies
        run: |
          cd vbwd-fe-admin
          npm install

      - name: Run plugin tests
        run: |
          cd vbwd-fe-admin
          if find plugins/PLUGIN_NAME -name "*.spec.ts" -o -name "*.test.ts" | grep -q .; then
            npx vitest run plugins/PLUGIN_NAME --reporter=verbose
          else
            echo "No tests found for PLUGIN_NAME — skipping."
          fi
YAML

# ── Core function ─────────────────────────────────────────────────────────────

write_and_push() {
  local plugin_dir="$1"   # absolute path to plugin directory
  local repo="$2"          # e.g. VBWD-platform/vbwd-plugin-ghrm
  local plugin="$3"        # plugin slug
  local template="$4"      # backend | fe_user | fe_admin

  local template_file="/tmp/vbwd_${template}_workflow.yml"
  local workflow_dir="$plugin_dir/.github/workflows"
  local workflow_file="$workflow_dir/tests.yml"

  # ── 1. Write locally ────────────────────────────────────────────────────────
  mkdir -p "$workflow_dir"
  sed "s/PLUGIN_NAME/${plugin}/g" "$template_file" > "$workflow_file"
  echo "  ✓ written  $workflow_file"

  # ── 2. Push to GitHub ───────────────────────────────────────────────────────
  local content
  content=$(base64 < "$workflow_file" | tr -d '\n')

  local sha
  sha=$(gh api "repos/${repo}/contents/.github/workflows/tests.yml" \
    --jq '.sha' 2>/dev/null || echo "")

  if [ -n "$sha" ]; then
    gh api "repos/${repo}/contents/.github/workflows/tests.yml" \
      --method PUT \
      -f message="ci: add unit + integration tests workflow" \
      -f content="${content}" \
      -f sha="${sha}" \
      --silent && echo "  ✓ synced  github.com/${repo}" || echo "  ✗ FAILED  github.com/${repo}"
  else
    gh api "repos/${repo}/contents/.github/workflows/tests.yml" \
      --method PUT \
      -f message="ci: add unit + integration tests workflow" \
      -f content="${content}" \
      --silent && echo "  ✓ synced  github.com/${repo}" || echo "  ✗ FAILED  github.com/${repo}"
  fi
}

# ── Backend plugins ───────────────────────────────────────────────────────────

echo ""
echo "=== Backend plugins ==="
for plugin in analytics chat cms email ghrm mailchimp paypal stripe taro yookassa; do
  echo ""
  echo "── $plugin"
  write_and_push \
    "$BACKEND/plugins/$plugin" \
    "$ORG/vbwd-plugin-$plugin" \
    "$plugin" \
    "backend"
done

# ── fe-user plugins ───────────────────────────────────────────────────────────

echo ""
echo "=== fe-user plugins ==="
for slug in chat checkout cms ghrm landing1 paypal-payment stripe-payment taro theme-switcher yookassa-payment; do
  echo ""
  echo "── $slug"
  write_and_push \
    "$FE_USER/plugins/$slug" \
    "$ORG/vbwd-fe-user-plugin-$slug" \
    "$slug" \
    "fe_user"
done

# ── fe-admin plugins ──────────────────────────────────────────────────────────

echo ""
echo "=== fe-admin plugins ==="
for slug in analytics-widget; do
  echo ""
  echo "── $slug"
  write_and_push \
    "$FE_ADMIN/plugins/$slug" \
    "$ORG/vbwd-fe-admin-plugin-$slug" \
    "$slug" \
    "fe_admin"
done

# cms-admin: local dir is cms-admin, remote repo is vbwd-fe-admin-plugin-cms
echo ""
echo "── cms-admin"
write_and_push \
  "$FE_ADMIN/plugins/cms-admin" \
  "$ORG/vbwd-fe-admin-plugin-cms" \
  "cms-admin" \
  "fe_admin"

# email-admin: local dir is email-admin, remote repo is vbwd-fe-admin-plugin-email
echo ""
echo "── email-admin"
write_and_push \
  "$FE_ADMIN/plugins/email-admin" \
  "$ORG/vbwd-fe-admin-plugin-email" \
  "email-admin" \
  "fe_admin"

# ghrm-admin: local dir is ghrm-admin, remote repo is vbwd-fe-admin-plugin-ghrm
echo ""
echo "── ghrm-admin"
write_and_push \
  "$FE_ADMIN/plugins/ghrm-admin" \
  "$ORG/vbwd-fe-admin-plugin-ghrm" \
  "ghrm-admin" \
  "fe_admin"

# taro-admin: local dir is taro-admin, remote repo is vbwd-fe-admin-plugin-taro
echo ""
echo "── taro-admin"
write_and_push \
  "$FE_ADMIN/plugins/taro-admin" \
  "$ORG/vbwd-fe-admin-plugin-taro" \
  "taro-admin" \
  "fe_admin"

echo ""
echo "Done. 25 plugins — workflow files written locally and synced to GitHub."
