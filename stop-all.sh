#!/usr/bin/env bash
#
# Stop the TIBCO PetClinic stack - the reverse of run-all.sh. Stop everything
# or one service at a time:
#   frontend   Stop the frontend (whatever is listening on 8080)
#   backend    Stop the backend  (whatever is listening on 8081)
#   tibco      Stop and remove the TIBCO EMS broker container
#   apps       Stop frontend and backend (no broker)
#   all        Stop frontend, backend and tibco (default)
#
# Services are stopped in the reverse of run-all.sh's start order:
# frontend, then backend, then tibco.
set -euo pipefail
cd "$(dirname "$0")"

TIBCO_CONTAINER="${TIBCO_CONTAINER:-petclinic-tibco}"
ACTIVEMQ_EXPORTER_CONTAINER="${ACTIVEMQ_EXPORTER_CONTAINER:-petclinic-activemq-exporter}"

usage() {
  cat <<'EOF'
Usage: ./stop-all.sh [target ...]

Targets:
  tibco      Stop and remove the TIBCO EMS broker container
  backend    Stop the backend  (listening on 8081)
  frontend   Stop the frontend (listening on 8080)
  apps       Stop frontend and backend (no broker)
  all        Stop frontend, backend and tibco (default)

Examples:
  ./stop-all.sh                # stop everything
  ./stop-all.sh tibco          # just the broker
  ./stop-all.sh frontend       # just the frontend
  ./stop-all.sh apps           # frontend + backend
EOF
}

# ---- parse targets ---------------------------------------------------------
want_tibco=0 want_backend=0 want_frontend=0
targets=("$@")
[ ${#targets[@]} -eq 0 ] && targets=(all)
for t in "${targets[@]}"; do
  case "$t" in
    all)      want_tibco=1; want_backend=1; want_frontend=1 ;;
    apps)     want_backend=1; want_frontend=1 ;;
    tibco)    want_tibco=1 ;;
    backend)  want_backend=1 ;;
    frontend) want_frontend=1 ;;
    -h|--help|help) usage; exit 0 ;;
    *) echo "error: unknown target '$t'" >&2; usage; exit 1 ;;
  esac
done

# stop_port <name> <port> - stop whatever process is listening on <port>
stop_port() {
  local name=$1 port=$2 pids i
  pids=$(lsof -ti "tcp:$port" -sTCP:LISTEN 2>/dev/null || true)
  if [ -z "$pids" ]; then
    echo "$name: not running (nothing listening on $port)."
    return 0
  fi
  echo "Stopping $name (pid $(echo "$pids" | tr '\n' ' ')on port $port)..."
  kill $pids 2>/dev/null || true
  for i in $(seq 1 10); do
    pids=$(lsof -ti "tcp:$port" -sTCP:LISTEN 2>/dev/null || true)
    [ -z "$pids" ] && { echo "$name stopped."; return 0; }
    sleep 1
  done
  echo "$name did not stop gracefully; forcing..."
  kill -9 $pids 2>/dev/null || true
  echo "$name stopped."
}

stop_tibco() {
  if podman container exists "$ACTIVEMQ_EXPORTER_CONTAINER" 2>/dev/null; then
    podman rm -f "$ACTIVEMQ_EXPORTER_CONTAINER" >/dev/null
    echo "ActiveMQ metrics exporter stopped."
  fi
  if podman container exists "$TIBCO_CONTAINER" 2>/dev/null; then
    echo "Stopping TIBCO EMS broker '$TIBCO_CONTAINER'..."
    podman rm -f "$TIBCO_CONTAINER" >/dev/null
    echo "TIBCO EMS broker stopped."
  else
    echo "tibco: not running."
  fi
}

# ---- act in reverse order: frontend, backend, tibco -----------------------
[ $want_frontend -eq 1 ] && stop_port frontend 8080
[ $want_backend -eq 1 ]  && stop_port backend  8081
[ $want_tibco -eq 1 ]    && stop_tibco
