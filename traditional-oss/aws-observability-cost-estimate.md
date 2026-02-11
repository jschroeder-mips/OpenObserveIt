# AWS Observability Stack Cost Estimate
**For: 50 Hosts/Applications**  
**Date:** 2024  
**Region Baseline:** US-East-1 (N. Virginia)

---

## Executive Summary

| Scenario | Monthly Cost | Annual Cost |
|----------|-------------|-------------|
| **Low (Basic)** | **$850 - $1,100** | **$10,200 - $13,200** |
| **Medium (Production)** | **$1,800 - $2,400** | **$21,600 - $28,800** |
| **High (Enterprise)** | **$3,500 - $4,500** | **$42,000 - $54,000** |

**Comparison**: Datadog/New Relic for 50 hosts = **$3,000 - $15,000/month** (depending on features)

---

## 1. DATA VOLUME ASSUMPTIONS

### Metrics (Prometheus/Mimir)
- **50 hosts** × 100 time series/host = 5,000 active time series
- Scrape interval: 15 seconds = 4 samples/minute
- Data per sample: ~12 bytes (timestamp + value + labels)
- **Daily ingestion**: 5,000 × 4 × 60 × 24 × 12 bytes = **~34 GB/day**
- **Monthly ingestion**: **~1 TB/month**
- Retention: 15 days (local), 13 months (S3)

### Logs (Loki)
- **50 hosts** × 1,000 log lines/minute/host = 50,000 lines/min
- Average log line: 200 bytes
- **Daily ingestion**: 50,000 × 60 × 24 × 200 bytes = **~14 GB/day**
- **Monthly ingestion**: **~420 GB/month**
- Retention: 30 days (local), 13 months (S3)

### Traces (Tempo)
- **50 hosts** × 100 traces/minute = 5,000 traces/min
- Average trace: 5 spans × 2 KB/span = 10 KB/trace
- **Daily ingestion**: 5,000 × 60 × 24 × 10 KB = **~7 GB/day**
- **Monthly ingestion**: **~210 GB/month**
- Retention: 7 days (local), 3 months (S3)

---

## 2. COST BREAKDOWN BY SCENARIO

---

## SCENARIO 1: LOW/BASIC (Small Production)
**Target**: Startups, small teams, development environments

### Compute (EC2)

| Component | Instance Type | vCPU | RAM | $/hour | Monthly (730h) | Notes |
|-----------|---------------|------|-----|---------|----------------|-------|
| Grafana | t3.medium | 2 | 4 GB | $0.0416 | $30.37 | UI server |
| Prometheus | t3.xlarge | 4 | 16 GB | $0.1664 | $121.47 | Metrics storage |
| Loki | t3.large | 2 | 8 GB | $0.0832 | $60.74 | Log aggregation |
| Tempo | t3.large | 2 | 8 GB | $0.0832 | $60.74 | Trace storage |
| **Subtotal** | | **10** | **36 GB** | | **$273.32** | Single-AZ |

### Storage (EBS - gp3)

| Component | Volume Size | IOPS | Throughput | $/month | Notes |
|-----------|-------------|------|------------|---------|-------|
| Grafana | 20 GB | 3,000 | 125 MB/s | $1.60 | SQLite DB |
| Prometheus | 200 GB | 3,000 | 125 MB/s | $16.00 | 15 days retention |
| Loki | 300 GB | 3,000 | 125 MB/s | $24.00 | 30 days logs |
| Tempo | 100 GB | 3,000 | 125 MB/s | $8.00 | 7 days traces |
| **Subtotal** | **620 GB** | | | **$49.60** | gp3 = $0.08/GB/month |

### Storage (S3 - Long-term)

| Data Type | Monthly Upload | Total Stored (1 year) | Storage Cost | PUT Requests | GET Requests | Total/Month |
|-----------|----------------|----------------------|--------------|--------------|--------------|-------------|
| Metrics | 1,000 GB | 12 TB | $276.48 | $5.00 | $0.40 | $281.88 |
| Logs | 420 GB | 5 TB | $115.20 | $2.10 | $0.40 | $117.70 |
| Traces | 210 GB (3mo) | 630 GB | $14.49 | $1.05 | $0.20 | $15.74 |
| **Subtotal** | **1,630 GB** | **17.6 TB** | **$406.17** | **$8.15** | **$1.00** | **$415.32** |

*S3 Standard = $0.023/GB/month (first 50 TB)*

### Networking

| Component | Usage | Rate | Monthly Cost | Notes |
|-----------|-------|------|--------------|-------|
| ALB (hours) | 730 hours | $0.0225/hour | $16.43 | Application Load Balancer |
| ALB (LCU) | ~5 LCUs | $0.008/LCU/hour | $29.20 | Load Balancer Capacity Units |
| Data Transfer OUT | 50 GB | $0.09/GB | $4.50 | First 10 TB pricing |
| NAT Gateway | 730 hours | $0.045/hour | $32.85 | For private subnets |
| NAT Data Processing | 100 GB | $0.045/GB | $4.50 | Data processed |
| **Subtotal** | | | **$87.48** | |

### Monitoring & Backups

| Component | Cost | Notes |
|-----------|------|-------|
| CloudWatch Logs | $15.00 | For EC2 logs |
| EBS Snapshots | $20.00 | Daily snapshots (incremental) |
| **Subtotal** | **$35.00** | |

### **TOTAL LOW SCENARIO: $860.72/month**

---

## SCENARIO 2: MEDIUM/PRODUCTION (Standard Production)
**Target**: Growing companies, production workloads, HA setup

### Compute (EC2 - Multi-AZ)

| Component | Instance Type | vCPU | RAM | Instances | $/hour | Monthly | Notes |
|-----------|---------------|------|-----|-----------|---------|---------|-------|
| Grafana | t3.large | 2 | 8 GB | 2 | $0.0832 | $121.47 | HA across 2 AZs |
| Prometheus/Mimir | m5.xlarge | 4 | 16 GB | 3 | $0.192 | $420.48 | Cluster with replication |
| Loki | m5.xlarge | 4 | 16 GB | 2 | $0.192 | $280.32 | Read/Write replicas |
| Tempo | m5.large | 2 | 8 GB | 2 | $0.096 | $140.16 | Distributed setup |
| **Subtotal** | | **36** | **136 GB** | **9** | | **$962.43** | Production-grade |

### Storage (EBS - gp3)

| Component | Volume Size | IOPS | Throughput | $/month | Notes |
|-----------|-------------|------|------------|---------|-------|
| Grafana (2×) | 40 GB | 3,000 | 125 MB/s | $3.20 | PostgreSQL RDS instead |
| Prometheus (3×) | 600 GB | 4,000 | 250 MB/s | $49.80 | 15 days, replicated |
| Loki (2×) | 800 GB | 4,000 | 250 MB/s | $67.60 | 30 days logs |
| Tempo (2×) | 300 GB | 3,000 | 125 MB/s | $24.80 | 7 days traces |
| **Subtotal** | **1,740 GB** | | | **$145.40** | Higher IOPS |

### Storage (S3 - Optimized with Lifecycle)

| Data Type | Storage Class | Monthly Upload | Storage Cost | Total/Month | Notes |
|-----------|---------------|----------------|--------------|-------------|-------|
| Metrics | Standard→IA→Glacier | 1,000 GB | $200.00 | $215.00 | Lifecycle after 90 days |
| Logs | Standard→IA | 420 GB | $80.00 | $88.00 | Lifecycle after 30 days |
| Traces | Standard (3mo) | 210 GB | $14.50 | $16.00 | Short retention |
| **Subtotal** | | **1,630 GB** | **$294.50** | **$319.00** | Cost optimized |

### Database (RDS for Grafana)

| Component | Instance | Storage | Monthly Cost | Notes |
|-----------|----------|---------|--------------|-------|
| RDS PostgreSQL | db.t3.medium | 100 GB gp3 | $85.00 | Multi-AZ, automated backups |

### Networking

| Component | Usage | Monthly Cost | Notes |
|-----------|-------|--------------|-------|
| ALB (hours + LCU) | 730 hours, 10 LCUs | $75.00 | Higher traffic |
| Data Transfer OUT | 200 GB | $18.00 | More external queries |
| NAT Gateway (2 AZs) | 1,460 hours | $65.70 | HA across 2 AZs |
| NAT Data Processing | 300 GB | $13.50 | More data movement |
| **Subtotal** | | **$172.20** | |

### Monitoring & Backups

| Component | Cost | Notes |
|-----------|------|-------|
| CloudWatch Logs | $30.00 | More detailed monitoring |
| CloudWatch Metrics | $10.00 | Custom metrics |
| EBS Snapshots | $50.00 | More frequent snapshots |
| S3 Backups | $20.00 | Configuration backups |
| **Subtotal** | **$110.00** | |

### **TOTAL MEDIUM SCENARIO: $1,794.03/month**

---

## SCENARIO 3: HIGH/ENTERPRISE (Large Scale, Full HA)
**Target**: Enterprises, high availability, compliance requirements

### Compute (EKS Cluster)

| Component | Type | Specs | Instances | Monthly Cost | Notes |
|-----------|------|-------|-----------|--------------|-------|
| EKS Control Plane | Managed | N/A | 1 cluster | $73.00 | $0.10/hour |
| Worker Nodes | m5.2xlarge | 8 vCPU, 32 GB | 6 | $1,051.20 | Spot + On-Demand mix |
| Additional Workers | m5.xlarge | 4 vCPU, 16 GB | 3 | $420.48 | For burst capacity |
| **Subtotal** | | **60 vCPU** | **264 GB** | **$1,544.68** | Auto-scaling enabled |

### Storage (EBS - gp3 + io2)

| Component | Volume Size | Type | IOPS | Monthly Cost | Notes |
|-----------|-------------|------|------|--------------|-------|
| Prometheus/Mimir | 1,500 GB | gp3 | 6,000 | $135.00 | High IOPS for queries |
| Loki | 1,200 GB | gp3 | 5,000 | $108.00 | 30 days + buffer |
| Tempo | 500 GB | gp3 | 4,000 | $42.50 | 7 days traces |
| Grafana (RDS) | 200 GB | io2 | 10,000 | $180.00 | High-performance DB |
| **Subtotal** | **3,400 GB** | | | **$465.50** | Performance-optimized |

### Storage (S3 - Multi-region with Intelligent-Tiering)

| Data Type | Storage Strategy | Monthly Upload | Storage Cost | Total/Month | Notes |
|-----------|------------------|----------------|--------------|-------------|-------|
| Metrics | Intelligent-Tiering | 1,000 GB | $150.00 | $165.00 | Auto-optimization |
| Logs | Intelligent-Tiering + Replication | 420 GB | $90.00 | $105.00 | Compliance copy |
| Traces | Standard (3mo) | 210 GB | $15.00 | $17.00 | Short retention |
| **Subtotal** | | **1,630 GB** | **$255.00** | **$287.00** | Enterprise features |

### Database (RDS - Production Grade)

| Component | Instance | Configuration | Monthly Cost | Notes |
|-----------|----------|---------------|--------------|-------|
| RDS PostgreSQL | db.r5.large | Multi-AZ, 200 GB io2 | $350.00 | High-performance, automated failover |

### Networking (Enterprise Scale)

| Component | Usage | Monthly Cost | Notes |
|-----------|-------|--------------|-------|
| ALB (2 ALBs) | 1,460 hours, 20 LCUs | $150.00 | Public + Internal |
| NLB (for internal traffic) | 730 hours | $25.00 | Network Load Balancer |
| Data Transfer OUT | 500 GB | $45.00 | More external access |
| NAT Gateway (3 AZs) | 2,190 hours | $98.55 | Full HA |
| NAT Data Processing | 800 GB | $36.00 | High data movement |
| VPC Endpoints (S3, ECR) | 2,190 hours | $15.00 | Reduce NAT costs |
| **Subtotal** | | **$369.55** | |

### Monitoring & Operations

| Component | Cost | Notes |
|-----------|------|-------|
| CloudWatch Logs | $80.00 | Extensive logging |
| CloudWatch Metrics | $30.00 | Custom + detailed metrics |
| CloudWatch Alarms | $10.00 | 100 alarms |
| EBS Snapshots | $100.00 | Frequent snapshots, compliance |
| S3 Cross-region Replication | $40.00 | DR/compliance |
| AWS Backup | $50.00 | Centralized backup management |
| **Subtotal** | **$310.00** | |

### Security & Compliance

| Component | Cost | Notes |
|-----------|------|-------|
| AWS WAF | $30.00 | Web application firewall |
| AWS Secrets Manager | $10.00 | Credential management |
| KMS Keys | $5.00 | Encryption keys |
| GuardDuty | $15.00 | Threat detection |
| **Subtotal** | **$60.00** | |

### **TOTAL HIGH SCENARIO: $3,386.73/month**

---

## 3. COST COMPARISON: AWS vs COMMERCIAL SAAS

### Commercial Observability Platform Pricing (50 Hosts)

#### Datadog

| Tier | Included Features | Monthly Cost | Annual Cost | Notes |
|------|-------------------|--------------|-------------|-------|
| **Infrastructure Monitoring** | 50 hosts | $900 | $10,800 | Base $15/host + $3/host/month |
| **APM (25 hosts)** | Distributed tracing | $1,875 | $22,500 | $31/host/month for APM |
| **Log Management** | 150 GB ingested/month | $900 | $10,800 | $0.10/GB ingested + $1.70/GB indexed |
| **Indexed Logs** | 45 GB indexed (30% of 150) | $1,530 | $18,360 | $1.70/GB/month |
| **Custom Metrics** | 100 custom metrics | $300 | $3,600 | $0.05/metric |
| **TOTAL (Full Stack)** | | **$5,505/month** | **$66,060/year** | All features |
| **TOTAL (Basic)** | Infrastructure only | **$900/month** | **$10,800/year** | Limited features |

#### New Relic

| Tier | Included Features | Monthly Cost | Annual Cost | Notes |
|------|-------------------|--------------|-------------|-------|
| **Standard** | 100 GB data/month | $99/user | $1,188/user | 5 users = $495/month |
| **Data Ingest** | ~400 GB/month (metrics+logs) | $1,000 | $12,000 | $0.25/GB over 100 GB |
| **Pro (5 users)** | Full platform access | $549/user | $6,588/user | 5 users = $2,745/month |
| **Data Ingest** | 400 GB/month | $1,000 | $12,000 | $0.25/GB over 100 GB |
| **TOTAL (Standard)** | | **$1,495/month** | **$17,940/year** | Limited features |
| **TOTAL (Pro)** | | **$3,745/month** | **$44,940/year** | Full features |

#### Elastic Cloud (Elasticsearch Service)

| Tier | Configuration | Monthly Cost | Annual Cost | Notes |
|------|---------------|--------------|-------------|-------|
| **Hot Tier** | 256 GB RAM, 1 TB storage | $2,400 | $28,800 | Recent data (15 days) |
| **Warm Tier** | 500 GB storage | $400 | $4,800 | Older data (13 months) |
| **Data Transfer** | 100 GB/month | $50 | $600 | Egress charges |
| **TOTAL** | | **$2,850/month** | **$34,200/year** | Logs + metrics |

### Comparison Summary

| Solution | Low End | Mid Range | High End | Notes |
|----------|---------|-----------|----------|-------|
| **AWS Self-Hosted** | $860/mo | $1,800/mo | $3,400/mo | Full control, requires ops team |
| **Datadog** | $900/mo | $3,000/mo | $5,500/mo | Turnkey, limited customization |
| **New Relic** | $1,500/mo | $2,500/mo | $3,750/mo | Per-user + data pricing |
| **Elastic Cloud** | $1,800/mo | $2,850/mo | $4,500/mo | Similar to self-hosted |

### Break-Even Analysis

**AWS Self-Hosted (Medium Scenario): $1,800/month**

**Total Cost of Ownership (TCO)**:
- Infrastructure: $1,800/month
- DevOps Engineer (0.5 FTE): $4,000/month (assumes $96k salary × 0.5)
- **Total TCO: $5,800/month**

**Datadog (Full Stack): $5,505/month**
- No ops overhead
- Faster time to value
- Limited customization

**Break-even point**: Self-hosted makes financial sense when:
1. You already have DevOps/SRE team managing infrastructure
2. Scale exceeds 100+ hosts (commercial pricing scales faster)
3. Data sovereignty or compliance requires on-prem control
4. Custom integrations or data processing required

---

## 4. COST OPTIMIZATION RECOMMENDATIONS

### Immediate Savings (10-30% reduction)

#### 1. Use Spot Instances for Non-Critical Components
**Savings: $200-400/month**
- Run Tempo on Spot Instances (70% discount)
- Use Spot for Prometheus replicas (keep 1 on-demand)
- Loki read replicas on Spot
```
Medium Scenario with Spot:
- 3 m5.xlarge Spot @ $0.058/hour × 730h × 3 = $127 (vs $420)
- Savings: $293/month
```

#### 2. Use S3 Intelligent-Tiering
**Savings: $50-100/month**
- Auto-moves data to cheaper tiers after 30/90/180 days
- Metrics: Standard → IA → Glacier Deep Archive
- Logs: Standard → IA after 30 days
```
Metrics Storage Optimization:
- Month 1-3: S3 Standard ($0.023/GB) = $69/TB
- Month 4-12: S3 IA ($0.0125/GB) = $37.50/TB
- Savings on 10 TB/year: ~$300/year
```

#### 3. Enable EBS gp3 with Lower Baseline IOPS
**Savings: $30-60/month**
- gp3 allows independent IOPS/throughput configuration
- Start with 3,000 IOPS (free tier), increase only if needed
```
Prometheus Volume (200 GB):
- gp2: $20/month (includes 600 IOPS)
- gp3: $16/month (includes 3,000 IOPS)
- Savings: $4/volume × 10 volumes = $40/month
```

#### 4. Use VPC Endpoints for S3
**Savings: $40-80/month**
- Eliminate NAT Gateway costs for S3 traffic
- Free data transfer to S3 via VPC endpoint
```
NAT Gateway Savings:
- Current: 500 GB @ $0.045/GB = $22.50/month
- With VPC Endpoint: $0
- Additional: Gateway hours saved = $32/month
- Total savings: ~$55/month
```

#### 5. Compress Data Before Storage
**Savings: $100-200/month**
- Enable compression in Loki (default: gzip)
- Prometheus uses snappy compression
- Typical compression ratio: 10:1 for logs, 5:1 for metrics
```
Log Storage Savings:
- Uncompressed: 420 GB/month
- Compressed: 42 GB/month (10:1 ratio)
- S3 savings: 378 GB × $0.023 = $8.70/month
- Long-term (1 year): 378 GB × 12 × $0.023 = $104/month
```

### Medium-term Optimizations (30-50% reduction)

#### 6. Implement Aggressive Retention Policies
**Savings: $200-500/month**
```
Conservative → Aggressive:
Metrics: 13 months → 6 months (50% reduction)
Logs: 13 months → 3 months (75% reduction)  
Traces: 3 months → 14 days (85% reduction)

S3 Storage Savings:
- Metrics: 12 TB → 6 TB = $138/month saved
- Logs: 5 TB → 1.25 TB = $86/month saved
- Traces: 630 GB → 90 GB = $12/month saved
Total: $236/month
```

#### 7. Use Reserved Instances (1-year commitment)
**Savings: $300-600/month**
```
Medium Scenario (9 instances):
- On-Demand: $962/month
- 1-year Reserved (No upfront): $625/month
- 3-year Reserved (All upfront): $410/month
Savings: $337-552/month (35-57% off)
```

#### 8. Implement Sampling for Traces
**Savings: $50-100/month**
- Sample 10% of traces (head-based sampling)
- Use tail-based sampling for errors
```
Trace Data Reduction:
- Current: 210 GB/month
- With 10% sampling: 21 GB/month
- Storage savings: $4-5/month (short retention)
- Compute savings (Tempo): $60/month (smaller instance)
Total: ~$65/month
```

#### 9. Use Savings Plans
**Savings: $200-400/month**
- Compute Savings Plans: 1-year commitment
- Applies to EC2, Fargate, Lambda
- More flexible than Reserved Instances
```
$1,000/month commitment:
- On-Demand cost: $1,000
- Savings Plan (1-year): $660/month
- Savings: $340/month (34% off)
```

### Long-term Optimizations (50%+ reduction at scale)

#### 10. Migrate to EKS with Spot + Fargate
**Savings: $400-800/month**
- Use Spot Instances for 80% of workload
- Fargate for bursty workloads (pay-per-use)
- Auto-scaling reduces waste
```
EKS Optimization:
- Current: 9 m5 instances = $962/month
- Optimized: 2 on-demand + 4 spot + Fargate
  - On-demand: $280/month
  - Spot (70% discount): $130/month
  - Fargate (avg): $150/month
- Total: $560/month
Savings: $402/month
```

#### 11. Implement Metrics Aggregation/Downsampling
**Savings: $100-300/month**
- Downsample old metrics to 5-minute resolution
- Aggregate metrics by namespace/service
```
Prometheus Optimization:
- Raw (15s resolution): 1 TB/month
- Downsampled after 7 days (5m resolution): 50 GB/month
- Storage savings over 1 year: ~$180/month
```

#### 12. Use AWS Graviton Instances (ARM)
**Savings: $200-400/month**
- 20% better price-performance vs x86
- Supported by Prometheus, Grafana, Loki, Tempo
```
Instance Migration:
- m5.xlarge: $0.192/hour
- m6g.xlarge (Graviton2): $0.154/hour
- Savings: $0.038/hour × 730h × 5 instances = $139/month
```

#### 13. Multi-tenant Grafana with RBAC
**Savings: Avoids duplicate infrastructure**
- Serve multiple teams from single stack
- Cost per team drops significantly
```
Scaling Economics:
- 50 hosts (1 team): $1,800/month = $36/host
- 200 hosts (4 teams): $3,200/month = $16/host
- 500 hosts (10 teams): $5,500/month = $11/host
```

---

## 5. COST OPTIMIZATION SUMMARY TABLE

| Optimization | Difficulty | Savings/Month | Implementation Time | Risk |
|--------------|-----------|---------------|---------------------|------|
| **Spot Instances** | Medium | $200-400 | 1 week | Medium (availability) |
| **S3 Intelligent-Tiering** | Easy | $50-100 | 1 day | Low |
| **EBS gp3 Migration** | Easy | $30-60 | 1 day | Low |
| **VPC Endpoints** | Easy | $40-80 | 1 day | Low |
| **Data Compression** | Easy | $100-200 | Enabled by default | Low |
| **Aggressive Retention** | Easy | $200-500 | 1 day | Low (data loss) |
| **Reserved Instances** | Easy | $300-600 | 1 day | Low (commitment) |
| **Trace Sampling** | Medium | $50-100 | 1 week | Medium (visibility) |
| **Savings Plans** | Easy | $200-400 | 1 day | Low (commitment) |
| **EKS + Spot + Fargate** | Hard | $400-800 | 1 month | Medium (complexity) |
| **Metrics Downsampling** | Medium | $100-300 | 2 weeks | Low |
| **Graviton Migration** | Medium | $200-400 | 2 weeks | Low (compatibility) |

**Total Potential Savings: $1,870-$3,940/month (50-70% reduction)**

---

## 6. FINAL RECOMMENDATIONS

### For Startups (<50 hosts, <$1M ARR)
**Recommendation: Use Commercial SaaS (Datadog/New Relic Basic)**
- **Cost**: $900-1,500/month
- **Rationale**: Focus on product, not infrastructure. TCO lower when factoring ops time.
- **When to reconsider**: >100 hosts or >$500K/year on observability

### For Growth Stage (50-200 hosts, $1-10M ARR)
**Recommendation: AWS Self-Hosted (Medium Scenario + Optimizations)**
- **Cost**: $1,200-1,800/month (vs $3,000-5,000 commercial)
- **Rationale**: Cost savings justify 0.5 FTE DevOps time. Customization valuable.
- **Optimizations**: Reserved Instances, Spot, VPC Endpoints, Retention policies
- **ROI**: $36K/year savings vs commercial SaaS

### For Enterprise (200+ hosts, $10M+ ARR)
**Recommendation: AWS Self-Hosted on EKS (High Scenario + All Optimizations)**
- **Cost**: $2,500-3,500/month (vs $10,000-15,000 commercial at 200 hosts)
- **Rationale**: Massive savings at scale. Team already has expertise.
- **Optimizations**: All optimizations, multi-tenancy, Graviton, aggressive tuning
- **ROI**: $100K+/year savings vs commercial SaaS

### Break-Even Analysis by Host Count

| Hosts | AWS Self-Hosted | Datadog Full Stack | Savings/Year |
|-------|----------------|-------------------|--------------|
| 50 | $1,800/mo | $5,500/mo | $44,400 |
| 100 | $2,800/mo | $11,000/mo | $98,400 |
| 200 | $3,500/mo | $22,000/mo | $222,000 |
| 500 | $6,000/mo | $55,000/mo | $588,000 |

**Self-hosted becomes significantly more cost-effective at scale.**

---

## 7. HIDDEN COSTS TO CONSIDER

### AWS Self-Hosted (Often Overlooked)

| Cost Category | Annual Cost | Notes |
|---------------|-------------|-------|
| **DevOps/SRE Time** | $48,000 - $96,000 | 0.5-1.0 FTE for operations |
| **Upgrade/Patching** | $12,000 | Security patches, version upgrades |
| **Incident Response** | $6,000 | Observability platform downtime |
| **Training** | $3,000 | Team learning Prometheus/Grafana |
| **Backup/DR Testing** | $4,000 | Quarterly DR drills |
| **Total Hidden Costs** | **$73,000 - $121,000/year** | **$6,000-10,000/month** |

### Commercial SaaS (Often Overlooked)

| Cost Category | Annual Cost | Notes |
|---------------|-------------|-------|
| **Data Overage Charges** | $6,000 - $12,000 | 20-40% above plan |
| **Additional Users** | $12,000 | More team members need access |
| **Custom Metrics** | $3,600 | Beyond included quota |
| **Support Plan (Enterprise)** | $15,000 | Required for SLA |
| **Integration Development** | $8,000 | Custom dashboards, alerts |
| **Total Hidden Costs** | **$44,600 - $50,600/year** | **$3,700-4,200/month** |

### True Total Cost of Ownership (TCO)

| Solution | Infrastructure | Hidden Costs | Total TCO/Month |
|----------|----------------|--------------|-----------------|
| **AWS Self-Hosted (Medium)** | $1,800 | $6,000 | $7,800 |
| **Datadog (Full Stack)** | $5,500 | $3,700 | $9,200 |
| **New Relic (Pro)** | $3,750 | $3,700 | $7,450 |

**When factoring in all costs, the gap narrows significantly.**

---

## 8. DECISION MATRIX

### Choose AWS Self-Hosted If:
✅ You have >100 hosts (cost savings justify ops overhead)  
✅ DevOps/SRE team with capacity (or can hire 0.5-1 FTE)  
✅ Require custom data processing or integrations  
✅ Data sovereignty/compliance requires on-prem control  
✅ Engineering team proficient in Prometheus/Grafana  
✅ Predictable, steady-state workload (not bursty)  

### Choose Commercial SaaS If:
✅ You have <50 hosts (ops overhead not justified)  
✅ Small/no DevOps team (want turnkey solution)  
✅ Rapid time to value critical (weeks vs months)  
✅ Prefer opex vs capex model  
✅ Want vendor support and SLAs  
✅ Team unfamiliar with observability infrastructure  

### Hybrid Approach:
Consider using **AWS self-hosted for metrics/logs** (bulk of data) and **commercial SaaS for APM/RUM** (specialized features).

**Example Hybrid Cost**:
- AWS self-hosted (metrics + logs): $1,200/month
- Datadog APM only (25 hosts): $775/month
- **Total: $1,975/month** (vs $5,500 full Datadog)

---

## APPENDIX: AWS PRICING REFERENCES (2024)

### EC2 On-Demand Pricing (us-east-1)
- t3.medium: $0.0416/hour
- t3.large: $0.0832/hour
- t3.xlarge: $0.1664/hour
- m5.large: $0.096/hour
- m5.xlarge: $0.192/hour
- m5.2xlarge: $0.384/hour

### EBS Pricing
- gp3: $0.08/GB/month (3,000 IOPS, 125 MB/s included)
- gp2: $0.10/GB/month (3 IOPS/GB)
- io2: $0.125/GB/month + $0.065/IOPS

### S3 Pricing
- Standard: $0.023/GB/month (first 50 TB)
- Intelligent-Tiering: $0.023/GB (Frequent) + $0.0125/GB (Infrequent)
- Standard-IA: $0.0125/GB/month
- Glacier: $0.004/GB/month
- PUT requests: $0.005/1,000
- GET requests: $0.0004/1,000

### Networking
- ALB: $0.0225/hour + $0.008/LCU-hour
- NLB: $0.0225/hour + $0.006/NLCU-hour
- NAT Gateway: $0.045/hour + $0.045/GB processed
- Data Transfer OUT (internet): $0.09/GB (first 10 TB)

---

## CONCLUSION

**For 50 hosts, the medium scenario ($1,800/month) provides the best balance of cost, reliability, and performance.**

**Key Takeaways**:
1. Self-hosted AWS is **2-3x cheaper** than commercial SaaS at infrastructure level
2. When including ops overhead, TCO gap narrows to **20-40%**
3. Savings increase dramatically at scale (>100 hosts)
4. Cost optimizations can reduce infrastructure costs by **50-70%**
5. Hybrid approaches offer middle ground (self-hosted + SaaS for specialized needs)

**Next Steps**:
1. Pilot with **Low Scenario** for 30 days (~$900)
2. Measure actual data volumes and adjust forecasts
3. Implement quick wins (VPC endpoints, gp3, compression)
4. Scale to **Medium Scenario** with Reserved Instances
5. Re-evaluate at 100 hosts for further optimization

**Budget Planning**:
- **Year 1**: $1,800/month × 12 = **$21,600** (medium scenario)
- **Year 2**: $1,200/month × 12 = **$14,400** (with optimizations + RIs)
- **Year 3**: $900/month × 12 = **$10,800** (mature, optimized)

Total 3-Year TCO: **$46,800** vs **$198,000** (Datadog) = **$151,200 savings**
