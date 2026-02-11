# ObserveIt AI - Quick Start Guide
## Get AI-First Observability Running in 2 Hours

---

## Prerequisites

- [ ] AWS Account with admin access
- [ ] 50 hosts to monitor (or start with 5-10 for PoC)
- [ ] Anthropic API key (Claude) OR AWS Bedrock access
- [ ] Slack workspace (for notifications)
- [ ] Terraform installed locally
- [ ] kubectl configured (if using Kubernetes)

---

## Phase 1: Deploy LGTM Stack (30 minutes)

### Option A: Docker Compose (Fastest for PoC)

```bash
# Clone the starter repo
git clone https://github.com/observeit/lgtm-stack-starter
cd lgtm-stack-starter

# Configure
cp .env.example .env
# Edit .env with your settings

# Launch
docker-compose up -d

# Verify
curl http://localhost:3000  # Grafana
curl http://localhost:9009/ready  # Mimir
curl http://localhost:3100/ready  # Loki
curl http://localhost:3200/ready  # Tempo
```

### Option B: Terraform on AWS (Production)

```hcl
# main.tf
module "observeit_lgtm" {
  source = "github.com/observeit/terraform-aws-lgtm"
  
  environment = "production"
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids
  
  # Sizing for 50 hosts
  grafana_instance_type = "t3.medium"
  mimir_instance_type   = "m5.large"
  loki_instance_type    = "m5.large"
  tempo_instance_type   = "m5.large"
  
  # Storage
  s3_bucket_prefix = "observeit-${var.environment}"
  retention_days   = 30
  
  # Access
  grafana_admin_password = var.grafana_password
  allowed_cidr_blocks    = ["10.0.0.0/8"]
}
```

```bash
terraform init
terraform plan
terraform apply
```

---

## Phase 2: Deploy OTel Agents to Hosts (20 minutes)

### Install OpenTelemetry Collector on Each Host

```bash
# Install script (run on each host)
curl -sSL https://observeit.dev/install-agent.sh | bash -s -- \
  --endpoint https://otel-gateway.yourdomain.com:4317 \
  --environment production \
  --service-name $(hostname)
```

### Agent Configuration

```yaml
# /etc/otel-collector/config.yaml
receivers:
  hostmetrics:
    collection_interval: 15s
    scrapers:
      cpu:
      memory:
      disk:
      network:
      filesystem:
  
  filelog:
    include: [/var/log/**/*.log]
    
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317

processors:
  batch:
    timeout: 10s
  resourcedetection:
    detectors: [ec2, system]
  memory_limiter:
    limit_mib: 500

exporters:
  otlphttp:
    endpoint: https://otel-gateway.yourdomain.com:4318

service:
  pipelines:
    metrics:
      receivers: [hostmetrics, otlp]
      processors: [resourcedetection, batch]
      exporters: [otlphttp]
    logs:
      receivers: [filelog, otlp]
      processors: [batch]
      exporters: [otlphttp]
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlphttp]
```

---

## Phase 3: Deploy AI Agents (45 minutes)

### Create Agent Service

```bash
# Clone AI agent framework
git clone https://github.com/observeit/ai-agents
cd ai-agents

# Install dependencies
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Configure
cp config.example.yaml config.yaml
```

### Configure AI Agents

```yaml
# config.yaml
llm:
  provider: anthropic  # or 'bedrock'
  model: claude-3-haiku-20240307  # Fast/cheap for most tasks
  model_complex: claude-3-5-sonnet-20241022  # For investigations
  api_key: ${ANTHROPIC_API_KEY}

observability:
  grafana_url: https://grafana.yourdomain.com
  mimir_url: https://mimir.yourdomain.com
  loki_url: https://loki.yourdomain.com
  tempo_url: https://tempo.yourdomain.com
  grafana_api_key: ${GRAFANA_API_KEY}

integrations:
  slack:
    webhook_url: ${SLACK_WEBHOOK}
    channel: "#ops-alerts"
  pagerduty:
    api_key: ${PAGERDUTY_API_KEY}
    service_id: ${PAGERDUTY_SERVICE_ID}

agents:
  sentinel:
    enabled: true
    check_interval_seconds: 60
    
  triage:
    enabled: true
    severity_thresholds:
      p1: ["revenue_impact", "data_loss", "security"]
      p2: ["user_facing_error", "latency_spike"]
      p3: ["internal_error", "disk_warning"]
      p4: ["info", "optimization"]
      
  first_responder:
    enabled: true
    max_actions_per_hour: 10
    allowed_actions:
      - restart_pod
      - scale_up
      - clear_cache
      - rotate_logs
    require_approval:
      - scale_down
      - terminate
      
  investigator:
    enabled: true
    max_investigations_per_hour: 5
    
  communicator:
    enabled: true
    
  coordinator:
    enabled: true
    escalation_timeout_minutes: 10

runbooks:
  path: ./runbooks/
  auto_update: true
```

### Start Agents

```bash
# Start all agents
python -m observeit.agents.main --config config.yaml

# Or as systemd service
sudo cp observeit-agents.service /etc/systemd/system/
sudo systemctl enable observeit-agents
sudo systemctl start observeit-agents
```

---

## Phase 4: Create Initial Runbooks (15 minutes)

### Runbook: High CPU

```yaml
# runbooks/high-cpu.yaml
name: High CPU Usage
triggers:
  - alertname: HighCPU
  - alertname: CPUThrottling

severity_rules:
  - condition: cpu_usage > 95
    severity: P2
  - condition: cpu_usage > 85
    severity: P3
  - condition: cpu_usage > 75
    severity: P4

investigation_steps:
  - name: Check top processes
    command: ps aux --sort=-%cpu | head -20
    
  - name: Check for runaway processes
    command: ps -eo pid,ppid,%cpu,cmd --sort=-%cpu | awk '$3>50'

remediation_steps:
  - name: Restart high-CPU service
    condition: known_service_causing_issue
    command: systemctl restart {{ service_name }}
    safe: true
    
  - name: Scale horizontally
    condition: all_replicas_high_cpu
    command: kubectl scale deployment/{{ deployment }} --replicas={{ current + 2 }}
    safe: true

verification:
  - command: top -bn1 | head -5
    success_criteria: cpu_usage < 80
```

### Runbook: Disk Space

```yaml
# runbooks/disk-space.yaml
name: Disk Space Warning
triggers:
  - alertname: DiskSpaceWarning
  - alertname: DiskSpaceCritical

severity_rules:
  - condition: disk_usage > 98
    severity: P1
  - condition: disk_usage > 95
    severity: P2
  - condition: disk_usage > 90
    severity: P3

investigation_steps:
  - name: Check disk usage
    command: df -h
    
  - name: Find large files
    command: du -sh /var/log/* | sort -rh | head -10

remediation_steps:
  - name: Rotate logs
    command: logrotate -f /etc/logrotate.d/*
    safe: true
    
  - name: Clear apt cache
    command: apt-get clean
    safe: true
    
  - name: Clear Docker
    command: docker system prune -f --volumes
    safe: true
    requires_confirmation: true

verification:
  - command: df -h | grep {{ mount_point }}
    success_criteria: usage < 85
```

---

## Phase 5: Verify Everything Works (10 minutes)

### Test Sentinel Detection

```bash
# Simulate CPU spike
stress-ng --cpu 4 --timeout 60s

# Watch AI detect it
tail -f /var/log/observeit/agents.log
```

### Test Auto-Remediation

```bash
# Create disk pressure
dd if=/dev/zero of=/tmp/bigfile bs=1M count=5000

# Watch AI clean it up
tail -f /var/log/observeit/agents.log
```

### Verify Slack Notifications

You should see messages like:
```
🟡 INCIDENT DETECTED - P3
━━━━━━━━━━━━━━━━━━━━━━━━
📍 Host: web-server-01
🔧 Issue: Disk usage at 92%
🤖 Status: Auto-remediating...
```

---

## What Happens Next

### Day 1-7: Shadow Mode
- AI classifies all alerts but only notifies
- No automatic actions taken
- Review AI decisions for accuracy

### Day 8-14: Safe Actions Only
- Enable restart, scale-up, log rotation
- Human review of all actions
- Build confidence in AI judgment

### Day 15-30: Full Autonomy
- AI handles P3/P4 independently
- Human approval for P2 actions
- P1 always escalates

### Day 30+: Continuous Learning
- AI suggests runbook updates
- Reduce false positives
- Expand safe action list

---

## Troubleshooting

### AI Not Detecting Alerts
```bash
# Check Grafana alerts are firing
curl -s http://grafana:3000/api/alerts | jq .

# Check agent connectivity
curl -s http://localhost:8080/health

# View agent logs
tail -f /var/log/observeit/sentinel.log
```

### High AI Costs
```bash
# Check token usage
observeit-cli usage --last 24h

# Switch to more Haiku
# Edit config.yaml: model: claude-3-haiku
```

### AI Taking Wrong Actions
```bash
# Disable first responder temporarily
observeit-cli agent disable first_responder

# Review action log
observeit-cli actions --last 50

# Adjust runbooks or safe action list
```

---

## Quick Reference

| Task | Command |
|------|---------|
| View agent status | `observeit-cli status` |
| View recent incidents | `observeit-cli incidents --last 24h` |
| View AI actions | `observeit-cli actions --last 50` |
| Check token usage | `observeit-cli usage --last 7d` |
| Disable an agent | `observeit-cli agent disable <name>` |
| Force escalation | `observeit-cli escalate <incident-id>` |
| Add runbook | `observeit-cli runbook add <file.yaml>` |

---

## Cost Monitoring

Set up alerts for AI spend:

```yaml
# In config.yaml
cost_alerts:
  daily_limit_usd: 10
  monthly_limit_usd: 300
  alert_at_percent: [50, 80, 100]
```

---

## Support

- 📖 Full docs: https://docs.observeit.dev
- 💬 Discord: https://discord.gg/observeit
- 🐛 Issues: https://github.com/observeit/ai-agents/issues

---

*You now have a 24/7 AI SRE teammate. Sleep well.* 🌙
