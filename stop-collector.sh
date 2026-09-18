#!/usr/bin/env bash
#
# Stop the Splunk OpenTelemetry Collector container started by run-collector.sh.
set -euo pipefail
cd "$(dirname "$0")"

CONTAINER_NAME="${SPLUNK_COLLECTOR_NAME:-splunk-otel-collector}"

if podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1; then
  echo "Removed $CONTAINER_NAME."
else
  echo "$CONTAINER_NAME is not running."
fi
