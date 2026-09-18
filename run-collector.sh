#!/usr/bin/env bash
#
# Run the Splunk Distribution of the OpenTelemetry Collector as a local podman
# container (gateway mode). The PetClinic app JVMs export OTLP to it
# (grpc localhost:4317 / http localhost:4318) and the collector forwards traces,
# metrics and logs to Splunk Observability Cloud for the configured realm.
#
# Credentials come from .env (SPLUNK_REALM + SPLUNK_ACCESS_TOKEN) so the token
# never appears on the command line or in `ps` output.
#
# To send the apps THROUGH this collector instead of straight to o11y cloud,
# start them with the realm unset and OTLP pointed at the collector, e.g.
#   SPLUNK_REALM= OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 ./run-all-otel.sh apps
#
# Usage:
#   ./run-collector.sh [start|stop|status|restart|logs]
#     start   pull (if needed) and (re)start the collector container   [default]
#     stop    stop and remove the collector container
#     status  show the container state and published ports
#     restart stop then start the collector container
#     logs    follow the collector logs
set -euo pipefail
cd "$(dirname "$0")"

# Load SPLUNK_REALM / SPLUNK_ACCESS_TOKEN from .env (gitignored). set -a exports
# them so `podman run -e VAR` forwards the value without printing it.
if [ -f .env ]; then
  set -a
  # shellcheck source=/dev/null
  . ./.env
  set +a
fi

CONTAINER_NAME="${SPLUNK_COLLECTOR_NAME:-splunk-otel-collector}"
IMAGE="${SPLUNK_COLLECTOR_IMAGE:-quay.io/signalfx/splunk-otel-collector:latest}"
# Local OTel gateway config overlay
LOCAL_OTEL_CONFIG="$(dirname "$0")/otel-tibco-metrics.yaml"
# Mount point inside the container
CONTAINER_OTEL_CONFIG="/etc/otel/collector/tibco_metrics_config.yaml"
# Use the mounted overlay config (OTLP receivers + Splunk exporters)
SPLUNK_CONFIG_PATH="${SPLUNK_CONFIG:-$CONTAINER_OTEL_CONFIG}"
SPLUNK_MEMORY_TOTAL_MIB="${SPLUNK_MEMORY_TOTAL_MIB:-512}"
OTEL_COLLECTOR_LOG_LEVEL="${OTEL_COLLECTOR_LOG_LEVEL:-info}"

cmd="${1:-start}"

start_collector() {
  : "${SPLUNK_REALM:?set SPLUNK_REALM in .env (e.g. us1)}"
  : "${SPLUNK_ACCESS_TOKEN:?set SPLUNK_ACCESS_TOKEN in .env}"
  echo "Starting $CONTAINER_NAME (realm=$SPLUNK_REALM, config=$SPLUNK_CONFIG_PATH, log-level=$OTEL_COLLECTOR_LOG_LEVEL)..."
  podman run -d --replace --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    --network petclinic-net \
    -v "$LOCAL_OTEL_CONFIG:$CONTAINER_OTEL_CONFIG" \
    -e SPLUNK_ACCESS_TOKEN \
    -e SPLUNK_REALM \
    -e SPLUNK_CONFIG="$SPLUNK_CONFIG_PATH" \
    -e SPLUNK_MEMORY_TOTAL_MIB="$SPLUNK_MEMORY_TOTAL_MIB" \
    -e OTEL_COLLECTOR_LOG_LEVEL \
    -e SPLUNK_LISTEN_INTERFACE=0.0.0.0 \
    -p 4317:4317 \
    -p 4318:4318 \
    -p 13133:13133 \
    "$IMAGE"
  printf 'Waiting for collector health (http://localhost:13133) '
  for _ in $(seq 1 30); do
    if curl -fs -o /dev/null http://localhost:13133; then
      echo " ready."
      echo "Collector up. OTLP in: grpc :4317, http :4318  ->  Splunk (realm=$SPLUNK_REALM)."
      return 0
    fi
    printf '.'; sleep 1
  done
  echo " timed out."
  # Some collector builds can accept the TCP connection but return an empty HTTP
  # response on :13133. If the container is running, treat startup as successful.
  if podman inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q '^true$'; then
    echo "Collector is running, but HTTP health probe on :13133 did not return success." >&2
    echo "Use './run-collector.sh logs' if you need deeper diagnostics." >&2
    echo "Collector up. OTLP in: grpc :4317, http :4318  ->  Splunk (realm=$SPLUNK_REALM)."
    return 0
  fi
  echo "Collector did not report healthy and is not running; inspect with: ./run-collector.sh logs" >&2
  return 1
}

stop_collector() {
  if podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1; then
    echo "Removed $CONTAINER_NAME."
  else
    echo "$CONTAINER_NAME is not running."
  fi
}

case "$cmd" in
  start|up)
    start_collector
    ;;
  stop|down)
    stop_collector
    ;;
  restart)
    stop_collector
    start_collector
    ;;
  status)
    podman ps -a --filter "name=$CONTAINER_NAME" \
      --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    ;;
  logs)
    podman logs -f "$CONTAINER_NAME"
    ;;
  -h|--help|help)
    sed -n '2,25p' "$0"
    ;;
  *)
    echo "Usage: $0 [start|stop|status|restart|logs]" >&2
    echo "(aliases: up=start, down=stop)" >&2
    exit 1
    ;;
esac
