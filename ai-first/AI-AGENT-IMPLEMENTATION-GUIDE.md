# AI Agent Implementation Guide
## Practical Code Examples and Infrastructure Setup

**Version:** 1.0  
**Audience:** Platform engineers implementing AI agents  
**Prerequisites:** Python 3.11+, AWS account, Claude API key or Bedrock access

---

## Quick Start: Deploy Your First AI Agent in 30 Minutes

This guide provides production-ready code to deploy the Sentinel Agent as your first AI observability component.

### Architecture Recap

```
┌─────────────────────────────────────────────────────────────┐
│  APPLICATION CODE (Your Python/Node.js services)            │
└─────────────────────────┬───────────────────────────────────┘
                          │ OpenTelemetry instrumentation
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  LGTM STACK (Data Layer)                                    │
│  ├─ Mimir (Metrics via PromQL)                              │
│  ├─ Loki (Logs via LogQL)                                   │
│  ├─ Tempo (Traces via TraceQL)                              │
│  └─ Grafana (Visualization)                                 │
└─────────────────────────┬───────────────────────────────────┘
                          │ HTTP APIs
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  AI AGENT LAYER (This Guide)                                │
│  ├─ Sentinel Agent (Anomaly Detection)     ← START HERE     │
│  ├─ Triage Agent (Alert Classification)                     │
│  ├─ First Responder (Safe Remediation)                      │
│  ├─ Investigator (Root Cause Analysis)                      │
│  ├─ Communicator (Notifications)                            │
│  └─ On-Call Coordinator (Escalation)                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Part 1: Environment Setup

### 1.1 Prerequisites

```bash
# Install dependencies
pip install anthropic boto3 requests pandas prometheus-api-client \
    temporal-python pydantic python-dotenv structlog

# Or use requirements.txt
cat > requirements.txt <<EOF
anthropic==0.21.0
boto3==1.34.0
requests==2.31.0
pandas==2.2.0
prometheus-api-client==0.5.3
temporal-sdk==1.5.0
pydantic==2.6.0
python-dotenv==1.0.1
structlog==24.1.0
psycopg2-binary==2.9.9
redis==5.0.1
EOF

pip install -r requirements.txt
```

### 1.2 Environment Variables

```bash
# .env file
# LLM Configuration
CLAUDE_API_KEY=sk-ant-api03-... # From console.anthropic.com
AWS_REGION=us-east-1
BEDROCK_MODEL_ID=anthropic.claude-3-5-sonnet-20241022-v2:0

# LGTM Stack Endpoints
PROMETHEUS_URL=http://prometheus.company.internal:9090
LOKI_URL=http://loki.company.internal:3100
TEMPO_URL=http://tempo.company.internal:3200
GRAFANA_URL=http://grafana.company.internal:3000
GRAFANA_API_KEY=glsa_... # Create in Grafana UI

# PostgreSQL (Incident Storage)
DATABASE_URL=postgresql://user:pass@localhost:5432/observability

# Redis (Caching & Rate Limiting)
REDIS_URL=redis://localhost:6379/0

# Slack (Notifications)
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
SLACK_BOT_TOKEN=xoxb-...

# PagerDuty (Escalation)
PAGERDUTY_API_KEY=...
PAGERDUTY_SERVICE_ID=...
```

---

## Part 2: Core Agent Framework

### 2.1 Base Agent Class

```python
# agents/base.py
from abc import ABC, abstractmethod
from typing import Dict, List, Optional
import structlog
from anthropic import Anthropic
import boto3
from datetime import datetime
import os

logger = structlog.get_logger()

class BaseAgent(ABC):
    """
    Abstract base class for all AI agents.
    Provides common functionality: LLM access, logging, error handling.
    """
    
    def __init__(
        self,
        agent_name: str,
        llm_backend: str = "claude_api",  # or "bedrock"
        model: str = "claude-3-5-sonnet-20241022",
    ):
        self.agent_name = agent_name
        self.llm_backend = llm_backend
        self.model = model
        self.logger = logger.bind(agent=agent_name)
        
        # Initialize LLM client
        if llm_backend == "claude_api":
            self.client = Anthropic(api_key=os.getenv("CLAUDE_API_KEY"))
        elif llm_backend == "bedrock":
            self.client = boto3.client("bedrock-runtime", region_name=os.getenv("AWS_REGION"))
        else:
            raise ValueError(f"Unknown LLM backend: {llm_backend}")
    
    def call_llm(
        self,
        system_prompt: str,
        user_prompt: str,
        max_tokens: int = 4096,
        temperature: float = 0.0,
    ) -> Dict:
        """
        Call LLM with structured prompt.
        Returns parsed JSON response.
        """
        start_time = datetime.utcnow()
        
        try:
            if self.llm_backend == "claude_api":
                response = self.client.messages.create(
                    model=self.model,
                    max_tokens=max_tokens,
                    temperature=temperature,
                    system=system_prompt,
                    messages=[{"role": "user", "content": user_prompt}],
                )
                
                content = response.content[0].text
                tokens_used = response.usage.input_tokens + response.usage.output_tokens
                
            elif self.llm_backend == "bedrock":
                # Bedrock requires different request format
                import json
                request_body = json.dumps({
                    "anthropic_version": "bedrock-2023-05-31",
                    "max_tokens": max_tokens,
                    "system": system_prompt,
                    "messages": [{"role": "user", "content": user_prompt}],
                    "temperature": temperature,
                })
                
                response = self.client.invoke_model(
                    modelId=os.getenv("BEDROCK_MODEL_ID"),
                    body=request_body,
                )
                
                response_body = json.loads(response["body"].read())
                content = response_body["content"][0]["text"]
                tokens_used = response_body["usage"]["input_tokens"] + response_body["usage"]["output_tokens"]
            
            # Log metrics
            duration_ms = (datetime.utcnow() - start_time).total_seconds() * 1000
            self.logger.info(
                "llm_call_success",
                model=self.model,
                tokens=tokens_used,
                duration_ms=duration_ms,
            )
            
            # Parse JSON from response (Claude typically wraps in ```json```)
            import re
            json_match = re.search(r'```json\n(.*?)\n```', content, re.DOTALL)
            if json_match:
                import json
                return json.loads(json_match.group(1))
            else:
                # Try parsing whole response as JSON
                return json.loads(content)
                
        except Exception as e:
            self.logger.error("llm_call_failed", error=str(e))
            raise
    
    @abstractmethod
    def process(self, input_data: Dict) -> Dict:
        """
        Main processing logic for the agent.
        Must be implemented by subclasses.
        """
        pass
    
    def log_action(self, action_type: str, details: Dict):
        """Log agent actions for audit trail"""
        self.logger.info(
            "agent_action",
            action=action_type,
            details=details,
            timestamp=datetime.utcnow().isoformat(),
        )
```

### 2.2 Data Connector Classes

```python
# connectors/prometheus.py
from prometheus_api_client import PrometheusConnect
from typing import List, Dict
import pandas as pd
from datetime import datetime, timedelta

class PrometheusConnector:
    """Interface to Mimir/Prometheus for metrics queries"""
    
    def __init__(self, url: str):
        self.client = PrometheusConnect(url=url, disable_ssl=True)
    
    def query_metric(
        self,
        promql: str,
        time_range_minutes: int = 60,
    ) -> pd.DataFrame:
        """
        Execute PromQL query and return results as DataFrame.
        
        Example:
            query_metric(
                'rate(http_requests_total[5m])',
                time_range_minutes=60
            )
        """
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(minutes=time_range_minutes)
        
        result = self.client.custom_query_range(
            query=promql,
            start_time=start_time,
            end_time=end_time,
            step='1m',
        )
        
        # Convert to DataFrame for easier manipulation
        rows = []
        for series in result:
            metric = series['metric']
            for timestamp, value in series['values']:
                rows.append({
                    'timestamp': datetime.fromtimestamp(timestamp),
                    'value': float(value),
                    **metric  # Include all labels as columns
                })
        
        return pd.DataFrame(rows)
    
    def get_baseline_stats(
        self,
        promql: str,
        lookback_days: int = 30,
    ) -> Dict:
        """
        Calculate baseline statistics for a metric.
        Returns: mean, std, p50, p95, p99
        """
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(days=lookback_days)
        
        result = self.client.custom_query_range(
            query=promql,
            start_time=start_time,
            end_time=end_time,
            step='5m',  # Sample every 5 minutes
        )
        
        # Aggregate all values
        values = []
        for series in result:
            values.extend([float(v[1]) for v in series['values']])
        
        df = pd.DataFrame({'value': values})
        
        return {
            'mean': df['value'].mean(),
            'std': df['value'].std(),
            'p50': df['value'].quantile(0.50),
            'p95': df['value'].quantile(0.95),
            'p99': df['value'].quantile(0.99),
            'min': df['value'].min(),
            'max': df['value'].max(),
            'sample_count': len(values),
        }
```

```python
# connectors/loki.py
import requests
from typing import List, Dict
from datetime import datetime, timedelta

class LokiConnector:
    """Interface to Loki for log queries"""
    
    def __init__(self, url: str):
        self.url = url.rstrip('/')
    
    def query_logs(
        self,
        logql: str,
        time_range_minutes: int = 60,
        limit: int = 1000,
    ) -> List[Dict]:
        """
        Execute LogQL query and return log lines.
        
        Example:
            query_logs(
                '{service="api"} |= "error" | json',
                time_range_minutes=15
            )
        """
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(minutes=time_range_minutes)
        
        params = {
            'query': logql,
            'start': int(start_time.timestamp() * 1e9),  # Nanoseconds
            'end': int(end_time.timestamp() * 1e9),
            'limit': limit,
        }
        
        response = requests.get(
            f"{self.url}/loki/api/v1/query_range",
            params=params,
            timeout=30,
        )
        response.raise_for_status()
        
        data = response.json()
        
        # Parse log lines
        logs = []
        for stream in data['data']['result']:
            labels = stream['stream']
            for timestamp_ns, line in stream['values']:
                logs.append({
                    'timestamp': datetime.fromtimestamp(int(timestamp_ns) / 1e9),
                    'line': line,
                    'labels': labels,
                })
        
        return logs
    
    def count_errors(
        self,
        service: str,
        time_range_minutes: int = 60,
    ) -> int:
        """Count error-level logs for a service"""
        logql = f'{{service="{service}"}} | json | level="error"'
        logs = self.query_logs(logql, time_range_minutes, limit=5000)
        return len(logs)
```

```python
# connectors/tempo.py
import requests
from typing import List, Dict

class TempoConnector:
    """Interface to Tempo for distributed tracing"""
    
    def __init__(self, url: str):
        self.url = url.rstrip('/')
    
    def get_trace(self, trace_id: str) -> Dict:
        """Fetch complete trace by ID"""
        response = requests.get(
            f"{self.url}/api/traces/{trace_id}",
            timeout=10,
        )
        response.raise_for_status()
        return response.json()
    
    def search_traces(
        self,
        service: str,
        min_duration_ms: int = None,
        tags: Dict[str, str] = None,
        limit: int = 100,
    ) -> List[Dict]:
        """
        Search for traces matching criteria.
        
        Example:
            search_traces(
                service="api-service",
                min_duration_ms=5000,  # Slow traces
                tags={"http.status_code": "500"}
            )
        """
        params = {
            'service': service,
            'limit': limit,
        }
        
        if min_duration_ms:
            params['minDuration'] = f'{min_duration_ms}ms'
        
        if tags:
            for key, value in tags.items():
                params[f'tags.{key}'] = value
        
        response = requests.get(
            f"{self.url}/api/search",
            params=params,
            timeout=30,
        )
        response.raise_for_status()
        return response.json()['traces']
```

---

## Part 3: Sentinel Agent Implementation

### 3.1 Complete Sentinel Agent

```python
# agents/sentinel.py
from agents.base import BaseAgent
from connectors.prometheus import PrometheusConnector
from typing import Dict, List
import os
from datetime import datetime

class SentinelAgent(BaseAgent):
    """
    Sentinel Agent: Detects anomalies before alerts fire.
    
    Monitors key metrics every 30-120 seconds and uses LLM
    to detect patterns that indicate emerging issues.
    """
    
    def __init__(self):
        super().__init__(
            agent_name="sentinel",
            llm_backend="claude_api",  # Use Claude API for low latency
            model="claude-3-5-sonnet-20241022",
        )
        
        self.prometheus = PrometheusConnector(os.getenv("PROMETHEUS_URL"))
        
        # Define services and metrics to monitor
        self.monitoring_config = [
            {
                'service': 'api-service',
                'critical': True,
                'check_interval_seconds': 30,
                'metrics': [
                    'rate(http_requests_total[5m])',
                    'histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))',
                    'rate(http_requests_total{status=~"5.."}[5m])',
                    'process_cpu_seconds_total',
                ],
            },
            {
                'service': 'database',
                'critical': True,
                'check_interval_seconds': 60,
                'metrics': [
                    'pg_stat_database_numbackends',
                    'pg_stat_database_deadlocks',
                    'rate(pg_stat_database_tup_returned[5m])',
                ],
            },
            # Add more services...
        ]
    
    def process(self, service_config: Dict) -> Dict:
        """
        Main entry point: Check one service for anomalies.
        
        Returns:
            {
                'status': 'NORMAL|WATCH|WARNING|CRITICAL',
                'anomalies': List[Dict],
                'recommended_action': str
            }
        """
        service = service_config['service']
        self.logger.info("checking_service", service=service)
        
        # 1. Collect current metrics
        current_metrics = self._collect_metrics(service_config)
        
        # 2. Get baseline statistics
        baseline_stats = self._get_baseline(service, lookback_days=30)
        
        # 3. Detect anomalies using LLM
        analysis = self._analyze_with_llm(
            service=service,
            current_metrics=current_metrics,
            baseline_stats=baseline_stats,
        )
        
        # 4. Take action based on analysis
        if analysis['status'] in ['WARNING', 'CRITICAL']:
            self._create_anomaly_ticket(service, analysis)
        
        return analysis
    
    def _collect_metrics(self, service_config: Dict) -> Dict:
        """Fetch current metric values"""
        metrics_data = {}
        
        for promql in service_config['metrics']:
            try:
                df = self.prometheus.query_metric(
                    promql=promql,
                    time_range_minutes=15,
                )
                
                if not df.empty:
                    # Get most recent value
                    latest = df.sort_values('timestamp').iloc[-1]
                    metrics_data[promql] = {
                        'current_value': latest['value'],
                        'timestamp': latest['timestamp'].isoformat(),
                    }
            except Exception as e:
                self.logger.warning("metric_fetch_failed", query=promql, error=str(e))
        
        return metrics_data
    
    def _get_baseline(self, service: str, lookback_days: int) -> Dict:
        """Calculate baseline statistics for comparison"""
        # For simplicity, we'll use the same PromQL queries
        # In production, you'd cache these in a vector database
        
        # Example: Get baseline for latency
        latency_query = 'histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))'
        
        baseline = self.prometheus.get_baseline_stats(
            promql=latency_query,
            lookback_days=lookback_days,
        )
        
        return baseline
    
    def _analyze_with_llm(
        self,
        service: str,
        current_metrics: Dict,
        baseline_stats: Dict,
    ) -> Dict:
        """Use LLM to detect anomalies"""
        
        system_prompt = """You are a Sentinel Agent monitoring production systems. 
Analyze metrics and detect anomalies that may require investigation.

INSTRUCTIONS:
1. Compare current metrics against baseline statistics
2. Consider time-of-day patterns (traffic is lower at night)
3. Assess severity: NORMAL, WATCH, WARNING, CRITICAL
4. Provide specific anomalies with deviation percentages
5. Be conservative - better to miss than create false positives

OUTPUT FORMAT: Valid JSON only, no markdown
{
  "status": "NORMAL|WATCH|WARNING|CRITICAL",
  "anomalies": [
    {
      "metric": "metric_name",
      "current_value": 123,
      "baseline_value": 100,
      "deviation_pct": 23,
      "confidence": 0.85
    }
  ],
  "reasoning": "Brief explanation",
  "recommended_action": "notify_triage|continue_monitoring|none"
}
"""
        
        user_prompt = f"""SERVICE: {service}
CURRENT TIME: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')} (Hour: {datetime.utcnow().hour})

CURRENT METRICS:
{self._format_metrics(current_metrics)}

BASELINE STATISTICS (last 30 days):
{self._format_baseline(baseline_stats)}

Analyze for anomalies:"""
        
        try:
            response = self.call_llm(
                system_prompt=system_prompt,
                user_prompt=user_prompt,
                max_tokens=2048,
                temperature=0.0,  # Deterministic
            )
            return response
        except Exception as e:
            self.logger.error("llm_analysis_failed", error=str(e))
            # Fallback to conservative response
            return {
                'status': 'UNKNOWN',
                'anomalies': [],
                'reasoning': f'LLM analysis failed: {str(e)}',
                'recommended_action': 'none',
            }
    
    def _format_metrics(self, metrics: Dict) -> str:
        """Format metrics for prompt"""
        lines = []
        for query, data in metrics.items():
            lines.append(f"  {query}: {data['current_value']:.4f}")
        return '\n'.join(lines)
    
    def _format_baseline(self, baseline: Dict) -> str:
        """Format baseline stats for prompt"""
        return f"""  Mean: {baseline.get('mean', 0):.4f}
  Std Dev: {baseline.get('std', 0):.4f}
  P95: {baseline.get('p95', 0):.4f}
  P99: {baseline.get('p99', 0):.4f}"""
    
    def _create_anomaly_ticket(self, service: str, analysis: Dict):
        """Create ticket for Triage Agent"""
        # In production, this would write to a queue or database
        # For now, we'll just log it
        self.log_action(
            action_type="anomaly_detected",
            details={
                'service': service,
                'severity': analysis['status'],
                'anomalies': analysis['anomalies'],
                'timestamp': datetime.utcnow().isoformat(),
            }
        )
        
        # TODO: Write to PostgreSQL incidents table or SQS queue
```

### 3.2 Running the Sentinel Agent

```python
# run_sentinel.py
import os
from dotenv import load_dotenv
from agents.sentinel import SentinelAgent
import time
import structlog

load_dotenv()
structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer()
    ]
)

def main():
    """Run Sentinel Agent in continuous monitoring loop"""
    agent = SentinelAgent()
    
    print("🔍 Sentinel Agent starting...")
    print(f"Monitoring {len(agent.monitoring_config)} services")
    
    while True:
        for service_config in agent.monitoring_config:
            service = service_config['service']
            interval = service_config['check_interval_seconds']
            
            try:
                result = agent.process(service_config)
                
                status = result['status']
                print(f"✓ {service}: {status}")
                
                if status in ['WARNING', 'CRITICAL']:
                    print(f"  ⚠️  Anomaly detected: {result['reasoning']}")
                    
            except Exception as e:
                print(f"✗ {service}: ERROR - {str(e)}")
            
            time.sleep(interval)

if __name__ == "__main__":
    main()
```

### 3.3 Testing the Sentinel Agent

```python
# test_sentinel.py
import unittest
from agents.sentinel import SentinelAgent
from unittest.mock import Mock, patch

class TestSentinelAgent(unittest.TestCase):
    def setUp(self):
        self.agent = SentinelAgent()
    
    @patch('connectors.prometheus.PrometheusConnector.query_metric')
    @patch('connectors.prometheus.PrometheusConnector.get_baseline_stats')
    def test_detects_latency_spike(self, mock_baseline, mock_query):
        """Test that agent detects significant latency increase"""
        
        # Mock baseline: p99 latency normally 450ms
        mock_baseline.return_value = {
            'mean': 300,
            'std': 50,
            'p95': 400,
            'p99': 450,
        }
        
        # Mock current: p99 latency now 850ms (89% increase)
        import pandas as pd
        mock_query.return_value = pd.DataFrame([{
            'timestamp': pd.Timestamp.utcnow(),
            'value': 850.0,
        }])
        
        service_config = {
            'service': 'test-api',
            'metrics': ['histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))'],
        }
        
        result = self.agent.process(service_config)
        
        # Should detect anomaly
        self.assertIn(result['status'], ['WARNING', 'CRITICAL'])
        self.assertGreater(len(result['anomalies']), 0)
    
    def test_handles_missing_data(self):
        """Test agent handles missing metrics gracefully"""
        
        service_config = {
            'service': 'test-api',
            'metrics': ['nonexistent_metric'],
        }
        
        # Should not crash
        result = self.agent.process(service_config)
        self.assertIsNotNone(result)

if __name__ == '__main__':
    unittest.main()
```

---

## Part 4: Deployment to AWS

### 4.1 Dockerfile for Agent

```dockerfile
# Dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy agent code
COPY agents/ ./agents/
COPY connectors/ ./connectors/
COPY run_sentinel.py .

# Run agent
CMD ["python", "run_sentinel.py"]
```

### 4.2 Terraform for ECS Deployment

```hcl
# terraform/ai-agents/sentinel-agent.tf

resource "aws_ecs_task_definition" "sentinel_agent" {
  family                   = "sentinel-agent"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"   # 0.5 vCPU
  memory                   = "1024"  # 1 GB
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.sentinel_agent_role.arn

  container_definitions = jsonencode([
    {
      name  = "sentinel-agent"
      image = "${aws_ecr_repository.agents.repository_url}:sentinel-latest"
      
      environment = [
        { name = "AWS_REGION", value = var.aws_region },
        { name = "PROMETHEUS_URL", value = "http://prometheus.internal:9090" },
        { name = "LOKI_URL", value = "http://loki.internal:3100" },
        { name = "TEMPO_URL", value = "http://tempo.internal:3200" },
      ]
      
      secrets = [
        {
          name      = "CLAUDE_API_KEY"
          valueFrom = aws_secretsmanager_secret.claude_api_key.arn
        },
        {
          name      = "DATABASE_URL"
          valueFrom = aws_secretsmanager_secret.database_url.arn
        },
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/sentinel-agent"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "sentinel_agent" {
  name            = "sentinel-agent"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.sentinel_agent.arn
  desired_count   = 1  # Only need 1 instance
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.sentinel_agent.id]
    assign_public_ip = false
  }
}

# IAM Role for Sentinel Agent
resource "aws_iam_role" "sentinel_agent_role" {
  name = "sentinel-agent-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Allow agent to invoke Bedrock (if using Bedrock instead of Claude API)
resource "aws_iam_role_policy" "sentinel_bedrock_access" {
  name = "bedrock-access"
  role = aws_iam_role.sentinel_agent_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-5-sonnet-*"
      }
    ]
  })
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "sentinel_agent" {
  name              = "/ecs/sentinel-agent"
  retention_in_days = 30
}

# Security Group
resource "aws_security_group" "sentinel_agent" {
  name        = "sentinel-agent-sg"
  description = "Security group for Sentinel Agent"
  vpc_id      = var.vpc_id

  # Allow outbound to Prometheus, Loki, Tempo
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### 4.3 Cost Estimates

```
SENTINEL AGENT INFRASTRUCTURE COSTS (Monthly):

AWS ECS Fargate:
- 1 task × 0.5 vCPU × $0.04048/vCPU-hour × 730 hours = $14.78
- 1 task × 1 GB memory × $0.004445/GB-hour × 730 hours = $3.24
Subtotal: $18.02/month

CloudWatch Logs:
- ~5 GB/month × $0.50/GB = $2.50
- ~500K log events × $0.50/million = $0.25
Subtotal: $2.75/month

LLM Costs (Claude API):
- 28,800 checks/day × 2K tokens input × $3/MTok = $172.80
- 28,800 checks/day × 500 tokens output × $15/MTok = $216.00
Subtotal: $388.80/month

TOTAL: ~$410/month for Sentinel Agent

NOTE: LLM costs dominate. To reduce:
- Use Claude Haiku for low-confidence checks ($0.25/MTok vs $3/MTok)
- Cache baseline data (reduce input tokens)
- Adjust check frequency (30s → 60s cuts cost in half)

Optimized Configuration:
- Use Haiku for initial scan, Sonnet only for suspected anomalies
- Estimated savings: 70% → $117/month LLM costs
- New total: ~$138/month
```

---

## Part 5: Production Checklist

### Before Deploying to Production:

- [ ] **Security**
  - [ ] Claude API key stored in AWS Secrets Manager (not environment variables)
  - [ ] IAM roles follow least-privilege principle
  - [ ] Network security groups restrict access to internal services only
  - [ ] Enable AWS CloudTrail for audit logging

- [ ] **Observability**
  - [ ] CloudWatch metrics for agent health (heartbeat, error rate)
  - [ ] Structured logging (JSON format) for easy search
  - [ ] Dead letter queue for failed LLM calls
  - [ ] Alerting on agent failures (via existing monitoring)

- [ ] **Cost Controls**
  - [ ] Set AWS Budgets alerts (e.g., >$500/month)
  - [ ] Implement LLM call rate limiting (e.g., max 1000 calls/hour)
  - [ ] Monitor token usage per agent (CloudWatch custom metrics)
  - [ ] Cache frequently accessed data (Redis)

- [ ] **Testing**
  - [ ] Unit tests for each agent (>80% coverage)
  - [ ] Integration tests with mock LGTM stack
  - [ ] Load testing (simulate 1000 alerts/hour)
  - [ ] Chaos testing (kill agent, verify recovery)

- [ ] **Operational**
  - [ ] Runbook for agent failures ("What if Sentinel stops detecting?")
  - [ ] Rollback plan (can disable agents without disrupting LGTM stack)
  - [ ] On-call rotation includes "AI Agents" in scope
  - [ ] Documentation for adding new services to monitoring

---

## Next Steps

1. **Deploy Sentinel Agent** (this guide) - 1-2 days
2. **Add Triage Agent** - See `AI-AGENT-TRIAGE-IMPLEMENTATION.md` - 2-3 days
3. **Add First Responder Agent** - Requires approval workflows - 3-5 days
4. **Integrate remaining agents** - 1-2 weeks

**Total Time to Full AI Layer: 3-4 weeks**

---

## Troubleshooting

### Agent not detecting anomalies

```python
# Check metrics are being fetched
python -c "
from connectors.prometheus import PrometheusConnector
import os
from dotenv import load_dotenv

load_dotenv()
prom = PrometheusConnector(os.getenv('PROMETHEUS_URL'))
result = prom.query_metric('up', time_range_minutes=5)
print(result)
"

# Should print DataFrame with 'up' metric values
```

### LLM calls failing

```bash
# Test Claude API directly
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $CLAUDE_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 100,
    "messages": [{"role": "user", "content": "Hello"}]
  }'

# Should return JSON response with "content" field
```

### High costs

```python
# Add cost tracking to BaseAgent
def call_llm(self, ...):
    # ... existing code ...
    
    # Calculate cost
    input_cost = (response.usage.input_tokens / 1_000_000) * 3.00  # $3/MTok
    output_cost = (response.usage.output_tokens / 1_000_000) * 15.00  # $15/MTok
    total_cost = input_cost + output_cost
    
    self.logger.info("llm_cost", cost_usd=total_cost, tokens=tokens_used)
    
    # Emit CloudWatch metric
    cloudwatch = boto3.client('cloudwatch')
    cloudwatch.put_metric_data(
        Namespace='AIAgents',
        MetricData=[{
            'MetricName': 'LLMCost',
            'Value': total_cost,
            'Unit': 'None',
            'Dimensions': [{'Name': 'Agent', 'Value': self.agent_name}]
        }]
    )
```

---

**Ready to deploy!** Start with `run_sentinel.py` locally, then move to ECS when satisfied.
