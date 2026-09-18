# OTel Collector Configuration

## Status
**ACTIVE** - The OTel Collector receives application OTLP traces and metrics.
The current Splunk Collector image does not include an ActiveMQ receiver, so it
does not scrape broker metrics. ActiveMQ statistics remain available from the
Jolokia endpoint on port 8161.

## Architecture
- **OTel Collector**: `quay.io/signalfx/splunk-otel-collector:latest` 
  - Container: `splunk-otel-collector`
  - Ports: 4317 (OTLP/gRPC), 4318 (OTLP/HTTP), 13133 (health)
  - Network: `petclinic-net` (shared with TIBCO)
  
- **TIBCO EMS Broker (ActiveMQ)**: `docker.io/apache/activemq-classic:latest`
  - Container: `petclinic-tibco`
  - Ports:
    - 61616 for JMS clients (frontend/backend)
    - 8161 for Web console and Jolokia API (available for manual inspection or a future/custom metrics integration)

## Jolokia Health and Status Checks

The broker exposes Jolokia at:

```text
http://localhost:8161/api/jolokia
```

Use `http://petclinic-tibco:8161/api/jolokia` when querying from another
container on `petclinic-net`. The endpoint requires the ActiveMQ Web Console's
HTTP Basic credentials and rejects requests with a null origin, so the examples
include an explicit same-origin `Origin` header:

```bash
AMQ_USER=admin
AMQ_PASSWORD=admin
```

Run all Jolokia checks with the repository script. It reads the credentials
strictly from the repository `.env` file and lists every JMS queue with its
key statistics:

```bash
./check-tibco-jolokia.sh
```

The script checks Jolokia authentication, reads broker status and aggregate
statistics, and reads the `petclinic.rpc.owner.findById` queue. For a direct
broker read, use Jolokia's path-based syntax:

```bash
curl -u "$AMQ_USER:$AMQ_PASSWORD" \
  -H 'Origin: http://localhost:8161' \
  http://localhost:8161/api/jolokia/read/org.apache.activemq:type=Broker,brokerName=localhost | jq
```

These queries inspect the broker directly. The current
`otel-tibco-metrics.yaml` does not query Jolokia, so the returned values are not
exported to the OTel Collector or Splunk Observability Cloud.

## Configuration Files

### 1. `otel-tibco-metrics.yaml` (OTel Receiver Config)
- **Receivers**:
  - `otlp` on `0.0.0.0:4317` (gRPC) and `0.0.0.0:4318` (HTTP)
- **Extensions**:
  - `health_check` on `0.0.0.0:13133`
- **Pipelines**:
  - `traces`: `otlp -> batch -> splunk_otlp`
  - `metrics`: `otlp -> batch -> splunk_otlp`

### 2. `run-collector.sh` (Startup Script)
- Mounts `otel-tibco-metrics.yaml` into container at `/etc/otel/collector/tibco_metrics_config.yaml`
- Exposes ports 4317, 4318, 13133
- Uses `--network petclinic-net` for DNS resolution
- Commands:
  - `start` (default)
  - `stop`
  - `status`
  - `restart`
