#!/usr/bin/env bash
# ============================================================
# validate-env.sh — Validate environment variables
# ============================================================
# Checks that all required env vars are present and not
# placeholder values. Optionally smoke-tests connections.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT/.env"

if [ ! -f "$ENV_FILE" ]; then
	echo "✗ $ENV_FILE not found."
	exit 1
fi

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

ERRORS=0
WARNS=0

check_var() {
	local name="$1"
	local value="${!name:-}"
	if [ -z "$value" ]; then
		echo "  ✗ $name — missing"
		ERRORS=$((ERRORS + 1))
		return
	fi
	if [[ "$value" == *"CHANGE_ME"* ]] || [[ "$value" == *"your-"* ]]; then
		echo "  ✗ $name — still placeholder"
		ERRORS=$((ERRORS + 1))
		return
	fi
	echo "  ✓ $name"
}

echo "=== Backend Required Variables ==="
check_var "DATABASE_URL"
check_var "JWT_SECRET"
check_var "JWT_EXPIRATION"
check_var "ACCSESS_TOKEN_NAME"
check_var "REFRESH_JWT_SECRET"
check_var "REFRESH_JWT_EXPIRATION"
check_var "REFRESH_TOKEN_NAME"
check_var "PASSWORD_PEPPER"
check_var "GOOGLE_CLIENT_ID"
check_var "GOOGLE_CLIENT_SECRET"
check_var "GOOGLE_CALLBACK_URL"
check_var "AWS_REGION"
check_var "AWS_ACCESS_KEY_ID"
check_var "AWS_SECRET_ACCESS_KEY"
check_var "AWS_S3_BUCKET_NAME"
check_var "AWS_S3_PUBLIC_URL"
check_var "NOVA_POS_API_KEY"
check_var "RESEND_API_KEY"
check_var "SERVICE_EMAIL"
check_var "FRONTEND_URL"
check_var "PORT"

echo ""
echo "=== Frontend Required Variables ==="
check_var "NEXT_PUBLIC_API_BASE_URL"
check_var "NEXT_PUBLIC_SITE_URL"

echo ""
echo "=== Connectivity Smoke Tests ==="

# MongoDB
if command -v mongosh &>/dev/null; then
	if mongosh "$DATABASE_URL" --eval "db.runCommand({ping:1})" --quiet &>/dev/null; then
		echo "  ✓ MongoDB — connected"
	else
		echo "  ✗ MongoDB — connection failed"
		ERRORS=$((ERRORS + 1))
	fi
else
	echo "  ⚠ MongoDB — mongosh not found, skipping"
	WARNS=$((WARNS + 1))
fi

# AWS S3
if command -v aws &>/dev/null; then
	if AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
		aws s3 ls "s3://$AWS_S3_BUCKET_NAME" --region "$AWS_REGION" &>/dev/null; then
		echo "  ✓ AWS S3 — bucket accessible"
	else
		echo "  ✗ AWS S3 — bucket not accessible"
		ERRORS=$((ERRORS + 1))
	fi
else
	echo "  ⚠ AWS CLI — not found, skipping S3 check"
	WARNS=$((WARNS + 1))
fi

echo ""
echo "=========================================="
if [ $ERRORS -gt 0 ]; then
	echo "RESULT: FAIL — $ERRORS error(s), $WARNS warning(s)"
	exit 1
else
	echo "RESULT: PASS — 0 errors, $WARNS warning(s)"
	exit 0
fi
