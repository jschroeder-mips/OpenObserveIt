# Copilot Instructions for OpenObserveIt

This repository contains documentation and infrastructure-as-code for an open-source observability platform on AWS using the LGTM stack (Loki, Grafana, Tempo, Mimir/Prometheus+Thanos).

## Repository Structure

The repository is organized into three main directories:

- **`traditional-oss/`** - Traditional open-source stack (LGTM) with manual operations
- **`ai-first/`** - AI-powered observability with Claude/Bedrock agents for autonomous incident response
- **`shared/`** - Comparison docs, decision matrices, and implementation checklists

## Architecture Overview

### Traditional OSS Stack (`traditional-oss/`)
- **Metrics**: Prometheus → Thanos → S3
- **Logs**: Promtail → Grafana Loki → S3
- **Traces**: OpenTelemetry Collector → Grafana Tempo → S3
- **RUM**: Grafana Faro
- **UI**: Grafana (single pane of glass)

### AI-First Stack (`ai-first/`)
Extends the traditional stack with 6 AI agents:
1. **Sentinel** - Continuous monitoring (Haiku)
2. **Triage** - Alert classification (Haiku/Sonnet)
3. **First Responder** - Auto-remediation (Sonnet)
4. **Investigator** - Root cause analysis (Sonnet)
5. **Communicator** - Slack/PagerDuty integration (Haiku)
6. **On-Call Coordinator** - Escalation management (Sonnet)

## Key Files

| File | Purpose |
|------|---------|
| `MASTER_INDEX.md` | Complete navigation guide - start here |
| `shared/START_HERE.md` | Role-based quick navigation |
| `traditional-oss/ARCHITECTURE.md` | Complete technical architecture (30+ pages) |
| `traditional-oss/terraform-example.tf` | AWS infrastructure as code |
| `traditional-oss/configs-*.yml` | Production-ready configurations |
| `ai-first/AI-AGENT-ARCHITECTURE.md` | AI agent specifications |
| `ai-first/AI-INCIDENT-RESPONSE-WORKFLOWS.md` | Automated incident workflows |

## Conventions

### Configuration Files
- Prometheus/Thanos configs use YAML with extensive comments explaining each setting
- Alert rules follow the pattern: `severity`, `team`, and `playbook_url` labels
- Recording rules optimize query performance for common PromQL patterns

### Terraform
- Resources use the `observability-` prefix for naming
- Multi-AZ deployment across 2 availability zones
- IAM roles over access keys for service authentication

### Documentation Style
- Markdown files use emoji prefixes for section headers (📋, 🎯, 💰, etc.)
- Cost estimates include comparison tables against commercial alternatives
- Architecture docs include ASCII diagrams for visual representation

### Query Language Examples
When documenting or creating examples:
- **PromQL** for metrics queries
- **LogQL** for log queries (similar to PromQL)
- **TraceQL** for trace queries

## Target Environment

- **Scale**: 50 hosts/applications (scalable to 1000+)
- **Cloud**: AWS (us-east-1 default)
- **Monthly Cost**: ~$1,200-1,800 (OSS) or ~$2,060 (AI-first)
- **Implementation Time**: 6-8 weeks
