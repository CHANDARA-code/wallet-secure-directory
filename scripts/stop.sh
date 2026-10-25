#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$ROOT_DIR/scripts/.dev.pids"

print_usage() {
  cat << 'EOF'
Usage: stop.sh [OPTIONS]

Stop development environment services for the Secure Digital Identity Wallet.

Options:
  -h, --help    Show this help message and exit
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  print_usage
  exit 0
fi

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
