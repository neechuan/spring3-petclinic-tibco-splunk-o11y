#!/usr/bin/env bash
#
# Start the TIBCO PetClinic stack, all together or one service at a time:
#   tibco      TIBCO EMS broker      (detached ActiveMQ container mimicking TIBCO)
#   backend    persistence + TIBCO replier   (http://localhost:8081)
#   frontend   UI + TIBCO requestor          (http://localhost:8080)
#   all        tibco + backend + frontend   (default)
#
# A single requested app runs in the foreground with live logs (Ctrl+C stops
# it). Multiple apps run in the background (logs in ./logs) and are stopped
# together with Ctrl+C. The broker always runs detached - stop it with:
#   ./stop-all.sh tibco
set -euo pipefail
cd "$(dirname "$0")"

# Load local config/secrets from .env if present (keeps SPLUNK_ACCESS_TOKEN out
# of this script and out of git - see .gitignore). set -a exports every value.
if [ -f .env ]; then
  set -a
  # shellcheck source=/dev/null
  . ./.env
  set +a
fi

usage() {
  cat <<'EOF'
Usage: ./run-all.sh [target ...]

Targets:
  tibco      Start the TIBCO EMS broker (detached ActiveMQ container, http://localhost:8161)
  backend    Start the backend  (persistence + replier, http://localhost:8081)
  frontend   Start the frontend (UI + requestor,        http://localhost:8080)
  apps       Start backend then frontend (no broker)
  all        Start tibco, backend and frontend (default)

Examples:
  ./run-all.sh                 # start everything
  ./run-all.sh tibco           # just the broker
  ./run-all.sh backend         # just the backend (live logs; Ctrl+C to stop)
  ./run-all.sh apps            # backend then frontend
  ./run-all.sh tibco backend   # broker + backend
EOF
}

# Prefer the bundled Maven wrapper if it is configured, otherwise system mvn.
if [ -x ./mvnw ] && [ -f .mvn/wrapper/maven-wrapper.properties ]; then
  MVN=./mvnw
elif command -v mvn >/dev/null 2>&1; then
  MVN=mvn
else
  echo "error: no working ./mvnw wrapper and 'mvn' is not on PATH." >&2
  exit 1
fi

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

LOG_DIR=logs
mkdir -p "$LOG_DIR"
pids=()

wait_for_http() { # <name> <url>
  local name=$1 url=$2 i
  printf 'Waiting for %s ' "$name"
  for i in $(seq 1 90); do
    if curl -fs -o /dev/null "$url"; then echo " ready."; return 0; fi
    printf '.'; sleep 2
  done
  echo " timed out (continuing anyway)."
}

run_tibco() {
  local name="${TIBCO_CONTAINER:-petclinic-tibco}"
  local image="${TIBCO_IMAGE:-docker.io/apache/activemq-classic:latest}"
  local exporter_name="${ACTIVEMQ_EXPORTER_CONTAINER:-petclinic-activemq-exporter}"
  local exporter_image="${ACTIVEMQ_EXPORTER_IMAGE:-docker.io/bitnami/jmx-exporter:latest}"
  local exporter_config="$(pwd)/activemq-jmx-exporter.yaml"
  local jmx_opts='-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.port=1099 -Dcom.sun.management.jmxremote.rmi.port=1099 -Djava.rmi.server.hostname=petclinic-tibco -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false'

  if podman container exists "$name"; then
    if ! podman inspect "$name" --format '{{json .Config.Env}}' | grep -Fq -- '-Dcom.sun.management.jmxremote.port=1099'; then
      echo "Recreating '$name' with remote JMX enabled for metrics..."
      podman rm -f "$name" >/dev/null
    else
      podman start "$name" >/dev/null
    fi
  fi
  if ! podman container exists "$name"; then
    podman run -d --name "$name" \
      --network petclinic-net \
      -e "ACTIVEMQ_OPTS=-Xms64M -Xmx1G -Djava.util.logging.config.file=logging.properties -Djava.security.auth.login.config=/opt/apache-activemq/conf/login.config -Djetty.host=0.0.0.0 $jmx_opts" \
      -p 61616:61616 \
      -p 8161:8161 \
      "$image"
  fi
  echo "TIBCO EMS broker '$name' starting (host port 61616, web console http://localhost:8161)."
  printf 'Waiting for TIBCO EMS (61616) '
  for i in $(seq 1 60); do
    if nc -z localhost 61616 2>/dev/null; then echo " open."; break; fi
    printf '.'; sleep 2
  done

  podman run -d --replace --name "$exporter_name" \
    --network petclinic-net \
    -p 9404:9404 \
    -v "$exporter_config:/opt/bitnami/jmx-exporter/config.yaml:ro" \
    "$exporter_image" 9404 config.yaml >/dev/null
  echo "ActiveMQ JMX exporter '$exporter_name' serving metrics on the collector network (port 9404)."
}

# start_app_bg <name> <pom-dir> <health-url>
start_app_bg() {
  local name=$1 dir=$2 url=$3
  echo "Starting $name (log: $LOG_DIR/$name.log)..."
  # fork=false keeps the app in this Maven process so Ctrl+C stops it cleanly.
  MAVEN_OPTS="${MAVEN_OPTS:-}" \
    $MVN -q -f "$dir/pom.xml" -Dspring-boot.run.fork=false spring-boot:run \
    > "$LOG_DIR/$name.log" 2>&1 &
  pids+=($!)
  wait_for_http "$name" "$url"
}

# run_app_fg <name> <pom-dir>  (replaces this process; Ctrl+C stops the app)
run_app_fg() {
  local name=$1 dir=$2
  echo "Starting $name in the foreground (Ctrl+C to stop)..."
  export MAVEN_OPTS="${MAVEN_OPTS:-}"
  exec $MVN -f "$dir/pom.xml" -Dspring-boot.run.fork=false spring-boot:run
}

# ---- act, in canonical order: tibco, backend, frontend --------------------
[ $want_tibco -eq 1 ] && run_tibco

java_count=$((want_backend + want_frontend))

if [ "$java_count" -eq 0 ]; then
  [ $want_tibco -eq 1 ] && \
    echo "TIBCO EMS broker  : localhost:61616"
  exit 0
fi

if [ "$java_count" -eq 1 ]; then
  if [ $want_backend -eq 1 ]; then
    run_app_fg backend backend
  else
    run_app_fg frontend frontend
  fi
fi

cleanup() {
  [ ${#pids[@]} -gt 0 ] && kill "${pids[@]}" 2>/dev/null
  wait 2>/dev/null
}

# Two or more apps: background them and wait together.
trap cleanup INT TERM
[ $want_backend -eq 1 ]  && start_app_bg backend  backend  "http://localhost:8081/actuator/health"
[ $want_frontend -eq 1 ] && start_app_bg frontend frontend "http://localhost:8080/actuator/health"

echo
echo "Services are up:"
[ $want_frontend -eq 1 ] && echo "  PetClinic UI      : http://localhost:8080/"
[ $want_backend -eq 1 ]  && echo "  Backend health    : http://localhost:8081/actuator/health"
[ $want_tibco -eq 1 ]    && echo "  TIBCO EMS broker  : localhost:61616"
echo
echo "Logs in $LOG_DIR/. Press Ctrl+C to stop the app(s)."
wait
