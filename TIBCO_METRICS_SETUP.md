# OTel TIBCO Metrics Receiver Configuration

## Status
✅ **ACTIVE** - OTel collector is running with both OTLP ingest and TIBCO EMS (ActiveMQ) metrics scraping.

## Architecture
- **OTel Collector**: `quay.io/signalfx/splunk-otel-collector:latest` 
  - Container: `splunk-otel-collector`
  - Ports: 4317 (OTLP/gRPC), 4318 (OTLP/HTTP), 13133 (health)
  - Network: `petclinic-net` (shared with TIBCO)
  
- **TIBCO EMS Broker (ActiveMQ)**: `docker.io/apache/activemq-classic:latest`
  - Container: `petclinic-tibco`
  - Ports:
    - 61616 for JMS clients (frontend/backend)
    - 8161 for Web console and Jolokia api (e.g., collector)

## Configuration Files

### 1. `otel-tibco-metrics.yaml` (OTel Receiver Config)
- **Receivers**:
  - `otlp` on `0.0.0.0:4317` (gRPC) and `0.0.0.0:4318` (HTTP)
  - `activemq` receiver to scrape broker statistics
- **TIBCO Metrics Receiver (ActiveMQ)**:
  - Endpoint: `http://petclinic-tibco:8161/api/jolokia`
  - Collection Interval: 1 minute
  - Initial Delay: 45 seconds
- **Extensions**:
  - `health_check` on `0.0.0.0:13133`
- **Pipelines**:
  - `traces`: `otlp -> batch -> splunk_otlp`
  - `metrics`: `otlp + activemq -> batch -> splunk_otlp`

### 2. `run-collector.sh` (Startup Script)
- Mounts `otel-tibco-metrics.yaml` into container at `/etc/otel/collector/tibco_metrics_config.yaml`
- Exposes ports 4317, 4318, 13133
- Uses `--network petclinic-net` for DNS resolution
- Commands:
  - `start` (default)
  - `stop`
  - `status`
  - `restart`
