#!/usr/bin/env bash
# ============================================================
# clone-all.sh — Clone Fillando child repositories
# Idempotent: safe to re-run; skips repos that already exist.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"

GITHUB_HOST="github_vvbogdanovih"
ORG="vvbogdanovih"
BRANCH="main"

declare -A REPOS=(
	[fillando-be]="fillando-be"
	[fillando-fe]="fillando-fe"
)

for dir in "${!REPOS[@]}"; do
	repo="${REPOS[$dir]}"
	target="$ROOT/$dir"

	if [ -d "$target/.git" ]; then
		echo "✓ $dir already cloned — skipping"
		continue
	fi

	echo "→ Cloning $repo into $dir …"
	git clone --branch "$BRANCH" "git@${GITHUB_HOST}:${ORG}/${repo}.git" "$target"
	echo "✓ $dir cloned"
done

echo ""
echo "Done. Run 'bash scripts/sync-env.sh' to distribute environment variables."
