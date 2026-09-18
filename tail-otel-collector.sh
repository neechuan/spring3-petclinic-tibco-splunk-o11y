#!/usr/bin/env bash
#
# Tail logs from the local Splunk OpenTelemetry Collector container.
#
# Usage:
#   ./tail-otel-collector.sh [--debug] [follow|tail|since] [arg]
#
# Commands:
#   follow          Follow logs continuously (default)
#   tail [N]        Show last N lines (default: 200)
#   since [DUR]     Show logs since a duration (default: 10m), e.g. 30s, 5m, 1h
#
# Options:
#   --debug         Restart the Collector with OTEL_COLLECTOR_LOG_LEVEL=debug before tailing
#
# Examples:
#   ./tail-otel-collector.sh
#   ./tail-otel-collector.sh --debug
#   ./tail-otel-collector.sh tail 500
#   ./tail-otel-collector.sh --debug since 15m
set -euo pipefail
cd "$(dirname "$0")"

CONTAINER_NAME="${SPLUNK_COLLECTOR_NAME:-splunk-otel-collector}"
debug=0

usage() {
  cat <<'EOF'
Usage: ./tail-otel-collector.sh [--debug] [follow|tail|since] [arg]

Commands:
  follow          Follow logs continuously (default)
  tail [N]        Show last N lines (default: 200)
  since [DUR]     Show logs since a duration (default: 10m)

Options:
  --debug         Restart the Collector with OTEL_COLLECTOR_LOG_LEVEL=debug before tailing

Examples:
  ./tail-otel-collector.sh
  ./tail-otel-collector.sh --debug
  ./tail-otel-collector.sh tail 500
  ./tail-otel-collector.sh --debug since 15m
EOF
}

while [ "${1:-}" = "--debug" ]; do
  debug=1
  shift
done

ensure_container_exists() {
  if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
    echo "error: OTel Collector container '$CONTAINER_NAME' does not exist." >&2
    echo "Start it with: ./run-collector.sh start" >&2
    exit 1
  fi
}

if [ "$debug" -eq 1 ]; then
  if [ ! -x ./run-collector.sh ]; then
    echo "error: ./run-collector.sh is required to restart the Collector in debug mode." >&2
    exit 1
  fi
  echo "Restarting OTel Collector with OTEL_COLLECTOR_LOG_LEVEL=debug..."
  OTEL_COLLECTOR_LOG_LEVEL=debug ./run-collector.sh restart
fi

cmd="${1:-follow}"
arg="${2:-}"

case "$cmd" in
  follow)
    ensure_container_exists
    echo "Following OTel Collector logs from '$CONTAINER_NAME'..."
    exec podman logs -f "$CONTAINER_NAME"
    ;;
  tail)
    ensure_container_exists
    lines="${arg:-200}"
    [[ "$lines" =~ ^[0-9]+$ ]] || { echo "error: tail count must be a number" >&2; exit 1; }
    exec podman logs --tail "$lines" "$CONTAINER_NAME"
    ;;
  since)
    ensure_container_exists
    since="${arg:-10m}"
    exec podman logs --since "$since" "$CONTAINER_NAME"
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