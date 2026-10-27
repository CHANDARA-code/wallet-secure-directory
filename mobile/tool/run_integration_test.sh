#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run_integration_test.sh [OPTIONS]

Runs the end-to-end mobile simulator integration tests against a private backend.

Options:
  --port <port>          Port for private backend (default: 3170)
  --device <udid>        Simulator UDID to target (default: creates dedicated iPhone 16)
  --keep-simulator       Do not delete the created simulator after test run
  --timeout <seconds>    Overall execution deadline in seconds (default: 900)
  -h, --help             Show this help message and exit

Environment Variables:
  MOBILE_DIR             Path to mobile app directory (default: repo mobile directory)
  SIM_RUNTIME            Simulator runtime identifier, for example com.apple.CoreSimulator.SimRuntime.iOS-18-3
                         (default: newest available iOS runtime; the test was verified on iOS 18.3)
EOF
}

TIMEOUT=900
for arg in "$@"; do
  if [ "$arg" = "--help" ] || [ "$arg" = "-h" ]; then
    usage
    exit 0
  fi
done

args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [ "${args[i]}" = "--timeout" ] && [ $((i+1)) -lt ${#args[@]} ]; then
    TIMEOUT="${args[i+1]}"
  fi
done

if [ -z "${_RUN_INTEGRATION_TEST_ALARM_SET:-}" ]; then
  export _RUN_INTEGRATION_TEST_ALARM_SET=1
  exec perl -e 'alarm shift; exec @ARGV' "$TIMEOUT" "$0" "$@"
fi

PORT=3170
DEVICE_ARG=""
KEEP_SIM=0

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --device)
      DEVICE_ARG="$2"
      shift 2
      ;;
    --keep-simulator)
      KEEP_SIM=1
      shift
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MOBILE_DIR="${MOBILE_DIR:-$REPO_ROOT/mobile}"
MOBILE_DIR="$(cd "$MOBILE_DIR" && pwd)"

BACKEND_PID=""
DB_DIR=""
BACKEND_LOG=""
DEVICE_UDID=""
CREATED_SIM=0

cleanup() {
  trap - EXIT INT TERM HUP ALRM
  if [ -n "$BACKEND_PID" ]; then
    kill -TERM "$BACKEND_PID" 2>/dev/null || true
    wait "$BACKEND_PID" 2>/dev/null || true
  fi
  if [ -n "$DB_DIR" ] && [ -d "$DB_DIR" ]; then
    rm -rf "$DB_DIR"
  fi
  if [ -n "$BACKEND_LOG" ] && [ -f "$BACKEND_LOG" ]; then
    rm -f "$BACKEND_LOG"
  fi
  if [ "$CREATED_SIM" -eq 1 ] && [ "$KEEP_SIM" -eq 0 ] && [ -n "$DEVICE_UDID" ]; then
    xcrun simctl shutdown "$DEVICE_UDID" 2>/dev/null || true
    xcrun simctl delete "$DEVICE_UDID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM HUP ALRM

if [ ! -d "$REPO_ROOT/backend/dist" ]; then
  (cd "$REPO_ROOT/backend" && npm run build)
fi

DB_DIR=$(mktemp -d)
DATABASE_PATH="$DB_DIR/wallet.db"
BACKEND_LOG="$DB_DIR/backend.log"
BETTER_AUTH_SECRET=$(openssl rand -base64 32 | tr -d '\n\r')
BETTER_AUTH_URL="http://localhost:$PORT"
TRUSTED_ORIGINS="http://localhost:5173"
TRUST_PROXY_HOPS="0"
NODE_ENV="development"

(cd "$REPO_ROOT/backend" && DATABASE_PATH="$DATABASE_PATH" npx drizzle-kit migrate >/dev/null)

ADMIN_EMAIL="admin@wallet.local"
ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
ADMIN_NAME="Admin"

(
  cd "$REPO_ROOT/backend" && \
  ADMIN_EMAIL="$ADMIN_EMAIL" \
  ADMIN_PASSWORD="$ADMIN_PASSWORD" \
  ADMIN_NAME="$ADMIN_NAME" \
  DATABASE_PATH="$DATABASE_PATH" \
  BETTER_AUTH_SECRET="$BETTER_AUTH_SECRET" \
  BETTER_AUTH_URL="$BETTER_AUTH_URL" \
  TRUSTED_ORIGINS="$TRUSTED_ORIGINS" \
  TRUST_PROXY_HOPS="$TRUST_PROXY_HOPS" \
  NODE_ENV="$NODE_ENV" \
  npx tsx scripts/seed-admin.ts >/dev/null
)

(
  cd "$REPO_ROOT/backend" && \
  PORT="$PORT" \
  DATABASE_PATH="$DATABASE_PATH" \
  BETTER_AUTH_SECRET="$BETTER_AUTH_SECRET" \
  BETTER_AUTH_URL="$BETTER_AUTH_URL" \
  TRUSTED_ORIGINS="$TRUSTED_ORIGINS" \
  TRUST_PROXY_HOPS="$TRUST_PROXY_HOPS" \
  NODE_ENV="$NODE_ENV" \
  exec node dist/main.js > "$BACKEND_LOG" 2>&1
) &
BACKEND_PID=$!

READY=0
for _ in $(seq 1 60); do
  if curl -s -f "http://localhost:${PORT}/api/health" >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 0.5
done

if [ "$READY" -ne 1 ]; then
  echo "Backend failed to become ready on port $PORT" >&2
  if [ -f "$BACKEND_LOG" ]; then
    cat "$BACKEND_LOG" >&2
  fi
  exit 1
fi

QA_EMAIL="qa@wallet.local"
QA_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)

SIGNUP_RESP=$(curl -s -X POST "http://localhost:${PORT}/api/auth/sign-up/email" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"QA User\",\"email\":\"${QA_EMAIL}\",\"password\":\"${QA_PASSWORD}\"}")

QA_USER_ID=$(node -e "console.log(JSON.parse(process.argv[1]).user?.id || '')" "$SIGNUP_RESP")
if [ -z "$QA_USER_ID" ]; then
  echo "Failed to create QA user" >&2
  exit 1
fi

ADMIN_LOGIN_RESP=$(curl -s -X POST "http://localhost:${PORT}/api/auth/sign-in/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}")

ADMIN_TOKEN=$(node -e "console.log(JSON.parse(process.argv[1]).token || '')" "$ADMIN_LOGIN_RESP")
if [ -z "$ADMIN_TOKEN" ]; then
  echo "Failed to authenticate admin" >&2
  exit 1
fi

ISSUE_RESP=$(curl -s -X POST "http://localhost:${PORT}/api/admin/documents" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -d "{\"userId\":\"${QA_USER_ID}\",\"type\":\"driving_license\",\"data\":{\"fullName\":\"QA User\",\"dateOfBirth\":\"1995-04-12\",\"address\":\"12 Street 51, Phnom Penh\",\"nationality\":\"KH\",\"issuingAuthority\":\"Ministry of Public Works and Transport\",\"licenseClasses\":[\"B\",\"C1\"],\"restrictions\":[\"CORRECTIVE_LENSES\"],\"issueDate\":\"2026-01-15\",\"expiryDate\":\"2036-01-14\"}}")

DOC_ID=$(node -e "console.log(JSON.parse(process.argv[1]).id || '')" "$ISSUE_RESP")
if [ -z "$DOC_ID" ]; then
  echo "Failed to issue driving license to QA user" >&2
  exit 1
fi

if [ -n "$DEVICE_ARG" ]; then
  DEVICE_UDID="$DEVICE_ARG"
  CREATED_SIM=0
else
  DEVICE_NAME="IT-iPhone16-$(date +%s)-$RANDOM"
  RUNTIME_ID="${SIM_RUNTIME:-}"
  if [ -z "$RUNTIME_ID" ]; then
    RUNTIME_ID=$(xcrun simctl list runtimes available -j | node -e "const r=JSON.parse(require('fs').readFileSync(0,'utf8')).runtimes.filter(x=>x.platform==='iOS'&&x.isAvailable);r.sort((a,b)=>a.version.localeCompare(b.version,undefined,{numeric:true}));console.log(r.length?r[r.length-1].identifier:'')")
  fi
  if [ -z "$RUNTIME_ID" ]; then
    echo "No available iOS simulator runtime found" >&2
    exit 1
  fi
  echo "Using simulator runtime: $RUNTIME_ID"
  DEVICE_UDID=$(xcrun simctl create "$DEVICE_NAME" com.apple.CoreSimulator.SimDeviceType.iPhone-16 "$RUNTIME_ID")
  CREATED_SIM=1
fi

xcrun simctl boot "$DEVICE_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_UDID" -b

(
  cd "$MOBILE_DIR" && \
  flutter test integration_test/e2e_faked_biometrics_simulator_test.dart \
    -d "$DEVICE_UDID" \
    --dart-define=API_BASE_URL="http://localhost:$PORT" \
    --dart-define=QA_EMAIL="$QA_EMAIL" \
    --dart-define=QA_PASSWORD="$QA_PASSWORD"
)
