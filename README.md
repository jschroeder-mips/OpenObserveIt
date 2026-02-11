# OpenObserveIt

[![GitHub](https://img.shields.io/badge/GitHub-jschroeder--mips%2FOpenObserveIt-blue?logo=github)](https://github.com/jschroeder-mips/OpenObserveIt)

Production-ready observability platform architecture for AWS using open-source tooling.

## Overview

This repository provides complete documentation, infrastructure-as-code, and configuration templates for deploying an enterprise-grade observability platform. Choose between two approaches:

| Approach | Monthly Cost | Automation | Best For |
|----------|--------------|------------|----------|
| **[Traditional OSS](traditional-oss/)** | $1,800 | Manual on-call | Teams with dedicated SRE staff |
| **[AI-First](ai-first/)** ⭐ | $2,060 | 80% autonomous | Small teams, reduced on-call burden |

Both approaches are **60-70% cheaper** than commercial alternatives (Datadog, New Relic).

## Quick Start

| Your Role | Start Here |
|-----------|------------|
| **Executive/Manager** | [MASTER_INDEX.md](MASTER_INDEX.md) → Cost comparison and decision matrix |
| **Infrastructure Engineer** | [traditional-oss/terraform-example.tf](traditional-oss/terraform-example.tf) → Deploy infrastructure |
| **DevOps/SRE** | [traditional-oss/configs-*.yml](traditional-oss/) → Configuration templates |
| **Architect** | [traditional-oss/ARCHITECTURE.md](traditional-oss/ARCHITECTURE.md) → Full technical design |

## Repository Structure

```
OpenObserveIt/
├── traditional-oss/          # Open source stack (Prometheus, Loki, Tempo, Grafana)
│   ├── ARCHITECTURE.md       # Complete technical architecture
│   ├── terraform-example.tf  # AWS infrastructure as code
│   └── configs-*.yml         # Production-ready configurations
│
├── ai-first/                 # AI-powered observability with Claude/Bedrock agents
│   ├── AI-AGENT-ARCHITECTURE.md
│   └── AI-INCIDENT-RESPONSE-WORKFLOWS.md
│
└── shared/                   # Comparison docs and implementation checklists
    ├── COST_COMPARISON_OSS_vs_AI.md
    └── DECISION_MATRIX.md
```

## Technology Stack

- **Metrics:** Prometheus + Thanos → S3 (long-term storage)
- **Logs:** Promtail → Grafana Loki → S3
- **Traces:** OpenTelemetry → Grafana Tempo → S3
- **RUM:** Grafana Faro
- **Visualization:** Grafana (unified dashboard)

## Key Metrics

| Metric | Value |
|--------|-------|
| Target Scale | 50 hosts (scalable to 1000+) |
| Implementation Time | 6-8 weeks |
| Monthly Infrastructure | ~$1,200-1,800 |
| vs. Datadog | 67% cheaper |
| vs. New Relic | 55% cheaper |

## Implementation Phases

1. **Phase 1 (Week 1-2):** Core infrastructure - Prometheus, Thanos, Grafana
2. **Phase 2 (Week 3-4):** Log aggregation - Loki, Promtail  
3. **Phase 3 (Week 5-6):** Distributed tracing - Tempo, OpenTelemetry
4. **Phase 4 (Week 7-8):** RUM, alerting, team training

See [shared/IMPLEMENTATION_CHECKLIST.md](shared/IMPLEMENTATION_CHECKLIST.md) for detailed steps.

## Documentation

| Document | Description |
|----------|-------------|
| [MASTER_INDEX.md](MASTER_INDEX.md) | Complete navigation guide |
| [traditional-oss/ARCHITECTURE.md](traditional-oss/ARCHITECTURE.md) | Technical architecture (30+ pages) |
| [ai-first/AI-AGENT-ARCHITECTURE.md](ai-first/AI-AGENT-ARCHITECTURE.md) | AI agent specifications |
| [shared/DECISION_MATRIX.md](shared/DECISION_MATRIX.md) | Technology trade-off analysis |

## Contributing

1. Test changes in a dev environment
2. Update relevant documentation
3. Follow existing configuration patterns

## License

Architecture and configuration examples provided under MIT License. Individual components (Prometheus, Grafana, etc.) have their own licenses - see [License Details](#license-details) below.

---

### License Details

| Component | License |
|-----------|---------|
| Prometheus | Apache 2.0 |
| Grafana | AGPLv3 / Commercial |
| Loki | AGPLv3 |
| Tempo | AGPLv3 |
| OpenTelemetry | Apache 2.0 |
| Thanos | Apache 2.0 |

---

**Questions?** Open an issue at [github.com/jschroeder-mips/OpenObserveIt](https://github.com/jschroeder-mips/OpenObserveIt/issues)
