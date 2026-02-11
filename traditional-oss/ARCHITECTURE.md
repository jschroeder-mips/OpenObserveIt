# Open-Source Observability Platform Architecture
## AWS PoC for 50 Hosts/Applications

**Version:** 1.0  
**Last Updated:** 2024  
**Target Scale:** 50 hosts, ~100-150 applications/services  
**Architecture Philosophy:** Cloud-native, horizontally scalable, open-source first

---

## Executive Summary

This architecture provides a production-ready observability stack that balances cost, performance, and operational simplicity for a 50-host deployment. The design prioritizes:

- **OpenTelemetry** as the unified collection layer
- **Grafana** as the single pane of glass for all observability data
- **Purpose-built storage backends** optimized for each signal type
- **AWS-native integration** for cost optimization and reliability
- **Linear scalability path** from 50 to 500+ hosts

**Estimated AWS Monthly Cost:** ~$1,200-1,800 (excluding host infrastructure)

---

## 1. Component Selection & Rationale

### 1.1 Metrics Stack

**Recommended: Prometheus + Thanos (Hybrid Architecture)**

#### Core Components:
- **Prometheus** v2.50+ - Primary metrics collection and short-term storage
- **Thanos** v0.34+ - Long-term storage, global query, downsampling
- **OpenTelemetry Collector** v0.96+ - Unified metrics collection agent

#### Why This Stack:
```
✅ Prometheus is the de-facto standard for metrics in cloud-native environments
✅ Thanos provides S3-backed unlimited retention without Prometheus operational complexity
✅ Proven at scale (used by companies running 10k+ hosts)
✅ Native Kubernetes support but works equally well on EC2
✅ Strong community, extensive exporter ecosystem
```

#### Alternative Considered: VictoriaMetrics
- **Pros:** 10x better compression, faster queries, simpler ops (single binary)
- **Cons:** Smaller community, less mature ecosystem
- **Verdict:** Excellent choice if team has strong Prometheus experience and wants simplified ops. Consider for Phase 2 optimization.

#### Why NOT Mimir:
- Requires Kubernetes and complex distributed architecture
- Overkill for 50 hosts (designed for multi-tenant massive scale)
- Higher operational burden

### 1.2 Logs Stack

**Recommended: Grafana Loki v2.9+**

#### Why Loki:
```
✅ Designed for cloud object storage (S3) - dramatically cheaper than Elasticsearch
✅ Tight Grafana integration with unified correlation UX
✅ Indexes only metadata (labels), not full-text - 10x cheaper storage
✅ LogQL query language similar to PromQL
✅ ~50GB/day log ingestion capacity per node
```

#### Architecture Pattern:
- **Promtail** v2.9+ on each host (lightweight log shipper)
- **Loki** distributed mode (3 components: ingester, querier, compactor)
- **S3** for long-term chunk storage

#### Alternative Considered: OpenSearch/Elasticsearch
- **Pros:** Full-text search, better for security/compliance use cases
- **Cons:** 5-10x more expensive storage, complex cluster management
- **Verdict:** Use only if you need advanced full-text search or compliance logging

### 1.3 Distributed Tracing

**Recommended: Grafana Tempo v2.4+**

#### Why Tempo:
```
✅ S3-native storage (cheapest possible tracing storage)
✅ No sampling required - store 100% of traces economically
✅ TraceQL for powerful trace queries
✅ Grafana native integration - seamless logs-to-traces-to-metrics correlation
✅ OpenTelemetry native
```

#### Alternative Considered: Jaeger
- **Pros:** More mature UI, better trace analytics
- **Cons:** Requires separate database (Cassandra/Elasticsearch), higher ops cost
- **Verdict:** Use if you need advanced trace analytics features or service dependency graphs

### 1.4 Unified UI

**Grafana Enterprise (Free) v10.3+**

- Single pane of glass for metrics, logs, traces
- Built-in alerting (replaces standalone Alertmanager)
- OnCall integration for incident management
- Synthetic monitoring support

### 1.5 Alerting

**Recommended: Grafana Alerting (Unified Alerting)**

#### Why:
- Integrated into Grafana v8+ (no separate deployment)
- Alert on metrics, logs, and traces from single interface
- Notification channels: PagerDuty, Slack, email, webhooks
- Label-based routing (Alertmanager compatible)

**Fallback:** Standalone Alertmanager v0.27+ if team already uses it

### 1.6 Data Collection

**Recommended: OpenTelemetry Collector v0.96+ (Universal Agent)**

#### Deployment Patterns:
```
Per-Host Agent (recommended):
- OTel Collector in agent mode on every host
- Collects metrics, logs, traces
- 50-100MB memory footprint per host

Gateway Pattern (optional for large deployments):
- OTel Collector in gateway mode (2-3 instances)
- Centralized processing, filtering, routing
- Use when you need centralized sampling/redaction
```

#### Supplementary Exporters:
- **node_exporter** v1.7+ - Host-level metrics (CPU, disk, network)
- **cAdvisor** v0.47+ - Container metrics (if using Docker/K8s)
- **postgres_exporter**, **mysqld_exporter** - Database metrics as needed

---

## 2. AWS Infrastructure Specification

### 2.1 Deployment Architecture: EC2-Based (Recommended for 50 hosts)

**Why EC2 over EKS:**
- Lower operational complexity for small scale
- $150-200/month savings (no EKS control plane costs)
- Easier for teams without Kubernetes expertise
- **Note:** EKS recommended if you already run containerized workloads

### 2.2 Instance Specifications

#### Observability Infrastructure Nodes

| Component | Instance Type | Count | vCPU | RAM | Storage | Monthly Cost |
|-----------|---------------|-------|------|-----|---------|--------------|
| **Prometheus** | t3.large | 2 | 2 | 8GB | 500GB gp3 | ~$150 |
| **Thanos Query** | t3.medium | 2 | 2 | 4GB | 50GB gp3 | ~$90 |
| **Thanos Store Gateway** | t3.medium | 2 | 2 | 4GB | 100GB gp3 | ~$100 |
| **Thanos Compactor** | t3.medium | 1 | 2 | 4GB | 100GB gp3 | ~$50 |
| **Loki (All-in-One)** | t3.xlarge | 2 | 4 | 16GB | 200GB gp3 | ~$200 |
| **Tempo** | t3.large | 2 | 2 | 8GB | 100GB gp3 | ~$150 |
| **Grafana** | t3.medium | 2 | 2 | 4GB | 50GB gp3 | ~$90 |
| **ALB** | - | 1 | - | - | - | ~$25 |

**Total Infrastructure:** ~$855/month (compute + EBS)

#### Monitored Hosts (Your 50 Application Hosts)
- **OTel Collector:** ~50-100MB RAM per host (negligible overhead)
- **node_exporter:** ~20MB RAM per host

### 2.3 Storage Architecture

#### EBS Volumes (Operational/Cache Storage)

```
Prometheus (per instance):
- Type: gp3 (3000 IOPS, 125 MB/s)
- Size: 500GB (15-day retention of raw metrics)
- Cost: ~$40/month per instance

Loki Ingesters:
- Type: gp3
- Size: 200GB (2-3 days of log cache)
- Cost: ~$20/month per instance

Tempo:
- Type: gp3
- Size: 100GB (trace ingestion buffer)
- Cost: ~$10/month per instance
```

#### S3 Buckets (Long-Term Storage)

```
thanos-metrics-bucket:
- Storage Class: S3 Standard → S3 Intelligent-Tiering after 30 days
- Estimated Size: 2TB/year (with 5min resolution, 5:1 compression)
- Lifecycle: Downsample to 5min after 7d, 1h after 30d
- Cost: ~$50-70/month (first year)

loki-logs-bucket:
- Storage Class: S3 Standard → S3 Glacier Instant after 90 days
- Estimated Size: 50GB/day × 30 days = 1.5TB/month
- Cost: ~$35-45/month

tempo-traces-bucket:
- Storage Class: S3 Standard (short retention)
- Estimated Size: 20GB/day × 30 days = 600GB
- Retention: 30 days (traces are queryable but rarely needed long-term)
- Cost: ~$15/month
```

**Total S3 Cost:** ~$100-130/month

### 2.4 Networking Architecture

#### VPC Design
```
VPC: 10.0.0.0/16

Subnets:
├── Public Subnets (10.0.1.0/24, 10.0.2.0/24)
│   └── Application Load Balancer (Grafana UI)
│
├── Private Subnets (10.0.10.0/24, 10.0.11.0/24)
│   └── Observability Platform Components
│
└── Monitoring Subnets (10.0.20.0/24, 10.0.21.0/24)
    └── Monitored Application Hosts
```

#### Load Balancers
```
grafana-public-alb (Internet-facing):
- Target: Grafana instances (port 3000)
- SSL/TLS: ACM certificate
- Cost: ~$25/month + $0.008/LCU-hour

prometheus-internal-nlb (Internal):
- Target: Prometheus instances (port 9090)
- Used by Thanos Query
- Cost: ~$20/month
```

#### Security Groups

```hcl
# Grafana Security Group
grafana-sg:
  Ingress:
    - Port 3000 from ALB security group
  Egress:
    - Port 9090 to Prometheus SG
    - Port 3100 to Loki SG
    - Port 3200 to Tempo SG
    - Port 443 to S3 VPC endpoint

# Prometheus Security Group
prometheus-sg:
  Ingress:
    - Port 9090 from Grafana SG
    - Port 9090 from Thanos Query SG
    - Port 10901 from Thanos Query SG (gRPC)
  Egress:
    - Port 443 to S3 VPC endpoint

# OTel Collector (on monitored hosts)
otel-sg:
  Ingress:
    - None (push model)
  Egress:
    - Port 9090 to Prometheus SG (remote_write)
    - Port 3100 to Loki SG
    - Port 4317 to Tempo SG (gRPC)
```

### 2.5 High Availability Configuration

#### Prometheus HA
```yaml
# 2 identical Prometheus instances with identical config
# Both scrape all targets (deduplication in Thanos Query)
# Each instance has Thanos Sidecar for S3 upload

Instance 1: prometheus-1.internal (AZ us-east-1a)
Instance 2: prometheus-2.internal (AZ us-east-1b)

Thanos Query deduplicates based on external_labels:
  replica: prometheus-1
  replica: prometheus-2
```

#### Loki HA (Simple Read/Write Mode)
```yaml
# 2 Loki instances in simple-scalable mode
# Write path: ALB → both instances (duplicate writes)
# Read path: ALB → any instance

loki-1: Read + Write (AZ us-east-1a)
loki-2: Read + Write (AZ us-east-1b)
```

#### Grafana HA
```yaml
# 2 Grafana instances sharing RDS PostgreSQL backend
# Session affinity via ALB sticky sessions

grafana-1: (AZ us-east-1a)
grafana-2: (AZ us-east-1b)
Database: RDS PostgreSQL (db.t3.small, Multi-AZ)
  Cost: ~$50/month
```

---

## 3. Data Flow Architecture

### 3.1 Metrics Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        Monitored Hosts (50x)                     │
│                                                                   │
│  ┌──────────────┐      ┌──────────────┐                         │
│  │ Application  │──────│ OTel         │                         │
│  │ (instrumented│      │ Collector    │                         │
│  │ with OTel SDK│      │ (Agent Mode) │                         │
│  └──────────────┘      └──────┬───────┘                         │
│                                │                                  │
│  ┌──────────────┐             │                                  │
│  │ node_exporter│─────────────┘                                  │
│  │ :9100        │                                                 │
│  └──────────────┘                                                 │
└────────────────────────────────┼───────────────────────────────┘
                                  │
                                  │ Prometheus Remote Write
                                  │ (HTTP/2)
                                  ▼
                    ┌─────────────────────────┐
                    │  Prometheus Instances   │
                    │  (2x HA Replicas)       │
                    │                         │
                    │  - 15 day retention     │
                    │  - Local TSDB           │
                    │  - Thanos Sidecar       │
                    └──────────┬──────────────┘
                               │
                               │ Thanos Sidecar uploads blocks
                               │ (every 2 hours)
                               ▼
                    ┌─────────────────────────┐
                    │    S3: thanos-metrics   │
                    │    - Infinite retention │
                    │    - Downsampling       │
                    └──────────┬──────────────┘
                               │
                               │ Query via S3 Select
                               ▼
         ┌────────────────────────────────────────┐
         │         Thanos Query Frontend          │
         │  - Deduplication                       │
         │  - Query Federation (Prometheus + S3)  │
         │  - PromQL API                          │
         └────────────────┬───────────────────────┘
                          │
                          │ PromQL Queries
                          ▼
                 ┌────────────────────┐
                 │      Grafana       │
                 │   (Metrics UI)     │
                 └────────────────────┘
```

#### Metrics Data Specifications
```yaml
Ingestion Rate: 
  - 50 hosts × 200 metrics/host = 10,000 metrics
  - 150 apps × 50 metrics/app = 7,500 metrics
  - Total: ~20,000 active time series

Scrape Interval: 30 seconds (configurable per job)

Cardinality Management:
  - Limit label values (max 100 per metric)
  - Drop high-cardinality metrics at OTel Collector
  - Use recording rules for expensive queries

Storage:
  - Raw: 30 sec resolution, 15 days (Prometheus local)
  - Downsampled: 5 min resolution, 90 days (Thanos S3)
  - Long-term: 1 hour resolution, 2 years (Thanos S3)
```

### 3.2 Logs Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        Monitored Hosts (50x)                     │
│                                                                   │
│  ┌──────────────┐      ┌──────────────┐                         │
│  │ Application  │──────│   Promtail   │                         │
│  │ Logs         │      │ (Log Shipper)│                         │
│  │ /var/log/app │      │              │                         │
│  └──────────────┘      └──────┬───────┘                         │
│                                │                                  │
│  ┌──────────────┐             │ Labels:                          │
│  │ System Logs  │             │  host=hostname                   │
│  │ /var/log/    │─────────────│  env=prod                        │
│  └──────────────┘             │  app=service-name                │
│                                │                                  │
└────────────────────────────────┼───────────────────────────────┘
                                  │
                                  │ HTTP Push (JSON)
                                  │ Port 3100
                                  ▼
                    ┌─────────────────────────┐
                    │   Loki Distributors     │
                    │   (via ALB)             │
                    └──────────┬──────────────┘
                               │
                               │ Forward to Ingesters
                               ▼
                    ┌─────────────────────────┐
                    │    Loki Ingesters       │
                    │   - Build chunks        │
                    │   - Local cache (2 days)│
                    └──────────┬──────────────┘
                               │
                               │ Flush chunks every 30min
                               ▼
                    ┌─────────────────────────┐
                    │    S3: loki-logs        │
                    │    - Indexed by labels  │
                    │    - 90 day retention   │
                    └──────────┬──────────────┘
                               │
                               │ Query via label index
                               ▼
                    ┌─────────────────────────┐
                    │     Loki Queriers       │
                    │   - LogQL Engine        │
                    │   - Parallel queries    │
                    └──────────┬──────────────┘
                               │
                               │ LogQL Queries
                               ▼
                    ┌─────────────────────────┐
                    │       Grafana           │
                    │     (Logs UI)           │
                    └─────────────────────────┘
```

#### Log Data Specifications
```yaml
Log Volume:
  - 50 hosts × 1GB/day/host = 50GB/day
  - Compression: ~5:1 ratio = 10GB/day stored
  - Monthly: ~300GB/month in S3

Log Pipeline:
  1. Promtail discovers log files via file_sd_configs
  2. Applies labels: {host, env, app, level}
  3. Extracts structured fields from JSON logs
  4. Pushes to Loki via HTTP

Retention:
  - S3 Standard: 30 days
  - S3 Glacier Instant Retrieval: 31-90 days
  - Delete: After 90 days

Log Parsing:
  - JSON logs: Automatic field extraction
  - Unstructured logs: Regex parsing at query time (LogQL)
```

### 3.3 Traces Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        Monitored Hosts (50x)                     │
│                                                                   │
│  ┌──────────────────────────────────┐                           │
│  │ Application (OpenTelemetry SDK)  │                           │
│  │  - Auto-instrumentation or       │                           │
│  │  - Manual span creation          │                           │
│  └──────────────┬───────────────────┘                           │
│                 │                                                 │
│                 │ OTLP/gRPC (Port 4317)                          │
│                 │                                                 │
│  ┌──────────────▼───────────┐                                   │
│  │   OTel Collector         │                                   │
│  │   - Batch processor      │                                   │
│  │   - Sampling (if needed) │                                   │
│  │   - Attribute enrichment │                                   │
│  └──────────────┬───────────┘                                   │
└─────────────────┼───────────────────────────────────────────────┘
                  │
                  │ OTLP/gRPC
                  │ (100% of traces)
                  ▼
       ┌──────────────────────────┐
       │  Tempo Distributors      │
       │  (Load balanced)         │
       └──────────┬───────────────┘
                  │
                  │ Hash ring distribution
                  ▼
       ┌──────────────────────────┐
       │    Tempo Ingesters       │
       │   - Write to WAL         │
       │   - Build trace blocks   │
       └──────────┬───────────────┘
                  │
                  │ Flush complete traces
                  ▼
       ┌──────────────────────────┐
       │   S3: tempo-traces       │
       │   - Parquet format       │
       │   - 30 day retention     │
       └──────────┬───────────────┘
                  │
                  │ Query via TraceID or TraceQL
                  ▼
       ┌──────────────────────────┐
       │     Tempo Queriers       │
       │   - TraceQL Engine       │
       │   - Exemplar links       │
       └──────────┬───────────────┘
                  │
                  │ Trace Queries + Exemplars
                  ▼
       ┌──────────────────────────┐
       │       Grafana            │
       │   - Trace Viewer UI      │
       │   - Span details         │
       │   - Service graph        │
       └──────────────────────────┘
```

#### Trace Data Specifications
```yaml
Trace Volume:
  - 150 services × 1000 requests/min = 150K spans/min
  - Span size: ~2KB average
  - Daily: 150K × 60 × 24 × 2KB = ~43GB/day raw
  - Compressed: ~20GB/day stored

Sampling Strategy:
  - Tail-based sampling at OTel Collector (optional)
  - Sample 100% of errors
  - Sample 10-20% of successful requests
  - Adaptive sampling for high-traffic services

Trace Context Propagation:
  - W3C Trace Context (traceparent header)
  - Automatic via OTel auto-instrumentation

Exemplars:
  - Link traces to metrics (e.g., latency histogram → trace)
  - Configured in Prometheus remote write
```

### 3.4 Correlation Architecture (Unified Observability)

```
┌────────────────────────────────────────────────────────────┐
│                       GRAFANA                              │
│                  (Single Pane of Glass)                     │
│                                                             │
│  ┌────────────┐    ┌────────────┐    ┌────────────┐      │
│  │  Metrics   │    │    Logs    │    │   Traces   │      │
│  │ Dashboard  │    │  Explorer  │    │   Viewer   │      │
│  └─────┬──────┘    └─────┬──────┘    └─────┬──────┘      │
│        │                 │                  │              │
└────────┼─────────────────┼──────────────────┼──────────────┘
         │                 │                  │
         │                 │                  │
    Correlation Labels (service, host, env, pod)
         │                 │                  │
         ▼                 ▼                  ▼
   [traceID=xyz]    [traceID=xyz]     [traceID=xyz]
   [host=web-01]    [host=web-01]     [host=web-01]
```

**Correlation Keys:**
```yaml
Standard Labels (applied at OTel Collector):
  service.name: "user-service"
  deployment.environment: "production"
  host.name: "web-01"
  k8s.pod.name: "user-svc-abc123" (if K8s)

Trace-Metric Linking:
  - Exemplars in Prometheus metrics point to traceID
  - Click histogram bar → see actual traces

Trace-Log Linking:
  - Logs include traceID as structured field
  - Click span → see related logs

Metric-Log Linking:
  - Shared labels (host, service, env)
  - Query logs filtered by same labels as metric alert
```

---

## 4. Scaling Considerations for 50 Hosts

### 4.1 Current Capacity Planning

**Metrics:**
```
Current: 20,000 active series
Headroom: Prometheus can handle 1M series per instance
Scaling Trigger: >500K series → add Prometheus replica

Current: ~400 samples/sec ingestion
Headroom: Prometheus can handle 500K samples/sec
```

**Logs:**
```
Current: 50GB/day (10GB compressed)
Headroom: Loki can handle 500GB/day per instance
Scaling Trigger: >300GB/day → split Loki read/write paths
```

**Traces:**
```
Current: ~20GB/day compressed
Headroom: Tempo can handle 1TB/day
Scaling Trigger: >500GB/day → add Tempo ingesters
```

### 4.2 Horizontal Scaling Path

**Scale to 100 hosts:**
- Increase Prometheus retention from 15 to 10 days (same storage)
- No other changes needed

**Scale to 250 hosts:**
- Add 1x Prometheus instance (3 total)
- Upgrade Loki to distributed mode (separate ingesters/queriers)
- Add 1x Tempo ingester

**Scale to 500+ hosts:**
- Migrate to EKS for better orchestration
- Consider VictoriaMetrics cluster for better compression
- Implement OTel Gateway tier for centralized processing

### 4.3 Vertical Scaling Recommendations

**When to scale up vs. out:**

Scale Up (increase instance size):
- Loki queriers: CPU-bound for LogQL regex queries
- Tempo queriers: Memory-bound for large trace reconstructions
- Grafana: DB-bound for dashboard rendering

Scale Out (add more instances):
- Prometheus: Shard targets across instances
- Loki ingesters: Distribute write load
- Thanos Store Gateway: Parallelize S3 queries

### 4.4 Data Retention vs. Cost

**Retention Strategy:**
```yaml
Metrics:
  Hot:  15 days (Prometheus local SSD)
  Warm: 90 days, 5min resolution (Thanos S3 Standard)
  Cold: 2 years, 1h resolution (Thanos S3 Intelligent-Tiering)
  
  Cost: $50-70/month for 2 years of data

Logs:
  Hot:  7 days (Loki local cache)
  Warm: 90 days (S3 Standard)
  
  Cost: ~$40/month for 90 days

Traces:
  Hot:  7 days (Tempo local)
  Cold: 30 days (S3 Standard, then delete)
  
  Cost: ~$15/month for 30 days
  Note: Traces are rarely queried after 7 days
```

**Cost Optimization Tips:**
1. Use S3 Intelligent-Tiering for metrics (auto-transition)
2. Implement aggressive downsampling (5min → 1h after 30 days)
3. Delete traces after 30 days (keep exemplars in metrics)
4. Use S3 Lifecycle policies for automatic transitions

### 4.5 Query Performance Optimization

**Prometheus/Thanos:**
- Use recording rules for expensive dashboards
- Pre-aggregate common queries (95th percentile latency, error rate)
- Set query timeout to 2 minutes
- Enable query result caching in Thanos Query Frontend

**Loki:**
- Limit query range to 24 hours by default
- Use structured metadata for high-cardinality fields
- Index only filterable labels (not log content)
- Enable query frontend for parallelization

**Tempo:**
- Query by TraceID is instant (indexed)
- TraceQL queries can be slow (scan all blocks)
- Use exemplars to jump from metrics → traces (best UX)

---

## 5. Real User Monitoring (RUM) Alternatives

### 5.1 Open-Source RUM Options

#### Option 1: Grafana Faro (Recommended)
```yaml
Project: grafana/faro-web-sdk
Status: Active (v1.3+)
License: Apache 2.0

Capabilities:
  ✅ Browser performance metrics (Core Web Vitals)
  ✅ JavaScript errors and stack traces
  ✅ User sessions and page views
  ✅ Custom events and measurements
  ✅ Integration with Tempo (frontend → backend traces)
  ✅ Loki integration for browser logs

Architecture:
  Frontend: @grafana/faro-web-sdk (npm package)
  Backend: Faro Collector (receives RUM data)
  Storage: Loki (logs) + Tempo (traces) + Mimir/Prometheus (metrics)
  
Setup:
  npm install @grafana/faro-web-sdk
  
  import { initializeFaro } from '@grafana/faro-web-sdk';
  
  initializeFaro({
    url: 'https://faro-collector.example.com/collect',
    app: {
      name: 'my-web-app',
      version: '1.0.0',
    },
  });

AWS Infrastructure:
  - Deploy Faro Collector on t3.small (1 instance per region)
  - ALB for HTTPS termination
  - CloudFront for global distribution
  - Cost: ~$40/month + CloudFront bandwidth

Data Collected:
  - Page load timings (TTFB, FCP, LCP)
  - JavaScript errors with source maps
  - User interactions (clicks, navigation)
  - Network requests (fetch/XHR)
  - Browser metadata (user-agent, viewport)
```

#### Option 2: OpenTelemetry Browser SDK
```yaml
Project: open-telemetry/opentelemetry-js
Status: Stable (v1.20+)
License: Apache 2.0

Capabilities:
  ✅ W3C Trace Context propagation (frontend → backend)
  ✅ Browser instrumentation (XHR, fetch, user interactions)
  ✅ Custom spans and metrics
  ✅ Automatic instrumentation via plugins
  ⚠️  No built-in RUM-specific features (need custom implementation)

Setup:
  npm install @opentelemetry/api @opentelemetry/sdk-trace-web
  
  import { WebTracerProvider } from '@opentelemetry/sdk-trace-web';
  import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
  
  const provider = new WebTracerProvider();
  provider.addSpanProcessor(
    new BatchSpanProcessor(
      new OTLPTraceExporter({
        url: 'https://tempo.example.com/v1/traces',
      })
    )
  );

Best For:
  - Teams already using OTel for backend
  - Need custom frontend instrumentation
  - Want full trace continuity (browser → API → DB)

Limitations:
  - No out-of-box Core Web Vitals dashboard
  - Requires more custom code than Faro
```

#### Option 3: Plausible Analytics (Privacy-Focused)
```yaml
Project: plausible/analytics
Status: Mature (v2.0+)
License: AGPLv3 (open-source) / Commercial (self-hosted)

Capabilities:
  ✅ Page views and unique visitors
  ✅ Traffic sources and campaigns
  ✅ Goal tracking and conversions
  ✅ No cookies (GDPR compliant)
  ⚠️  NOT for performance monitoring (analytics only)

Best For:
  - Privacy-focused web analytics
  - Replacing Google Analytics
  - Simple visitor tracking

Not Suitable For:
  - Performance monitoring
  - Error tracking
  - Technical observability
```

#### Option 4: Sentry (Error Tracking + Performance)
```yaml
Project: getsentry/sentry
Status: Mature (v24+)
License: BSL 1.1 (Business Source License, converts to Apache 2.0 after 3 years)

Capabilities:
  ✅ JavaScript error tracking with source maps
  ✅ Session replay (limited in self-hosted)
  ✅ Performance monitoring (transactions, web vitals)
  ✅ User feedback widgets
  ✅ Release tracking and alerting

Setup:
  npm install @sentry/react
  
  Sentry.init({
    dsn: 'https://key@sentry.example.com/project-id',
    integrations: [new BrowserTracing()],
    tracesSampleRate: 0.1,
  });

Self-Hosted Infrastructure:
  - Requires: PostgreSQL, Redis, Kafka, Clickhouse
  - Recommended: 3x t3.medium + RDS + ElastiCache + MSK
  - Cost: ~$300-400/month AWS infrastructure
  - Complexity: High (many moving parts)

Limitations:
  - Session replay requires Sentry Cloud (not in self-hosted)
  - Heavy infrastructure requirements
  - License restrictions (not pure open-source)
```

### 5.2 RUM Comparison Matrix

| Feature | Grafana Faro | OTel Browser | Sentry | Plausible |
|---------|--------------|--------------|--------|-----------|
| **Core Web Vitals** | ✅ Built-in | ⚠️ Custom | ✅ Built-in | ❌ |
| **Error Tracking** | ✅ Yes | ⚠️ Custom | ✅ Advanced | ❌ |
| **Trace Continuity** | ✅ Tempo | ✅ Native | ⚠️ Limited | ❌ |
| **Session Replay** | ❌ No | ❌ No | ⚠️ Cloud only | ❌ |
| **Infrastructure** | Lightweight | Lightweight | Heavy | Lightweight |
| **Setup Complexity** | Low | Medium | High | Low |
| **Monthly Cost** | ~$40 | ~$20 | ~$300+ | ~$30 |
| **License** | Apache 2.0 | Apache 2.0 | BSL 1.1 | AGPLv3 |

**Recommendation for Your PoC:** **Grafana Faro**

**Why:**
- Designed specifically for Grafana stack
- Lightweight infrastructure (single collector)
- Native integration with Loki + Tempo + Prometheus
- Best frontend-to-backend correlation story
- Low cost (~$40/month)

### 5.3 Grafana Faro Implementation Guide

#### Step 1: Deploy Faro Collector
```bash
# Run on t3.small EC2 instance
docker run -d \
  -p 12347:12347 \
  -v /etc/faro/config.yaml:/etc/faro/config.yaml \
  grafana/faro-collector:latest
```

#### Step 2: Faro Collector Configuration
```yaml
# /etc/faro/config.yaml
receivers:
  faro:
    endpoint: 0.0.0.0:12347
    cors_allowed_origins:
      - "https://yourdomain.com"
      - "https://*.yourdomain.com"

processors:
  batch:
    timeout: 10s
    send_batch_size: 1000

exporters:
  # Send RUM logs to Loki
  loki:
    endpoint: http://loki-internal-lb:3100/loki/api/v1/push
    labels:
      resource:
        service.name: "service_name"
        app: "app"
  
  # Send RUM traces to Tempo
  otlp:
    endpoint: http://tempo:4317
    tls:
      insecure: true
  
  # Send RUM metrics to Prometheus
  prometheusremotewrite:
    endpoint: http://prometheus:9090/api/v1/write

service:
  pipelines:
    logs:
      receivers: [faro]
      processors: [batch]
      exporters: [loki]
    traces:
      receivers: [faro]
      processors: [batch]
      exporters: [otlp]
    metrics:
      receivers: [faro]
      processors: [batch]
      exporters: [prometheusremotewrite]
```

#### Step 3: Frontend Integration
```typescript
// main.tsx or index.tsx
import { initializeFaro, getWebInstrumentations } from '@grafana/faro-web-sdk';

export const faro = initializeFaro({
  url: 'https://faro.yourdomain.com/collect',
  app: {
    name: 'my-web-app',
    version: process.env.REACT_APP_VERSION || '1.0.0',
    environment: process.env.NODE_ENV,
  },
  instrumentations: [
    ...getWebInstrumentations({
      captureConsole: true,
      captureConsoleDisabledLevels: ['debug'],
    }),
  ],
});

// Custom event tracking
faro.api.pushEvent('button_clicked', {
  button_id: 'checkout',
  user_id: '12345',
});

// Custom measurement
faro.api.pushMeasurement({
  type: 'custom_metric',
  values: {
    api_response_time: 234,
  },
});
```

#### Step 4: Grafana Dashboard for RUM
```json
// Import pre-built dashboard
// Dashboard ID: 18212 (Grafana Faro Web SDK)

Panels include:
- Page Load Times (P50, P95, P99)
- Core Web Vitals (LCP, FID, CLS)
- JavaScript Errors (count, error rate)
- Top Pages by Traffic
- Browser/Device Breakdown
- Geographic Distribution
```

### 5.4 RUM Data Retention & Cost

```yaml
Faro Collector Traffic:
  - Typical website: 10K page views/day
  - Events per page view: ~5-10
  - Data per event: ~2KB
  - Daily data: 10K × 7 × 2KB = 140MB/day
  - Monthly: ~4GB/month

Storage in Loki:
  - 4GB × $0.023/GB = $0.10/month (negligible)

Bandwidth:
  - CloudFront: 4GB × $0.085/GB = $0.34/month
  - ALB: 4GB × $0.008/GB = $0.03/month

Total RUM Cost: ~$40/month (mostly compute for Faro Collector)
```

---

## 6. Deployment Automation

### 6.1 Infrastructure as Code (Terraform)

**Repository Structure:**
```
observability-platform/
├── terraform/
│   ├── modules/
│   │   ├── prometheus/
│   │   ├── thanos/
│   │   ├── loki/
│   │   ├── tempo/
│   │   ├── grafana/
│   │   └── networking/
│   ├── environments/
│   │   ├── dev/
│   │   └── prod/
│   └── main.tf
├── ansible/
│   ├── playbooks/
│   │   ├── prometheus.yml
│   │   ├── otel-collector.yml
│   │   └── exporters.yml
│   └── inventory/
├── configs/
│   ├── prometheus/
│   ├── loki/
│   ├── tempo/
│   └── grafana/
└── dashboards/
    ├── infrastructure.json
    ├── application.json
    └── rum.json
```

### 6.2 Configuration Management

**Ansible for Configuration:**
- Deploy OTel Collector to all 50 hosts
- Configure Promtail for log collection
- Install node_exporter
- Update configs without redeployment

### 6.3 Monitoring the Monitoring

**Self-Observability:**
```yaml
Prometheus monitors itself:
  - prometheus_tsdb_head_series (cardinality)
  - prometheus_http_request_duration_seconds (query performance)

Loki monitors itself:
  - loki_ingester_chunks_created_total
  - loki_request_duration_seconds

Grafana has built-in stats:
  - grafana_stats_dashboards_total
  - grafana_stats_users_active

Alerts:
  - PrometheusDown
  - LokiIngesterUnhealthy
  - TempoDistributorUnhealthy
  - GrafanaAPIError
```

---

## 7. Security Considerations

### 7.1 Access Control

```yaml
Grafana Authentication:
  - SSO via SAML/OAuth (Okta, Google Workspace, Azure AD)
  - RBAC: Viewer, Editor, Admin roles
  - API key authentication for automation

Prometheus Security:
  - Basic auth on scrape endpoints
  - mTLS for Thanos gRPC (optional)
  - No public internet exposure (private subnets only)

Loki Security:
  - Tenant ID in headers (for multi-tenancy)
  - Basic auth on Promtail → Loki
  - S3 bucket encryption (SSE-S3 or SSE-KMS)
```

### 7.2 Network Security

```yaml
TLS/SSL:
  - ALB terminates TLS (ACM certificate)
  - Internal traffic can be plain HTTP (within VPC)
  - Optional: mTLS for paranoid security

VPC Endpoints:
  - S3 VPC endpoint (no NAT gateway costs)
  - Secrets Manager endpoint (for config)

IAM Roles:
  - EC2 instance roles for S3 access
  - Least privilege (read-only for Store Gateway)
  - Write-only for Prometheus Sidecar
```

### 7.3 Secrets Management

```yaml
AWS Secrets Manager:
  - Grafana admin password
  - Database credentials
  - API keys for integrations

Retrieved at boot via:
  - EC2 user-data scripts
  - Systemd EnvironmentFile
  - Never hardcoded in config files
```

---

## 8. Operational Runbooks

### 8.1 Common Issues & Resolutions

**Prometheus Out of Memory**
```bash
Symptom: Prometheus pod/instance crashes with OOMKilled
Diagnosis: Check cardinality
  promtool tsdb analyze /prometheus/data
Resolution:
  1. Identify high-cardinality metrics
  2. Add metric_relabel_configs to drop labels
  3. Increase memory (double RAM)
```

**Loki Query Timeout**
```bash
Symptom: "Query timeout exceeded" in Grafana
Diagnosis: Query too broad (time range or cardinality)
Resolution:
  1. Limit query to 24 hours max
  2. Use specific label filters
  3. Add more Loki queriers (scale horizontally)
```

**Thanos Store Gateway Slow Queries**
```bash
Symptom: Dashboard loads take >30 seconds
Diagnosis: Cold S3 data, large time ranges
Resolution:
  1. Use recording rules for common queries
  2. Enable query result caching (Redis)
  3. Reduce query time range
  4. Add more Store Gateway instances
```

### 8.2 Backup & Disaster Recovery

```yaml
Prometheus:
  - Snapshot via Admin API: POST /api/v1/admin/tsdb/snapshot
  - Backup to S3 (automated daily)
  - Restore: Copy snapshot to data dir, restart

Loki:
  - Indexes backed up to S3 (automatic)
  - No manual backup needed (chunks already in S3)

Grafana:
  - Database backup: RDS automated snapshots (daily)
  - Dashboards: Version control in Git (export JSON)
  - Restore: Import JSON or restore RDS snapshot

Tempo:
  - Traces in S3 (no additional backup)
  - Recent traces in WAL (ephemeral, acceptable loss)
```

### 8.3 Upgrade Strategy

```yaml
Rolling Upgrades:
  Prometheus:
    1. Upgrade instance 1, wait 10 minutes
    2. Verify metrics still flowing
    3. Upgrade instance 2

  Loki:
    1. Upgrade queriers first (stateless)
    2. Upgrade ingesters (drain connections first)

  Grafana:
    1. Take DB snapshot
    2. Upgrade instance 1, test UI
    3. Upgrade instance 2

Testing:
  - Always test in dev environment first
  - Run query regression tests
  - Verify alert rules still fire
```

---

## 9. Migration Path & Phased Rollout

### Phase 1: Core Infrastructure (Week 1-2)
```
1. Deploy Prometheus + Thanos
2. Deploy Grafana (with RDS backend)
3. Instrument 5 pilot hosts with OTel Collector
4. Create basic infrastructure dashboards
5. Validate data flow

Success Criteria:
  ✅ 5 hosts reporting metrics
  ✅ Data visible in Grafana
  ✅ S3 backup working
```

### Phase 2: Logs & Expanded Coverage (Week 3-4)
```
1. Deploy Loki
2. Install Promtail on all 50 hosts
3. Onboard 25 hosts to observability
4. Create log dashboards
5. Set up basic alerts

Success Criteria:
  ✅ 25 hosts logging to Loki
  ✅ LogQL queries working
  ✅ Logs-to-metrics correlation
```

### Phase 3: Traces & Correlation (Week 5-6)
```
1. Deploy Tempo
2. Instrument 10 applications with OTel SDK
3. Enable exemplars in Prometheus
4. Create trace dashboards
5. Test full correlation (metrics → logs → traces)

Success Criteria:
  ✅ End-to-end trace visibility
  ✅ Click-through from metrics to traces
  ✅ Error tracking with traces
```

### Phase 4: RUM & Advanced Features (Week 7-8)
```
1. Deploy Grafana Faro
2. Instrument frontend applications
3. Set up alerting (Grafana Unified Alerting)
4. Create runbooks and documentation
5. Train team on platform

Success Criteria:
  ✅ Frontend performance visibility
  ✅ Alert pipelines operational
  ✅ Team can self-service
```

---

## 10. Cost Summary

### 10.1 Monthly AWS Costs

| Category | Service | Monthly Cost |
|----------|---------|--------------|
| **Compute** | 11x EC2 instances (t3.medium to t3.xlarge) | $855 |
| **Database** | RDS PostgreSQL (db.t3.small Multi-AZ) | $50 |
| **Storage** | EBS volumes (2TB total) | $160 |
| **Storage** | S3 (4TB metrics + logs + traces) | $100 |
| **Networking** | ALB (1x public, 1x internal) | $45 |
| **Networking** | Data transfer (within VPC, negligible) | $10 |
| **RUM** | Faro Collector + CloudFront | $40 |
| **Total** | | **~$1,260/month** |

**Cost per Host:** $1,260 / 50 = **$25.20/host/month**

### 10.2 Cost Optimization Opportunities

```yaml
Immediate Savings:
  - Use Spot Instances for Thanos Compactor (-70%): Save $35/month
  - Use Graviton instances (ARM) where possible (-20%): Save ~$170/month
  - S3 Intelligent-Tiering for metrics: Save ~$20/month

6-Month Savings:
  - Reserved Instances (1-year commit, -30%): Save ~$250/month
  - Optimize data retention (reduce from 90d to 30d logs): Save ~$30/month

Total Optimized Cost: ~$800-900/month
```

### 10.3 Comparison with Commercial SaaS

| Provider | Cost for 50 hosts | Notes |
|----------|-------------------|-------|
| **Datadog** | ~$3,000-5,000/month | 50 hosts × $15/host + logs + APM |
| **New Relic** | ~$2,500-4,000/month | Consumption-based pricing |
| **Grafana Cloud** | ~$1,500-2,500/month | 50 hosts + logs + traces |
| **This Architecture** | ~$1,260/month | Full control, no vendor lock-in |

**ROI:** Save $1,500-3,500/month vs. SaaS (~60-70% cost reduction)

---

## 11. Success Metrics & KPIs

### Platform Health KPIs
```yaml
Availability:
  - Target: 99.5% uptime (3.6 hours/month downtime budget)
  - Measure: Synthetic checks to Grafana UI

Data Loss:
  - Target: <0.1% of metrics/logs/traces
  - Measure: Compare ingestion counts vs. storage counts

Query Performance:
  - Target: P95 query latency <5 seconds
  - Measure: Prometheus/Loki/Tempo query duration histograms

Storage Efficiency:
  - Target: <$30/TB/month all-in cost
  - Measure: S3 costs / total TB stored
```

### User Adoption KPIs
```yaml
Dashboard Usage:
  - Target: 80% of engineers use Grafana weekly
  - Measure: Grafana user analytics

Alert Effectiveness:
  - Target: <10% false positive rate
  - Measure: Alert feedback loop

Mean Time to Detect (MTTD):
  - Target: <5 minutes for critical issues
  - Measure: Time from incident to alert fire

Mean Time to Resolution (MTTR):
  - Target: <30 minutes for P1 incidents
  - Measure: Alert fire time to incident close
```

---

## 12. Next Steps & Recommendations

### Immediate Actions (Week 1)
1. **Provision AWS VPC** with subnets and security groups
2. **Deploy Terraform modules** for Prometheus + Grafana
3. **Instrument 5 pilot hosts** with OTel Collector
4. **Create infrastructure dashboard** (CPU, memory, disk)
5. **Document learnings** for team onboarding

### Short-Term Goals (Month 1)
1. **Onboard all 50 hosts** to metrics + logs
2. **Instrument top 10 critical services** with tracing
3. **Set up on-call rotation** with PagerDuty/Grafana OnCall
4. **Create runbooks** for common issues
5. **Train team** on query languages (PromQL, LogQL, TraceQL)

### Long-Term Goals (Quarter 1)
1. **Deploy RUM** (Grafana Faro) to production web apps
2. **Implement SLO dashboards** for key services
3. **Automate alert tuning** (reduce noise, increase signal)
4. **Optimize costs** (Reserved Instances, data retention tuning)
5. **Document success stories** (incidents resolved faster)

---

## Appendix A: Technology Decision Matrix

| Criteria | Prometheus + Thanos | VictoriaMetrics | Mimir |
|----------|---------------------|-----------------|-------|
| **Operational Complexity** | Medium | Low | High |
| **Query Performance** | Good | Excellent | Excellent |
| **Storage Efficiency** | Good (5:1) | Excellent (10:1) | Good (6:1) |
| **Community Size** | Very Large | Growing | Small |
| **AWS S3 Integration** | Excellent (Thanos) | Good | Excellent |
| **Cardinality Limits** | ~1M series/instance | ~10M series/instance | ~10M series/instance |
| **Best For** | Standard deployments | High-scale, cost-sensitive | Multi-tenant SaaS |

**Verdict:** Prometheus + Thanos offers best balance for PoC

---

## Appendix B: Useful Resources

### Documentation
- Prometheus: https://prometheus.io/docs/
- Thanos: https://thanos.io/
- Loki: https://grafana.com/docs/loki/
- Tempo: https://grafana.com/docs/tempo/
- OpenTelemetry: https://opentelemetry.io/docs/
- Grafana Faro: https://grafana.com/docs/faro-web-sdk/

### Community
- CNCF Slack: #prometheus, #thanos, #opentelemetry
- Grafana Community: https://community.grafana.com/

### Training
- Prometheus Certified: https://training.linuxfoundation.org/
- Grafana Labs Training: https://grafana.com/training/

---

**Document Maintained By:** Technical Lead Team  
**Review Cycle:** Quarterly  
**Last Architecture Review:** 2024-Q4
