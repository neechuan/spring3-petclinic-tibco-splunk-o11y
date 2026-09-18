#!/usr/bin/env bash
#
# Check ActiveMQ Jolokia health, broker statistics, and a PetClinic queue.
#
# Usage:
#   ./check-tibco-jolokia.sh
#
# Optional environment variables:
#   AMQ_HOST       Jolokia host (default: localhost)
#   AMQ_PORT       Jolokia port (default: 8161)
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "error: .env is required; set AMQ_USER and AMQ_PASSWORD there" >&2
  exit 1
fi
set -a
# shellcheck source=/dev/null
. ./.env
set +a
: "${AMQ_USER:?AMQ_USER must be set in .env}"
: "${AMQ_PASSWORD:?AMQ_PASSWORD must be set in .env}"
AMQ_HOST="${AMQ_HOST:-localhost}"
AMQ_PORT="${AMQ_PORT:-8161}"

command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "error: jq is required" >&2; exit 1; }

JOLOKIA_URL="http://${AMQ_HOST}:${AMQ_PORT}/api/jolokia"
ORIGIN="http://${AMQ_HOST}:${AMQ_PORT}"
BROKER_MBEAN='org.apache.activemq:type=Broker,brokerName=localhost'

jolokia_get() {
  curl -fsS -u "${AMQ_USER}:${AMQ_PASSWORD}" \
    -H "Origin: ${ORIGIN}" "$@"
}

check_response() {
  local label=$1
  local response=$2

  if ! jq -e '.status == 200' >/dev/null <<<"$response"; then
    echo "error: ${label} request failed:" >&2
    jq . <<<"$response" >&2 || printf '%s\n' "$response" >&2
    exit 1
  fi
}

echo "Checking Jolokia at ${JOLOKIA_URL}..."
version_response="$(jolokia_get "${JOLOKIA_URL}/version")"
check_response "Jolokia health" "$version_response"
jq . <<<"$version_response"

echo
echo "Reading broker status and aggregate statistics..."
broker_response="$(jolokia_get \
  "${JOLOKIA_URL}/read/${BROKER_MBEAN}")"
check_response "broker status" "$broker_response"
jq . <<<"$broker_response"

echo
echo "Listing all JMS queues and statistics..."
queue_list_response="$(jolokia_get \
  "${JOLOKIA_URL}/read/${BROKER_MBEAN}/Queues")"
check_response "JMS queue list" "$queue_list_response"
queue_count="$(jq '.value | length' <<<"$queue_list_response")"
echo "Found ${queue_count} queue(s)."

while IFS= read -r queue_mbean; do
  queue_name="$(sed -n 's/.*destinationName=\([^,]*\),destinationType=Queue.*/\1/p' <<<"$queue_mbean")"
  queue_stats="$(jolokia_get \
    "${JOLOKIA_URL}/read/${queue_mbean}/QueueSize,EnqueueCount,DequeueCount,ConsumerCount,ProducerCount")"
  check_response "queue statistics for ${queue_name}" "$queue_stats"
  printf '\n%s\n' "${queue_name}"
  jq '.value | {QueueSize, EnqueueCount, DequeueCount, ConsumerCount, ProducerCount}' <<<"$queue_stats"
done < <(jq -r '.value[].objectName' <<<"$queue_list_response")

echo
echo "Jolokia checks passed."
