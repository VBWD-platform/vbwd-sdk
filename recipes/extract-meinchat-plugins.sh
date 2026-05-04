#!/usr/bin/env bash
#
# extract-meinchat-plugins.sh — split the three meinchat plugin trees out
# of the SDK monorepo into three standalone GitHub repos, per the
# `feedback_plugins_always_in_own_repos.md` rule.
#
# Why this is a separate script and not run automatically:
# - Creates new public GitHub repos (visible to others).
# - Force-rewrites git history via `git filter-repo`.
# - Pushes to remotes.
#
# All three actions need explicit human go-ahead. Run this only after
# you've reviewed the targets below.
#
# Prereqs:
#   - `git filter-repo` installed (https://github.com/newren/git-filter-repo)
#   - `gh` authenticated (`gh auth status` must show logged-in)
#   - You have admin rights on the VBWD-platform GitHub org
#
# Usage:
#   bash recipes/extract-meinchat-plugins.sh
#
# Targets:
#   github.com/VBWD-platform/vbwd-plugin-meinchat
#   github.com/VBWD-platform/vbwd-fe-user-plugin-meinchat
#   github.com/VBWD-platform/vbwd-fe-admin-plugin-meinchat

set -euo pipefail

GH_ORG="${GH_ORG:-VBWD-platform}"
SDK_ROOT="$(git rev-parse --show-toplevel)"
WORK_DIR="${WORK_DIR:-/tmp/meinchat-extract-$$}"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "=================================================================="
echo " meinchat plugin extraction — three repos"
echo " SDK root: $SDK_ROOT"
echo " Workdir : $WORK_DIR"
echo " GH org  : $GH_ORG"
echo "=================================================================="

extract_one() {
    local subdir_in_sdk=$1     # path inside the SDK monorepo
    local repo_name=$2          # github repo name
    local target_subdir=${3:-}  # optional: only this subdir of subdir_in_sdk

    echo ""
    echo "── extracting $subdir_in_sdk → $GH_ORG/$repo_name ──"

    rm -rf "$repo_name"
    git clone "$SDK_ROOT" "$repo_name"
    cd "$repo_name"

    # Drop everything except the target plugin path. `--to-subdirectory-filter .`
    # promotes the plugin's contents to repo root.
    if [[ -n "$target_subdir" ]]; then
        git filter-repo --force \
            --subdirectory-filter "$subdir_in_sdk/$target_subdir" \
            --refs main
    else
        git filter-repo --force \
            --subdirectory-filter "$subdir_in_sdk" \
            --refs main
    fi

    if gh repo view "$GH_ORG/$repo_name" >/dev/null 2>&1; then
        echo "  Repo $GH_ORG/$repo_name already exists; pushing to existing remote."
        git remote remove origin 2>/dev/null || true
        git remote add origin "git@github.com:$GH_ORG/$repo_name.git"
    else
        echo "  Creating new public repo $GH_ORG/$repo_name…"
        gh repo create "$GH_ORG/$repo_name" --public --source=. --remote=origin
    fi

    git push -u origin main --force-with-lease

    cd "$WORK_DIR"
}

# 1. Backend bundle
extract_one "vbwd-backend/plugins/meinchat" "vbwd-plugin-meinchat"

# 2. fe-user dashboard plugin
extract_one "vbwd-fe-user/plugins/meinchat" "vbwd-fe-user-plugin-meinchat"

# 3. fe-admin moderation plugin
extract_one "vbwd-fe-admin/plugins/meinchat-admin" "vbwd-fe-admin-plugin-meinchat"

echo ""
echo "=================================================================="
echo " ✅ All three repos pushed."
echo ""
echo " Next steps (manual):"
echo "   - Tag each repo v1.0.0:"
echo "       cd $WORK_DIR/vbwd-plugin-meinchat       && git tag v1.0.0 && git push --tags"
echo "       cd $WORK_DIR/vbwd-fe-user-plugin-meinchat   && git tag v1.0.0 && git push --tags"
echo "       cd $WORK_DIR/vbwd-fe-admin-plugin-meinchat  && git tag v1.0.0 && git push --tags"
echo ""
echo "   - Add to recipes/push-plugins.sh + recipes/ci-status.sh EXPECTED list."
echo ""
echo "   - Wire CI from the stripe-style tests.yml template (vbwd-plugin-stripe)."
echo "=================================================================="
