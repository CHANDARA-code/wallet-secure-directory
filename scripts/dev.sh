#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$ROOT_DIR/scripts/.dev.pids"

print_usage() {
  cat << 'EOF'
Usage: dev.sh [OPTIONS]

Run the development environment for the Secure Digital Identity Wallet.

Options:
  -h, --help               Show this help message and exit
  --docs                   Start Mintlify documentation server
  --seed-admin EMAIL       Seed an admin user with the given email (prompts for password)
  --port PORT              Backend port (default: 3000 or $PORT)
  --admin-port PORT        Admin portal port (default: 5173 or $ADMIN_PORT)
  --docs-port PORT         Docs server port (default: 3333 or $DOCS_PORT)
  --db-path PATH           SQLite database path (default: from .env or ./data/wallet.db)
  --stop                   Stop running services previously started by dev.sh
EOF
}

START_DOCS=false
SEED_ADMIN_EMAIL=""
BACKEND_PORT="${PORT:-3000}"
ADMIN_PORT="${ADMIN_PORT:-5173}"
DOCS_PORT="${DOCS_PORT:-3333}"
DB_PATH="${DATABASE_PATH:-}"
DO_STOP=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      print_usage
      exit 0
      ;;
    --docs)
      START_DOCS=true
      shift
      ;;
    --seed-admin)
      if [[ $# -lt 2 || "$2" == --* ]]; then
        echo "Error: --seed-admin requires an email address." >&2
        exit 1
      fi
      SEED_ADMIN_EMAIL="$2"
      shift 2
      ;;
    --port)
      if [[ $# -lt 2 ]]; then
        echo "Error: --port requires a port number." >&2
        exit 1
      fi
      BACKEND_PORT="$2"
      shift 2
      ;;
    --admin-port|--vite-port)
      if [[ $# -lt 2 ]]; then
        echo "Error: $1 requires a port number." >&2
        exit 1
      fi
      ADMIN_PORT="$2"
      shift 2
      ;;
    --docs-port)
      if [[ $# -lt 2 ]]; then
        echo "Error: --docs-port requires a port number." >&2
        exit 1
      fi
      DOCS_PORT="$2"
      shift 2
      ;;
    --db-path)
      if [[ $# -lt 2 ]]; then
        echo "Error: --db-path requires a database file path." >&2
        exit 1
      fi
      DB_PATH="$2"
      shift 2
      ;;
    --stop)
      DO_STOP=true
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      print_usage >&2
      exit 1
      ;;
  esac
done

if [[ "$DO_STOP" == "true" ]]; then
  if [[ -f "$PID_FILE" ]]; then
    STOPPED=0
    while read -r pid; do
      if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        STOPPED=$((STOPPED + 1))
      fi
    done < "$PID_FILE"
    rm -f "$PID_FILE"
    echo "Stopped $STOPPED service(s)."
  else
    echo "No running services found (no $PID_FILE)."
  fi
  exit 0
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Error: Node.js is not installed or not in PATH." >&2
  exit 1
fi

MISSING_MODULES=false
if [[ ! -d "$ROOT_DIR/backend/node_modules" ]]; then
  echo "Error: backend/node_modules is missing." >&2
  echo "To install backend dependencies, run: (cd backend && npm install)" >&2
  MISSING_MODULES=true
fi

if [[ ! -d "$ROOT_DIR/admin/node_modules" ]]; then
  echo "Error: admin/node_modules is missing." >&2
  echo "To install admin dependencies, run: (cd admin && npm install)" >&2
  MISSING_MODULES=true
fi

if [[ "$MISSING_MODULES" == "true" ]]; then
  exit 1
fi

ENV_FILE="$ROOT_DIR/backend/.env"
EXAMPLE_FILE="$ROOT_DIR/backend/.env.example"

if [[ ! -f "$ENV_FILE" ]]; then
  if [[ ! -f "$EXAMPLE_FILE" ]]; then
    echo "Error: $EXAMPLE_FILE not found." >&2
    exit 1
  fi
  GENERATED_SECRET="$(openssl rand -base64 32 | tr -d '\n')"
  sed "s|^BETTER_AUTH_SECRET=.*|BETTER_AUTH_SECRET=${GENERATED_SECRET}|" "$EXAMPLE_FILE" > "$ENV_FILE"
  echo "Created backend/.env with generated BETTER_AUTH_SECRET."
fi

ADMIN_PASSWORD=""
if [[ -n "$SEED_ADMIN_EMAIL" ]]; then
  printf "Enter password for admin (%s): " "$SEED_ADMIN_EMAIL"
  read -r -s ADMIN_PASSWORD
  echo ""
  if [[ -z "$ADMIN_PASSWORD" ]]; then
    echo "Error: Admin password cannot be empty." >&2
    exit 1
  fi
fi

if [[ -n "$DB_PATH" ]]; then
  mkdir -p "$(dirname "$DB_PATH")"
  (cd "$ROOT_DIR/backend" && DATABASE_PATH="$DB_PATH" npm run db:migrate)
else
  (cd "$ROOT_DIR/backend" && npm run db:migrate)
fi

if [[ -n "$SEED_ADMIN_EMAIL" ]]; then
  if [[ -n "$DB_PATH" ]]; then
    (cd "$ROOT_DIR/backend" && ADMIN_EMAIL="$SEED_ADMIN_EMAIL" ADMIN_PASSWORD="$ADMIN_PASSWORD" ADMIN_NAME="Admin" DATABASE_PATH="$DB_PATH" npm run seed:admin)
  else
    (cd "$ROOT_DIR/backend" && ADMIN_EMAIL="$SEED_ADMIN_EMAIL" ADMIN_PASSWORD="$ADMIN_PASSWORD" ADMIN_NAME="Admin" npm run seed:admin)
  fi
fi

(cd "$ROOT_DIR/backend" && npm run build)

PIDS=()

cleanup() {
  trap - INT TERM EXIT
  echo ""
  echo "Stopping services..."
  if [[ ${#PIDS[@]} -gt 0 ]]; then
    for pid in "${PIDS[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
      fi
    done
    wait "${PIDS[@]}" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
  echo "Services stopped."
}

trap cleanup INT TERM EXIT

mkdir -p "$ROOT_DIR/scripts"
: > "$PID_FILE"

BACKEND_ENV=(
  "PORT=$BACKEND_PORT"
  "BETTER_AUTH_URL=http://localhost:$BACKEND_PORT"
  "TRUSTED_ORIGINS=http://localhost:$ADMIN_PORT,http://localhost:5173"
)
if [[ -n "$DB_PATH" ]]; then
  BACKEND_ENV+=("DATABASE_PATH=$DB_PATH")
fi

(
  cd "$ROOT_DIR/backend"
  exec env "${BACKEND_ENV[@]}" node dist/main.js
) &
BACKEND_PID=$!
PIDS+=("$BACKEND_PID")
echo "$BACKEND_PID" >> "$PID_FILE"

(
  cd "$ROOT_DIR/admin"
  exec env VITE_API_PROXY_TARGET="http://localhost:$BACKEND_PORT" npx vite --port "$ADMIN_PORT"
) &
ADMIN_PID=$!
PIDS+=("$ADMIN_PID")
echo "$ADMIN_PID" >> "$PID_FILE"

if [[ "$START_DOCS" == "true" ]]; then
  (
    cd "$ROOT_DIR/backend/docs"
    exec npx -y mint@latest dev --port "$DOCS_PORT" --no-open
  ) &
  DOCS_PID=$!
  PIDS+=("$DOCS_PID")
  echo "$DOCS_PID" >> "$PID_FILE"
fi

HEALTH_URL="http://localhost:$BACKEND_PORT/api/health"
echo "Waiting for backend at $HEALTH_URL..."
MAX_ATTEMPTS=30
ATTEMPT=0
READY=false

while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
  if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
    echo "Error: Backend process exited unexpectedly." >&2
    exit 1
  fi
  if curl -s -f "$HEALTH_URL" >/dev/null 2>&1; then
    READY=true
    break
  fi
  sleep 1
  ATTEMPT=$((ATTEMPT + 1))
done

if [[ "$READY" != "true" ]]; then
  echo "Error: Backend failed to respond at $HEALTH_URL within 30 seconds." >&2
  exit 1
fi

echo ""
echo "============================================================"
echo " Secure Digital Identity Wallet Development Services"
echo "============================================================"
echo " Backend API:   http://localhost:$BACKEND_PORT"
echo " Health check:  http://localhost:$BACKEND_PORT/api/health"
echo " Admin Portal:  http://localhost:$ADMIN_PORT"
if [[ "$START_DOCS" == "true" ]]; then
  echo " Documentation: http://localhost:$DOCS_PORT"
fi
echo "============================================================"
echo "Press Ctrl-C to stop all services."
echo ""

wait
