# Product Requirements Document (PRD)
## Open-Source Observability Platform PoC
### "ObserveIt" - Enterprise Observability Without Enterprise Costs

**Version:** 1.0  
**Date:** February 2026  
**Author:** Product & Engineering Team  
**Status:** Draft for PoC Planning

---

## Executive Summary

This PRD outlines a Proof of Concept for an open-source observability platform designed to monitor 50 hosts and applications with metrics, logs, and distributed tracing capabilities. The platform provides a cost-effective alternative to commercial solutions like Datadog and New Relic, leveraging proven CNCF-graduated projects.

**Key Numbers:**
- **Target Scale:** 50 hosts/applications
- **Estimated Monthly Cost:** $1,200 - $2,400 (AWS)
- **Commercial Equivalent:** $5,500 - $9,200/month (Datadog/New Relic)
- **Projected Savings:** 60-80% ($44,000 - $100,000+ annually)

---

## 1. Problem Statement

### The Observability Economics Problem

Modern organizations face a critical challenge: observability is no longer optional, but commercial platforms have created unsustainable cost structures.

| Challenge | Impact |
|-----------|--------|
| **Cost Explosion** | Datadog/New Relic costs $150K-$200K/year for 50 hosts with full-stack monitoring |
| **Vendor Lock-in** | Proprietary agents, formats, and query languages trap data |
| **Data Sovereignty** | Sensitive operational data leaves your infrastructure |
| **Unpredictable Billing** | Per-host, per-GB, per-metric pricing creates budget anxiety |

### Why Now?

The open-source observability ecosystem has matured significantly:
- **Prometheus** (CNCF Graduated) - de facto metrics standard
- **OpenTelemetry** (CNCF) - unified instrumentation standard
- **Grafana** - best-in-class visualization (unified dashboards)
- **Loki/Tempo** - cloud-native logs and traces

---

## 2. Target Users

### Primary Personas

| Persona | Role | Goals | Pain Points |
|---------|------|-------|-------------|
| **Engineering Leader** | VP/Director of Engineering | Control costs, maintain visibility | Unpredictable observability bills |
| **Platform Engineer** | DevOps/SRE | Build reliable infrastructure | Tool sprawl, context switching |
| **Application Developer** | Backend/Full-stack | Debug issues quickly | Slow query times, missing context |

### Ideal Company Profile
- **Size:** 20-200 engineers
- **Stage:** Series A to Series C ($1M-$50M ARR)
- **Infrastructure:** Cloud-native, AWS/GCP/Azure
- **Culture:** Open-source friendly, cost-conscious

---

## 3. Solution Overview

### The LGTM Stack (Loki, Grafana, Tempo, Mimir/Prometheus)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              GRAFANA UI                                  │
│                    (Unified Dashboards & Alerting)                       │
└─────────────────────────────────────────────────────────────────────────┘
         │                        │                        │
         ▼                        ▼                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│     MIMIR       │    │      LOKI       │    │     TEMPO       │
│   (Metrics)     │    │     (Logs)      │    │    (Traces)     │
│                 │    │                 │    │                 │
│  Long-term      │    │  Log            │    │  Distributed    │
│  Prometheus     │    │  Aggregation    │    │  Tracing        │
│  Storage        │    │                 │    │                 │
└────────┬────────┘    └────────┬────────┘    └────────┬────────┘
         │                      │                      │
         └──────────────────────┼──────────────────────┘
                                │
                    ┌───────────┴───────────┐
                    │   OPENTELEMETRY       │
                    │     COLLECTOR         │
                    │  (Unified Ingestion)  │
                    └───────────┬───────────┘
                                │
         ┌──────────────────────┼──────────────────────┐
         │                      │                      │
         ▼                      ▼                      ▼
   ┌───────────┐          ┌───────────┐          ┌───────────┐
   │  Host 1   │          │  Host 2   │          │  Host N   │
   │  OTel     │          │  OTel     │          │  OTel     │
   │  Agent    │          │  Agent    │          │  Agent    │
   └───────────┘          └───────────┘          └───────────┘
```

---

## 4. Technical Architecture

### 4.1 Component Selection

| Component | Selected Tool | Version | Alternatives Considered |
|-----------|--------------|---------|------------------------|
| **Metrics Collection** | Prometheus | 2.50+ | VictoriaMetrics |
| **Metrics Storage** | Grafana Mimir | 2.11+ | Thanos, Cortex |
| **Log Aggregation** | Grafana Loki | 3.0+ | OpenSearch, Elasticsearch |
| **Distributed Tracing** | Grafana Tempo | 2.4+ | Jaeger, Zipkin |
| **Visualization** | Grafana | 10.3+ | - |
| **Alerting** | Grafana Alerting | Built-in | Alertmanager |
| **Data Collection** | OpenTelemetry Collector | 0.96+ | Prometheus exporters |

### 4.2 AWS Infrastructure

#### Compute Resources (EC2)

| Component | Instance Type | Count | Purpose |
|-----------|--------------|-------|---------|
| **Grafana** | t3.medium | 1 | UI, dashboards, alerting |
| **Mimir (All-in-one)** | m5.large | 1 | Metrics ingestion & storage |
| **Loki (All-in-one)** | m5.large | 1 | Log ingestion & storage |
| **Tempo (All-in-one)** | m5.large | 1 | Trace ingestion & storage |
| **OTel Collector Gateway** | t3.medium | 2 | Centralized data routing |

**For HA Production (Optional):**
- Add second instance for each component
- Use Application Load Balancer

#### Storage

| Type | Size | Purpose |
|------|------|---------|
| **EBS gp3** | 100GB per node | Local working storage |
| **S3 Standard** | ~500GB/month | Long-term data retention |
| **S3 Intelligent-Tiering** | As needed | Archive tier for old data |

#### Networking

```
┌─────────────────────────────────────────────────────────────────┐
│                           VPC                                    │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    Public Subnet                             ││
│  │  ┌─────────────┐                                            ││
│  │  │     ALB     │ ◄─── HTTPS (Grafana UI)                    ││
│  │  └──────┬──────┘                                            ││
│  └─────────┼───────────────────────────────────────────────────┘│
│            │                                                     │
│  ┌─────────┼───────────────────────────────────────────────────┐│
│  │         ▼        Private Subnet                              ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          ││
│  │  │  Grafana    │  │   Mimir     │  │    Loki     │          ││
│  │  └─────────────┘  └─────────────┘  └─────────────┘          ││
│  │  ┌─────────────┐  ┌─────────────┐                           ││
│  │  │   Tempo     │  │ OTel GW x2  │ ◄─── gRPC/HTTP (agents)   ││
│  │  └─────────────┘  └─────────────┘                           ││
│  └─────────────────────────────────────────────────────────────┘│
│                              │                                   │
│                    ┌─────────┴─────────┐                        │
│                    │   VPC Endpoint    │                        │
│                    │      (S3)         │                        │
│                    └───────────────────┘                        │
└─────────────────────────────────────────────────────────────────┘
```

### 4.3 Data Flow

```
Monitored Hosts (50)
        │
        │ OTel Agent (per host)
        │ - Collects metrics (host, containers, apps)
        │ - Collects logs (journald, files)
        │ - Collects traces (auto-instrumentation)
        │
        ▼
┌─────────────────────────────┐
│   OTel Collector Gateway    │
│   - Batching & buffering    │
│   - Protocol translation    │
│   - Filtering & sampling    │
└─────────────────────────────┘
        │
        ├──── Metrics (OTLP) ───► Mimir ───► S3
        │
        ├──── Logs (OTLP) ──────► Loki ────► S3
        │
        └──── Traces (OTLP) ────► Tempo ───► S3
                                     │
                                     ▼
                              ┌─────────────┐
                              │   Grafana   │
                              │  (Query &   │
                              │  Visualize) │
                              └─────────────┘
```

### 4.4 Data Volume Estimates (50 Hosts)

| Data Type | Ingestion Rate | Daily Volume | Monthly Volume |
|-----------|---------------|--------------|----------------|
| **Metrics** | ~100,000 samples/min | ~5GB | ~150GB |
| **Logs** | ~50GB/day | ~50GB | ~1.5TB |
| **Traces** | ~10GB/day (10% sampling) | ~10GB | ~300GB |
| **Total** | - | ~65GB | ~2TB |

### 4.5 Real User Monitoring (RUM) Options

**Gap Acknowledged:** Pure open-source RUM is less mature than commercial solutions.

| Option | Approach | Maturity |
|--------|----------|----------|
| **Grafana Faro** | Open-source RUM SDK | Beta/Early |
| **OpenTelemetry Browser** | OTEL JS SDK | Experimental |
| **Sentry (Self-hosted)** | Error tracking + performance | Production-ready |
| **Hybrid: PostHog + Grafana** | Product analytics + observability | Production-ready |

**Recommendation:** Use **Grafana Faro** for PoC, evaluate **Sentry OSS** for error tracking, plan for potential hybrid (commercial RUM + OSS backend) if needed.

---

## 5. AWS Cost Estimation

### 5.1 Detailed Monthly Breakdown

#### Compute (EC2 - On-Demand Pricing)

| Instance | Type | Count | $/Hour | Monthly |
|----------|------|-------|--------|---------|
| Grafana | t3.medium | 1 | $0.0416 | $31 |
| Mimir | m5.large | 1 | $0.096 | $70 |
| Loki | m5.large | 1 | $0.096 | $70 |
| Tempo | m5.large | 1 | $0.096 | $70 |
| OTel Gateway | t3.medium | 2 | $0.0416 | $62 |
| **Subtotal** | | | | **$303** |

#### Storage

| Type | Size | Rate | Monthly |
|------|------|------|---------|
| EBS gp3 (6 nodes x 100GB) | 600GB | $0.08/GB | $48 |
| S3 (metrics, logs, traces) | 2TB | $0.023/GB | $47 |
| S3 API requests | ~10M | $0.0004/1K | $40 |
| **Subtotal** | | | **$135** |

#### Networking

| Component | Usage | Monthly |
|-----------|-------|---------|
| ALB | 1 LCU average | $22 |
| Data Transfer (out) | 100GB | $9 |
| NAT Gateway* | 500GB | $45 |
| **Subtotal** | | **$76** |

*Eliminated with VPC Endpoints

#### Total Baseline

| Category | Monthly Cost |
|----------|-------------|
| Compute | $303 |
| Storage | $135 |
| Networking | $76 |
| **Total (On-Demand)** | **$514** |

### 5.2 Realistic Scenarios

| Scenario | Configuration | Monthly Cost | Annual Cost |
|----------|--------------|--------------|-------------|
| **Basic/Dev** | Single node each, minimal HA | $850 - $1,100 | $10,200 - $13,200 |
| **Production** | HA across 2 AZs, 30-day retention | $1,800 - $2,400 | $21,600 - $28,800 |
| **Enterprise** | Full HA, 90-day retention, EKS | $3,500 - $4,500 | $42,000 - $54,000 |

### 5.3 Comparison to Commercial Solutions

| Platform | 50 Hosts/Month | 50 Hosts/Year | Features |
|----------|---------------|---------------|----------|
| **This Solution (Prod)** | $1,800 | $21,600 | Full stack |
| **Datadog Full Stack** | $5,500 | $66,000 | Metrics + APM + Logs |
| **Datadog Infrastructure** | $900 | $10,800 | Metrics only |
| **New Relic Pro** | $3,750 | $45,000 | 5 users, 400GB |
| **Elastic Cloud** | $2,850 | $34,200 | Logs + metrics |

### 5.4 Cost Optimization Strategies

| Strategy | Savings | Implementation Effort |
|----------|---------|----------------------|
| 1-year Reserved Instances | 35-40% on EC2 | Low (commit) |
| 3-year Reserved Instances | 55-60% on EC2 | Low (commit) |
| Spot Instances (non-critical) | 60-70% on EC2 | Medium |
| VPC Endpoints (S3) | $50-100/mo | Low |
| S3 Intelligent-Tiering | 20-40% on storage | Low |
| Aggressive retention (30 days) | 30-50% on storage | Low |

**Optimized Production Cost:** $1,200 - $1,500/month

### 5.5 Total Cost of Ownership (TCO)

| Cost Category | Self-Hosted | Datadog |
|---------------|-------------|---------|
| Platform/Infrastructure | $1,800/mo | $5,500/mo |
| DevOps Time (0.5 FTE) | $4,000/mo | $500/mo |
| Training & Onboarding | $500/mo | $200/mo |
| **Total TCO** | **$6,300/mo** | **$6,200/mo** |

**Break-even Point:** ~50 hosts with 0.5 FTE dedicated

**At 100+ hosts:**
| Metric | Self-Hosted | Datadog |
|--------|-------------|---------|
| Infrastructure | $2,800/mo | $11,000/mo |
| DevOps (same 0.5 FTE) | $4,000/mo | $500/mo |
| **Total TCO** | **$6,800/mo** | **$11,500/mo** |
| **Annual Savings** | | **$56,400** |

---

## 6. Success Criteria

### PoC Acceptance Criteria

| Category | Metric | Target |
|----------|--------|--------|
| **Coverage** | Hosts monitored | 50/50 (100%) |
| **Metrics** | Samples ingested | 100K/min |
| **Logs** | Log lines ingested | 1M/day |
| **Traces** | Traces stored | 100K/day |
| **Query Performance** | P95 dashboard load | < 3 seconds |
| **Alerting** | Alert delivery | < 1 minute |
| **Uptime** | Platform availability | 99.5% |
| **Cost** | Monthly AWS bill | < $2,500 |

### Go/No-Go Decision Matrix

| Outcome | Criteria |
|---------|----------|
| **GO** | All metrics met, team satisfaction > 4/5, cost < Datadog |
| **CONDITIONAL** | 80% metrics met, identified gaps have mitigation plan |
| **NO-GO** | < 70% metrics met, or critical gaps (e.g., query performance) |

---

## 7. Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)
- [ ] Provision AWS infrastructure (Terraform)
- [ ] Deploy Grafana, Mimir, Loki, Tempo
- [ ] Configure OTel Collector Gateway
- [ ] Set up S3 storage backends

### Phase 2: Agent Deployment (Weeks 3-4)
- [ ] Create OTel Collector agent configuration
- [ ] Deploy agents to 10 pilot hosts
- [ ] Validate metrics, logs, traces flowing
- [ ] Iterate on configuration

### Phase 3: Scale & Dashboards (Weeks 5-6)
- [ ] Roll out agents to remaining 40 hosts
- [ ] Build standard dashboards (host, application, SLOs)
- [ ] Configure alerting rules
- [ ] Document runbooks

### Phase 4: Validation (Weeks 7-8)
- [ ] Performance testing under load
- [ ] User acceptance testing
- [ ] Cost analysis vs projections
- [ ] Go/No-Go decision

---

## 8. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Performance at scale | Medium | High | Load test early, horizontal scaling ready |
| RUM gap blocks adoption | Low | Medium | Plan hybrid approach, defer to Phase 2 |
| DevOps bandwidth | Medium | Medium | Prioritize automation, IaC |
| Learning curve | Medium | Low | Training, documentation, Grafana familiarity |
| Vendor changes (Grafana Labs) | Low | Medium | CNCF standards ensure portability |

---

## 9. Appendix

### A. Technology Stack Summary

```
┌────────────────────────────────────────────────────────────────┐
│                        PRESENTATION                             │
│  Grafana 10.3+ (Dashboards, Explore, Alerting)                 │
└────────────────────────────────────────────────────────────────┘
┌────────────────────────────────────────────────────────────────┐
│                          STORAGE                                │
│  Mimir (Metrics) │ Loki (Logs) │ Tempo (Traces) │ S3 (Backend) │
└────────────────────────────────────────────────────────────────┘
┌────────────────────────────────────────────────────────────────┐
│                        COLLECTION                               │
│  OpenTelemetry Collector (Gateway + Agents)                    │
└────────────────────────────────────────────────────────────────┘
┌────────────────────────────────────────────────────────────────┐
│                       INSTRUMENTATION                           │
│  OTEL SDKs (Java, Python, Node, Go) │ Auto-instrumentation     │
└────────────────────────────────────────────────────────────────┘
```

### B. Sample OTel Collector Configuration

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
  hostmetrics:
    collection_interval: 15s
    scrapers:
      cpu:
      memory:
      disk:
      network:
      filesystem:

processors:
  batch:
    timeout: 10s
    send_batch_size: 10000
  memory_limiter:
    check_interval: 1s
    limit_mib: 1000
    spike_limit_mib: 200

exporters:
  prometheusremotewrite:
    endpoint: http://mimir:9009/api/v1/push
  loki:
    endpoint: http://loki:3100/loki/api/v1/push
  otlp:
    endpoint: tempo:4317
    tls:
      insecure: true

service:
  pipelines:
    metrics:
      receivers: [otlp, hostmetrics]
      processors: [memory_limiter, batch]
      exporters: [prometheusremotewrite]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [loki]
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [otlp]
```

### C. Key Links & Resources

| Resource | URL |
|----------|-----|
| OpenTelemetry | https://opentelemetry.io |
| Grafana | https://grafana.com/oss |
| Grafana Mimir | https://grafana.com/oss/mimir |
| Grafana Loki | https://grafana.com/oss/loki |
| Grafana Tempo | https://grafana.com/oss/tempo |
| Prometheus | https://prometheus.io |
| CNCF Landscape | https://landscape.cncf.io/card-mode?category=observability-and-analysis |

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | Feb 2026 | Product & Engineering | Initial PRD for PoC |

---

*This document is a living artifact and should be updated as the PoC progresses.*
