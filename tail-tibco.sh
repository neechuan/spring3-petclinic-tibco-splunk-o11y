#!/usr/bin/env bash
#
# Tail logs from the TIBCO EMS broker container.
#
# Usage:
#   ./tail-tibco.sh [follow|tail|since] [arg]
#
# Commands:
#   follow          Follow logs continuously (default)
#   tail [N]        Show last N lines (default: 200)
#   since [DUR]     Show logs since a duration (default: 10m), e.g. 30s, 5m, 1h
#
# Examples:
#   ./tail-tibco.sh
#   ./tail-tibco.sh follow
#   ./tail-tibco.sh tail 500
#   ./tail-tibco.sh since 15m
set -euo pipefail
cd "$(dirname "$0")"

TIBCO_CONTAINER="${TIBCO_CONTAINER:-petclinic-tibco}"

usage() {
  cat <<'EOF'
Usage: ./tail-tibco.sh [follow|tail|since] [arg]

Commands:
  follow          Follow logs continuously (default)
  tail [N]        Show last N lines (default: 200)
  since [DUR]     Show logs since a duration (default: 10m)

Examples:
  ./tail-tibco.sh
  ./tail-tibco.sh follow
  ./tail-tibco.sh tail 500
  ./tail-tibco.sh since 15m
EOF
}

ensure_container_exists() {
  if ! podman container exists "$TIBCO_CONTAINER" 2>/dev/null; then
    echo "error: TIBCO container '$TIBCO_CONTAINER' does not exist." >&2
    echo "Start it with: ./run-all.sh tibco" >&2
    exit 1
  fi
}

cmd="${1:-follow}"
arg="${2:-}"

case "$cmd" in
  follow)
    ensure_container_exists
    echo "Following TIBCO logs from '$TIBCO_CONTAINER'..."
    exec podman logs -f "$TIBCO_CONTAINER"
    ;;
  tail)
    ensure_container_exists
    lines="${arg:-200}"
    [[ "$lines" =~ ^[0-9]+$ ]] || { echo "error: tail count must be a number" >&2; exit 1; }
    exec podman logs --tail "$lines" "$TIBCO_CONTAINER"
    ;;
  since)
    ensure_container_exists
    since="${arg:-10m}"
    exec podman logs --since "$since" "$TIBCO_CONTAINER"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "error: unknown command '$cmd'" >&2
    usage
    exit 1
    ;;
esac
