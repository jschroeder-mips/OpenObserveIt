# AI-First Observability Platform Architecture
## Autonomous AI Agents Layer for LGTM Stack

**Version:** 1.0  
**Last Updated:** 2024  
**Target Scale:** 50 hosts, small engineering team (5-15 engineers)  
**AI Philosophy:** Autonomous triage and safe remediation, human escalation for critical decisions

---

## Executive Summary

This architecture adds an **AI Automation Layer** on top of the existing LGTM stack (Loki, Grafana, Tempo, Mimir), transforming it from a passive monitoring platform into an **autonomous observability system** that detects, triages, investigates, and responds to incidents with minimal human intervention.

### Value Proposition

**For a 50-host environment with a small team:**
- **Reduce MTTR by 60-80%**: AI agents detect issues before humans notice and start investigation immediately
- **Eliminate alert fatigue**: Triage Agent deduplicates and correlates 70-90% of noise
- **24/7 autonomous response**: First Responder handles common issues (pod restarts, scaling) without waking engineers
- **Preserve institutional knowledge**: AI learns from runbooks and past incidents
- **Cost-effective**: ~$500-800/month for AI layer (Claude API/Bedrock) vs $50K+/year for human on-call burden

### Architecture Philosophy

```
┌─────────────────────────────────────────────────────────────┐
│                    AI AUTOMATION LAYER                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │ Sentinel │  │  Triage  │  │   First  │  │Investigator│   │
│  │  Agent   │→ │  Agent   │→ │ Responder│→ │   Agent    │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘    │
│       ↓             ↓              ↓              ↓           │
│  ┌──────────────────────────────────────────────────────┐   │
│  │         Agent Orchestration & Memory Layer           │   │
│  │   (Temporal.io / Conductor + PostgreSQL/DynamoDB)    │   │
│  └──────────────────────────────────────────────────────┘   │
│       ↓             ↓              ↓              ↓           │
└───────┼─────────────┼──────────────┼──────────────┼──────────┘
        │             │              │              │
┌───────┼─────────────┼──────────────┼──────────────┼──────────┐
│                    LGTM DATA LAYER                            │
│    Grafana  │   Mimir    │    Loki     │    Tempo             │
│   (Dashboards)│ (Metrics) │  (Logs)    │  (Traces)            │
└───────────────────────────────────────────────────────────────┘
        ↑             ↑              ↑              ↑
    [Application & Infrastructure Telemetry via OTel]
```

---

## Table of Contents

1. [AI Agent Specifications](#1-ai-agent-specifications)
2. [Claude API vs AWS Bedrock Analysis](#2-claude-api-vs-aws-bedrock-analysis)
3. [AWS Infrastructure Design](#3-aws-infrastructure-design)
4. [Agent Orchestration Architecture](#4-agent-orchestration-architecture)
5. [Memory & Context Management](#5-memory--context-management)
6. [Runbook Integration Strategy](#6-runbook-integration-strategy)
7. [Safety & Guardrails](#7-safety--guardrails)
8. [Implementation Roadmap](#8-implementation-roadmap)
9. [Cost Analysis](#9-cost-analysis)
10. [Operational Runbooks](#10-operational-runbooks)

---

## 1. AI Agent Specifications

### 1.1 Sentinel Agent - "The Watchful Eye"

**Purpose:** Continuously monitors dashboards and metrics to detect anomalies *before* traditional threshold-based alerts fire. Reduces time-to-detection from minutes to seconds.

#### Input Sources
```yaml
Primary:
  - Mimir/Prometheus metrics (via PromQL queries)
  - Grafana dashboard panels (JSON API)
  - Historical baseline data (from vector database)
  
Secondary:
  - Service dependency graph (from Tempo traces)
  - Recent deployment events (from CI/CD webhooks)
  - Past incident patterns (from PostgreSQL incident DB)

Refresh Rate:
  - Critical services: Every 30 seconds
  - Standard services: Every 2 minutes
  - Background jobs: Every 5 minutes
```

#### LLM Capabilities & Prompts

**Model:** Claude 3.5 Sonnet (complex pattern recognition) or Haiku (cost-optimized for simple checks)

**Core Prompt Template:**
```python
SENTINEL_PROMPT = """
You are a Sentinel Agent monitoring production systems. Analyze the following metrics and determine if an anomaly exists that requires investigation.

CONTEXT:
- Service: {service_name}
- Time Range: Last {time_window} minutes
- Normal Baseline: {baseline_stats}

CURRENT METRICS:
{metric_data}

RECENT CHANGES:
{deployment_events}

INSTRUCTIONS:
1. Compare current metrics against baseline (consider time-of-day, day-of-week patterns)
2. Identify any concerning trends even if below alert thresholds
3. Assess severity: NORMAL, WATCH, WARNING, CRITICAL
4. If not NORMAL, provide:
   - Specific metric(s) showing anomaly
   - Deviation percentage from baseline
   - Potential business impact
   - Recommended next action

OUTPUT FORMAT (JSON):
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

Think step-by-step. Be conservative - better to miss an anomaly than create false positives.
"""
```

**Advanced Features:**
- **Time-series pattern recognition**: Detect gradual degradation, cyclical patterns, sudden spikes
- **Contextual awareness**: Factor in deployments, traffic patterns, time-of-day
- **Confidence scoring**: Only escalate when confidence > 80%
- **Multi-metric correlation**: Detect issues spanning CPU + latency + error rate

#### Tools & Actions

```python
class SentinelAgent:
    """Sentinel Agent tool definitions"""
    
    def query_metrics(self, promql: str, time_range: str) -> DataFrame:
        """Query Mimir/Prometheus via HTTP API"""
        
    def fetch_dashboard(self, dashboard_uid: str) -> Dict:
        """Retrieve Grafana dashboard configuration"""
        
    def get_baseline(self, service: str, metric: str, lookback_days: int = 30) -> Stats:
        """Retrieve historical baseline from vector DB (Pinecone/Weaviate)"""
        
    def check_recent_deployments(self, service: str, hours: int = 2) -> List[Event]:
        """Query CI/CD system (GitHub Actions, Argo CD)"""
        
    def create_anomaly_ticket(self, anomaly: Dict) -> str:
        """Create ticket in orchestration system for Triage Agent"""
        
    def store_context(self, incident_id: str, context: Dict) -> None:
        """Store anomaly context in shared memory (PostgreSQL)"""
```

#### Safety Boundaries

**CANNOT DO:**
- ❌ Restart services or modify infrastructure
- ❌ Silence alerts or modify alerting rules
- ❌ Access production databases or secrets
- ❌ Change code or configurations

**CAN DO:**
- ✅ Read metrics, logs, traces (read-only)
- ✅ Create tickets for Triage Agent
- ✅ Store anomaly context
- ✅ Query external APIs (weather, public incident feeds for cloud providers)

#### Handoff Criteria to Humans

**Immediate Human Escalation:**
1. CRITICAL severity + confidence > 95%
2. Multi-service cascading failure detected
3. Security-related anomaly (auth failures, unusual traffic patterns)
4. Agent encounters error or ambiguity

**Handoff to Triage Agent:**
1. WARNING severity + confidence > 80%
2. Single service degradation
3. Known issue pattern detected

**Continue Monitoring:**
1. WATCH severity or confidence < 80%
2. Expected behavior (e.g., batch job spikes)

#### Example Detection Scenario

```
# Scenario: API response time gradually increasing
INPUT METRICS:
- p99_latency: 850ms (baseline: 450ms) → +89% over 15 minutes
- error_rate: 0.8% (baseline: 0.2%) → +300%
- cpu_usage: 65% (baseline: 40%) → +62%
- recent_deployment: "api-v2.3.1" deployed 20 minutes ago

SENTINEL ANALYSIS:
{
  "status": "WARNING",
  "anomalies": [
    {
      "metric": "p99_latency",
      "current_value": 850,
      "baseline_value": 450,
      "deviation_pct": 89,
      "confidence": 0.92
    }
  ],
  "reasoning": "Latency spiking gradually after deployment. CPU increase suggests resource contention. Error rate climbing - likely cascading effect.",
  "recommended_action": "notify_triage",
  "suspected_cause": "Recent deployment api-v2.3.1 may have introduced performance regression"
}

ACTION TAKEN:
→ Create ticket for Triage Agent with full context
→ Tag as "deployment-related"
→ Attach last 30 days of deployment-latency correlation data
```

---

### 1.2 Triage Agent - "The Intelligent Filter"

**Purpose:** Receives alerts from monitoring systems and Sentinel Agent, classifies severity, correlates related issues, and eliminates 70-90% of alert noise through intelligent deduplication.

#### Input Sources

```yaml
Primary:
  - Alertmanager alerts (Prometheus/Mimir)
  - Sentinel Agent anomaly tickets
  - PagerDuty / Opsgenie webhooks (if integrated)
  - Grafana alert notifications
  
Secondary:
  - Active incident timeline (from memory layer)
  - Service dependency graph (Tempo)
  - Recent Triage decisions (for consistency)
  - Runbook database (for known issues)

Trigger Method:
  - Webhook receiver (HTTP POST)
  - Message queue consumer (SQS/SNS)
  - Polling (every 15 seconds for high-priority queues)
```

#### LLM Capabilities & Prompts

**Model:** Claude 3.5 Sonnet (requires reasoning across multiple signals)

**Core Prompt Template:**
```python
TRIAGE_PROMPT = """
You are a Triage Agent responsible for classifying and correlating production alerts. Your goal is to reduce noise and ensure the right issues reach the right people.

INCOMING ALERT:
{alert_data}

CONTEXT:
Active Incidents: {active_incidents}
Recent Alerts (last 10 min): {recent_alerts}
Service Dependencies: {dependency_graph}
Known Issues: {known_issues_from_runbooks}

YOUR TASKS:

1. SEVERITY CLASSIFICATION (Re-assess beyond threshold-based alerts)
   - P0 (Critical): Complete service outage, data loss risk, security breach
   - P1 (High): Significant degradation affecting >20% users
   - P2 (Medium): Partial degradation or impacted feature
   - P3 (Low): Minor issue or warning sign
   - P4 (Info): Informational, no action needed

2. CORRELATION ANALYSIS
   - Is this a NEW incident or related to existing incident #{incident_ids}?
   - Is this a symptom of an upstream dependency failure?
   - Are multiple alerts describing the same root cause?

3. DEDUPLICATION
   - Should this alert be grouped with others?
   - Is this a duplicate of a recently-triaged alert?

4. RECOMMENDED ACTION
   - escalate_to_first_responder: Safe automated remediation possible
   - escalate_to_investigator: Needs RCA but not urgent
   - escalate_to_human: Requires human judgment
   - suppress: Noise / already handled
   - watch: Monitor for 5 minutes before deciding

OUTPUT FORMAT (JSON):
{
  "severity": "P0|P1|P2|P3|P4",
  "is_duplicate": false,
  "related_incident_id": null,
  "correlation": {
    "root_cause_alert": "alert_id or null",
    "symptom_alerts": ["alert_id1", "alert_id2"],
    "affected_services": ["service1", "service2"]
  },
  "recommended_action": "escalate_to_first_responder|escalate_to_investigator|escalate_to_human|suppress|watch",
  "reasoning": "Detailed explanation",
  "suggested_responder": "oncall_backend|oncall_platform|auto",
  "estimated_customer_impact": "Brief description",
  "runbook_match": "runbook_id or null"
}

Be decisive but cautious. When in doubt between severities, escalate.
"""
```

**Example Correlation Logic:**
```python
# Scenario: 15 alerts fire within 2 minutes after database failure
INCOMING ALERTS:
1. database-01: Connection pool exhausted
2. api-service: High latency (p99 > 5s)
3. api-service: Error rate > 5%
4. worker-service: Queue backlog growing
5. api-service: 502 errors increasing
6. frontend: Timeout errors
... (9 more symptom alerts)

TRIAGE ANALYSIS:
{
  "root_incident": {
    "id": "INC-2024-001234",
    "root_cause_alert": "database-01: Connection pool exhausted",
    "severity": "P1",
    "affected_services": ["api-service", "worker-service", "frontend"],
    "symptom_alerts": [2, 3, 4, 5, 6, ...],  // Grouped
    "recommended_action": "escalate_to_first_responder",
    "suggested_remediation": "Scale database connection pool or restart stale connections"
  },
  "suppressed_alerts": 13,  // 14 symptom alerts collapsed into 1 incident
  "reasoning": "Database connection exhaustion is root cause. All downstream services experiencing cascading failure. High confidence (0.94) based on dependency graph and timing."
}
```

#### Tools & Actions

```python
class TriageAgent:
    """Triage Agent tool definitions"""
    
    def query_active_incidents(self) -> List[Incident]:
        """Fetch all active incidents from memory layer"""
        
    def get_service_dependencies(self, service: str) -> DAG:
        """Query service dependency graph from Tempo"""
        
    def search_runbooks(self, alert_pattern: str) -> List[Runbook]:
        """Semantic search in runbook vector database"""
        
    def create_incident(self, alert: Dict) -> str:
        """Create new incident record"""
        
    def link_to_incident(self, alert_id: str, incident_id: str) -> None:
        """Associate alert with existing incident"""
        
    def suppress_alert(self, alert_id: str, reason: str) -> None:
        """Mark alert as suppressed (logged but not escalated)"""
        
    def escalate_to_agent(self, incident: Incident, target: str) -> None:
        """Route incident to First Responder or Investigator"""
        
    def notify_human(self, incident: Incident, channel: str) -> None:
        """Send notification via Communicator Agent"""
        
    def update_incident_context(self, incident_id: str, metadata: Dict) -> None:
        """Append triage decision context to incident timeline"""
```

#### Safety Boundaries

**CANNOT DO:**
- ❌ Take remediation actions (restart, scale, etc.)
- ❌ Silence alerts permanently (only suppress individual occurrences)
- ❌ Modify alert routing rules
- ❌ Downgrade P0/P1 incidents without human confirmation

**CAN DO:**
- ✅ Re-classify severity (but must log reasoning)
- ✅ Group and correlate alerts
- ✅ Suppress duplicate/symptom alerts (with audit log)
- ✅ Route incidents to appropriate responders
- ✅ Create/update incident records

#### Handoff Criteria to Humans

**Immediate Human Escalation:**
1. P0 incidents (always notify on-call)
2. Ambiguous alerts that don't match known patterns
3. Multiple P1 incidents occurring simultaneously (potential widespread issue)
4. Security-related alerts (auth failures, DDoS, data access anomalies)

**Handoff to First Responder Agent:**
1. P1/P2 incidents with matching runbook (safe automation available)
2. Known remediation patterns (e.g., restart pod, scale up)
3. Single-service degradation

**Handoff to Investigator Agent:**
1. P2/P3 incidents requiring RCA but not time-sensitive
2. Novel failure patterns needing deeper analysis
3. Post-incident analysis requests

---

### 1.3 First Responder Agent - "The Safe Remediator"

**Purpose:** Takes **safe, pre-approved remediation actions** to resolve common incidents without human intervention. Operates within strict guardrails to prevent accidental harm.

#### Input Sources

```yaml
Primary:
  - Triaged incidents (from Triage Agent)
  - Matched runbooks (with approved automation flags)
  
Secondary:
  - Current infrastructure state (Kubernetes API, AWS APIs)
  - Recent remediation history (to prevent loops)
  - Blast radius analysis (affected resources)

Trigger Method:
  - Incident routing from Triage Agent
  - Only triggers on incidents with runbook_match + auto_remediation_allowed=true
```

#### LLM Capabilities & Prompts

**Model:** Claude 3.5 Sonnet (requires careful decision-making and safety checks)

**Core Prompt Template:**
```python
FIRST_RESPONDER_PROMPT = """
You are a First Responder Agent with LIMITED PERMISSIONS to take safe remediation actions. Your primary directive is: FIRST, DO NO HARM.

INCIDENT:
{incident_details}

MATCHED RUNBOOK:
{runbook_content}

CURRENT STATE:
{infrastructure_state}

RECENT REMEDIATION HISTORY:
{recent_actions}

YOUR TASKS:

1. VALIDATE RUNBOOK MATCH (Confidence Check)
   - Does this incident truly match the runbook criteria?
   - Are all prerequisites met for automation?
   - Confidence threshold: Must be >90% to proceed

2. SAFETY CHECKS (CRITICAL - MUST ALL PASS)
   - Is this remediation marked as "safe_for_automation: true" in runbook?
   - Have we attempted this remediation <3 times in last 1 hour? (prevent loops)
   - Is the blast radius acceptable? (single pod/instance, not entire cluster)
   - Is this a production-critical window (business hours)? If yes, be more conservative.
   - Are there any ongoing deployments that could interact? (check CI/CD state)

3. SELECT REMEDIATION ACTION (Only from pre-approved list)
   Safe Actions (GREEN ZONE):
   - Restart single pod/container
   - Scale deployment up (within pre-approved limits)
   - Clear message queue / cache
   - Restart connection pool
   - Drain and replace single EC2 instance
   - Toggle feature flag (if specified in runbook)
   
   Forbidden Actions (RED ZONE):
   - Restart entire deployment / all pods
   - Scale down (risk of making issue worse)
   - Database operations (read-only queries OK, writes FORBIDDEN)
   - Network changes (security groups, firewall rules)
   - IAM / permission changes
   - Code or configuration changes

4. DRY RUN (Simulation)
   - Describe exactly what commands would run
   - Estimate blast radius (how many users/requests affected)
   - Predict expected outcome

OUTPUT FORMAT (JSON):
{
  "validation": {
    "runbook_match_confidence": 0.95,
    "prerequisites_met": true,
    "decision": "proceed|abort"
  },
  "safety_checks": {
    "is_safe_for_automation": true,
    "recent_attempt_count": 0,
    "blast_radius": "single_pod",
    "critical_window": false,
    "ongoing_deployment": false,
    "all_checks_passed": true
  },
  "selected_action": {
    "type": "restart_pod",
    "target": "api-service-pod-abc123",
    "commands": ["kubectl delete pod api-service-pod-abc123 -n production"],
    "estimated_downtime": "5-10 seconds (rolling restart)",
    "expected_outcome": "Pod restarts with fresh state, connection pool resets",
    "rollback_plan": "If issue persists after 2 minutes, escalate to human"
  },
  "reasoning": "Detailed explanation of why this action is safe and appropriate",
  "recommended_action": "execute|dry_run_only|escalate_to_human"
}

REMEMBER: If ANY safety check fails, ABORT and escalate to human. Better to wake a human than cause an outage.
"""
```

#### Tools & Actions

```python
class FirstResponderAgent:
    """First Responder Agent tool definitions"""
    
    # READ-ONLY TOOLS
    def get_kubernetes_state(self, namespace: str, resource: str) -> Dict:
        """Query Kubernetes API (read-only)"""
        
    def get_ec2_instance_state(self, instance_id: str) -> Dict:
        """Query AWS EC2 API (describe-instances)"""
        
    def check_deployment_status(self, service: str) -> Dict:
        """Check CI/CD system for active deployments"""
        
    def get_recent_remediations(self, service: str, hours: int = 1) -> List[Action]:
        """Query action history to prevent loops"""
    
    # WRITE TOOLS (LIMITED SCOPE)
    def restart_pod(self, pod_name: str, namespace: str, dry_run: bool = False) -> Result:
        """Delete pod (Kubernetes will recreate). Requires approval token."""
        # Safety: Only single pod, must have replica count > 1
        
    def scale_deployment(self, deployment: str, replicas: int, dry_run: bool = False) -> Result:
        """Scale Kubernetes deployment. Max increase: +50% current, max replicas: 20"""
        # Safety: Only scale UP, never down. Check cost impact.
        
    def clear_cache(self, cache_key_pattern: str, dry_run: bool = False) -> Result:
        """Clear Redis/Memcached keys. Requires exact pattern match."""
        # Safety: Wildcard * must be approved in runbook
        
    def drain_ec2_instance(self, instance_id: str, dry_run: bool = False) -> Result:
        """Drain connections and replace EC2 instance in ASG"""
        # Safety: Only if instance is in ASG with min_size > current_size - 1
        
    def execute_runbook_command(self, command: str, dry_run: bool = False) -> Result:
        """Execute pre-approved command from runbook whitelist"""
        # Safety: Command must be in approved_commands table, signed by human
    
    # AUDIT & LOGGING
    def log_action(self, action: Dict, result: Dict) -> None:
        """Log all actions (success or failure) to audit trail"""
        
    def request_human_approval(self, action: Dict, reason: str) -> str:
        """For borderline cases, request async approval via Slack"""
```

#### Safety Boundaries

**STRICT RESTRICTIONS:**
- ❌ **NEVER** restart entire services (only single pods/instances)
- ❌ **NEVER** scale down (can make incidents worse)
- ❌ **NEVER** modify databases (no writes, no schema changes)
- ❌ **NEVER** change network/security configs
- ❌ **NEVER** touch authentication systems
- ❌ **NEVER** override human decisions
- ❌ **NEVER** act during change freeze windows

**ALLOWED ACTIONS (with constraints):**
- ✅ Restart single pod/container (only if replicas > 1)
- ✅ Scale UP deployment (max +50%, max 20 replicas total)
- ✅ Clear cache (only exact keys or pre-approved patterns)
- ✅ Restart connection pools (app-level, not DB-level)
- ✅ Drain single EC2 instance (only in Auto Scaling Groups)
- ✅ Run pre-approved scripts (must be code-reviewed and signed)

**RATE LIMITS:**
- Max 3 remediation attempts per service per hour (prevent loops)
- Max 5 total actions per hour across all services (circuit breaker)
- If 2 consecutive actions fail, escalate to human immediately

#### Handoff Criteria to Humans

**Immediate Human Escalation:**
1. ANY safety check fails
2. Remediation attempt fails (action executed but issue persists)
3. Uncertainty about runbook match (confidence < 90%)
4. Novel incident pattern (no runbook match)
5. Multiple services affected (potential cascading failure)
6. Rate limit exceeded (too many recent actions)

**Handoff to Investigator Agent:**
1. Remediation succeeds but want post-mortem (P1 incidents)
2. Unusual failure pattern (may indicate deeper issue)

#### Example Remediation Scenario

```
# Scenario: API pod stuck in CrashLoopBackOff

INCIDENT:
- Service: user-api-service
- Alert: Pod restarting continuously (5 restarts in 10 minutes)
- Logs: OutOfMemoryError in pod user-api-7d4f9c-abc123

MATCHED RUNBOOK: "OOM-POD-RESTART"
- Title: "Pod OOM - Restart to Clear Memory Leak"
- Safe for automation: TRUE
- Action: Delete pod, let Kubernetes recreate

FIRST RESPONDER ANALYSIS:
{
  "validation": {
    "runbook_match_confidence": 0.96,
    "prerequisites_met": true,
    "decision": "proceed"
  },
  "safety_checks": {
    "is_safe_for_automation": true,
    "recent_attempt_count": 0,
    "blast_radius": "single_pod (5% of traffic)",
    "replica_count": 3,  // ✅ > 1, safe to delete one
    "critical_window": false,  // 3 AM, low traffic
    "ongoing_deployment": false,
    "all_checks_passed": true
  },
  "selected_action": {
    "type": "restart_pod",
    "target": "user-api-7d4f9c-abc123",
    "commands": ["kubectl delete pod user-api-7d4f9c-abc123 -n production"],
    "estimated_downtime": "0 seconds (other pods handle traffic)",
    "expected_outcome": "Pod recreates with fresh memory, OOM clears",
    "rollback_plan": "If new pod also OOMs within 5 minutes, escalate to human (likely code issue, not transient)"
  },
  "recommended_action": "execute"
}

EXECUTION:
→ Execute: kubectl delete pod user-api-7d4f9c-abc123 -n production
→ Wait 60 seconds for new pod to become Ready
→ Monitor: Check if new pod is healthy (no restarts)

OUTCOME:
✅ New pod running successfully for 5 minutes
✅ No further OOM errors
✅ Latency returned to normal

INCIDENT CLOSED:
- Resolution time: 2 minutes (vs 15-30 minutes with human)
- Update incident timeline
- Notify Communicator Agent to post update
- Tag for Investigator Agent (post-mortem: why OOM happened?)
```

---

### 1.4 Investigator Agent - "The Root Cause Detective"

**Purpose:** Performs deep Root Cause Analysis (RCA) by correlating metrics, logs, and traces. Operates asynchronously and produces comprehensive incident reports.

#### Input Sources

```yaml
Primary:
  - Incident timeline (from memory layer)
  - Mimir metrics (PromQL queries)
  - Loki logs (LogQL queries)
  - Tempo distributed traces (TraceQL queries)
  
Secondary:
  - Code repository (GitHub/GitLab for recent changes)
  - Deployment history (CI/CD systems)
  - Past similar incidents (vector similarity search)
  - External context (AWS status page, dependency service status)

Trigger Method:
  - Async queue (non-urgent RCA requests)
  - On-demand via human request ("@investigator explain INC-123")
  - Automatic post-incident (all P0/P1 incidents)
```

#### LLM Capabilities & Prompts

**Model:** Claude 3.5 Sonnet or Opus (requires deep reasoning and synthesis)

**Core Prompt Template:**
```python
INVESTIGATOR_PROMPT = """
You are an Investigator Agent performing Root Cause Analysis (RCA) for production incidents. Your goal is to produce a comprehensive, evidence-based analysis that helps prevent future occurrences.

INCIDENT:
{incident_summary}

TIMELINE:
{incident_timeline}

AVAILABLE DATA:
- Metrics: Access via query_metrics(promql)
- Logs: Access via query_logs(logql)
- Traces: Access via query_traces(traceql)
- Recent Changes: {deployment_history}

YOUR INVESTIGATION PROCESS:

1. HYPOTHESIS GENERATION
   - Based on symptoms, what are the top 3-5 possible root causes?
   - Rank by likelihood (high/medium/low)

2. EVIDENCE GATHERING (Iterative)
   For each hypothesis:
   - What metrics would confirm/refute this hypothesis?
   - What log patterns would indicate this cause?
   - What traces would show this behavior?
   - Query relevant data sources

3. CORRELATION ANALYSIS
   - Time-align metrics, logs, traces to build causal chain
   - Example: "Deploy at 14:23:00 → CPU spike at 14:23:15 → Error logs at 14:23:18"
   - Identify triggering event vs symptoms

4. ROOT CAUSE DETERMINATION
   - Apply "5 Whys" reasoning
   - Distinguish proximate cause (immediate trigger) from root cause (underlying issue)
   - Example:
     * Proximate: Database connection pool exhausted
     * Root: Recent code change introduced connection leak
     * Deeper Root: Missing connection pool monitoring alert

5. SUPPORTING EVIDENCE
   - Include specific metric values, log snippets, trace IDs
   - Link to Grafana dashboards, Loki queries
   - Show before/after comparisons

6. CONTRIBUTING FACTORS
   - What made this incident worse or easier to resolve?
   - Were there warning signs missed?
   - Did existing runbooks help or need updates?

7. REMEDIATION ANALYSIS
   - What actions were taken (by humans or agents)?
   - Which actions were effective?
   - What was the resolution mechanism?

OUTPUT FORMAT (Structured Markdown):
# Incident Report: {incident_id}

## Executive Summary
- **Duration**: {start_time} to {end_time} ({duration} minutes)
- **Severity**: {severity}
- **Customer Impact**: {impact_description}
- **Root Cause**: {one_sentence_summary}
- **Resolution**: {one_sentence_summary}

## Timeline
{detailed_timeline_with_evidence}

## Root Cause Analysis

### Hypotheses Investigated
1. [Hypothesis 1] - CONFIRMED / REFUTED
2. [Hypothesis 2] - CONFIRMED / REFUTED
...

### Root Cause
{detailed_explanation_with_evidence}

### Supporting Evidence
- Metric: [link to Grafana]
- Logs: [link to Loki query]
- Traces: [link to Tempo trace]

## Contributing Factors
{factors_that_amplified_or_mitigated_incident}

## What Went Well
{positive_aspects_of_response}

## What Could Be Improved
{actionable_improvement_suggestions}

## Action Items
- [ ] [Action 1 - Owner: TBD - Priority: High]
- [ ] [Action 2 - Owner: TBD - Priority: Medium]
...

## Runbook Updates
{suggestions_for_new_or_updated_runbooks}

---
Generated by Investigator Agent | Review by: {suggested_human_reviewer}
"""
```

**Advanced Techniques:**
```python
# Multi-modal analysis example
def investigate_latency_spike(incident_id: str):
    # 1. Metrics: Identify timing
    latency_data = query_metrics(
        promql='histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))',
        time_range='incident_window'
    )
    
    # 2. Traces: Find slow exemplars
    slow_traces = query_traces(
        traceql='{ duration > 5s && span.http.status_code >= 500 }',
        limit=10
    )
    
    # 3. Logs: Correlate errors
    for trace in slow_traces:
        error_logs = query_logs(
            logql=f'{{service="api"}} |= "{trace.trace_id}" | json | level="error"'
        )
        
    # 4. Code changes: Find culprit commit
    recent_deploys = get_deployments(service='api', hours_before_incident=6)
    
    # 5. LLM synthesis
    llm_analysis = claude.analyze(
        hypothesis="Recent deployment introduced N+1 query",
        evidence={
            'latency': latency_data,
            'traces': slow_traces,
            'logs': error_logs,
            'deploys': recent_deploys
        }
    )
    
    return llm_analysis
```

#### Tools & Actions

```python
class InvestigatorAgent:
    """Investigator Agent tool definitions"""
    
    # DATA QUERYING (Read-Only)
    def query_metrics(self, promql: str, start: str, end: str) -> DataFrame:
        """Query Mimir/Prometheus with PromQL"""
        
    def query_logs(self, logql: str, start: str, end: str, limit: int = 1000) -> List[LogLine]:
        """Query Loki with LogQL"""
        
    def query_traces(self, traceql: str, start: str, end: str, limit: int = 100) -> List[Trace]:
        """Query Tempo with TraceQL"""
        
    def get_trace_by_id(self, trace_id: str) -> Trace:
        """Fetch complete trace by ID"""
        
    def get_deployment_history(self, service: str, hours: int = 24) -> List[Deployment]:
        """Query CI/CD system for recent deployments"""
        
    def get_code_changes(self, repo: str, start_commit: str, end_commit: str) -> List[Commit]:
        """Query GitHub/GitLab for code changes"""
        
    def search_similar_incidents(self, incident: Incident, top_k: int = 5) -> List[Incident]:
        """Semantic search for similar past incidents (vector DB)"""
    
    # ANALYSIS TOOLS
    def correlate_timeline(self, metrics: List, logs: List, traces: List) -> Timeline:
        """Time-align different data sources"""
        
    def detect_change_points(self, metric_data: DataFrame) -> List[Timestamp]:
        """Statistical change point detection"""
        
    def build_dependency_graph(self, trace: Trace) -> DAG:
        """Extract service dependencies from trace"""
    
    # REPORTING
    def generate_report(self, analysis: Dict) -> MarkdownReport:
        """Generate structured incident report"""
        
    def create_action_items(self, report: MarkdownReport) -> List[Task]:
        """Extract actionable items for humans/teams"""
        
    def update_runbook(self, runbook_id: str, learnings: Dict) -> None:
        """Suggest runbook updates based on findings"""
        
    def store_incident_report(self, incident_id: str, report: MarkdownReport) -> str:
        """Store report in knowledge base (S3, Confluence, etc.)"""
```

#### Safety Boundaries

**CANNOT DO:**
- ❌ Take any remediation actions
- ❌ Modify production systems
- ❌ Access sensitive data (PII, credentials, secrets)
- ❌ Run arbitrary code execution

**CAN DO:**
- ✅ Query all observability data (metrics, logs, traces)
- ✅ Access code repositories (read-only)
- ✅ Search incident history
- ✅ Generate reports and action items
- ✅ Suggest runbook updates (requires human approval)

#### Handoff Criteria to Humans

**Always Requires Human Review:**
1. ALL incident reports (human must approve and assign action items)
2. Runbook change suggestions (human must approve and commit)
3. Ambiguous findings (multiple equally-likely root causes)
4. Incidents involving security or compliance

**Immediate Human Escalation:**
1. Investigation reveals critical vulnerability
2. Evidence of malicious activity
3. Data integrity concerns

---

### 1.5 Communicator Agent - "The Translator"

**Purpose:** Handles all external communication - posts updates to Slack/Teams, creates tickets, pages humans, and translates technical details into appropriate language for different audiences.

#### Input Sources

```yaml
Primary:
  - Incident timeline events (from memory layer)
  - Agent decisions (from Triage, First Responder, Investigator)
  - Incident severity and status changes
  
Secondary:
  - On-call schedules (PagerDuty, Opsgenie)
  - Communication templates (for different audiences)
  - Escalation policies

Trigger Method:
  - Event-driven (subscribe to incident timeline updates)
  - On-demand (agents explicitly call notify())
```

#### LLM Capabilities & Prompts

**Model:** Claude 3.5 Haiku (fast, cost-effective for message generation)

**Core Prompt Template:**
```python
COMMUNICATOR_PROMPT = """
You are a Communicator Agent responsible for translating technical incident information into clear, appropriate messages for different audiences.

INCIDENT UPDATE:
{incident_event}

TARGET AUDIENCE: {audience_type}
- "engineers": Technical team (Slack engineering channel)
- "executives": Leadership (email, brief)
- "customers": Public status page (non-technical)
- "oncall": On-call engineer (page, concise, actionable)

PREVIOUS MESSAGES: {message_history}

YOUR TASKS:

1. DETERMINE IF MESSAGE IS NEEDED
   - Is this update significant enough to notify?
   - Has enough time passed since last update? (rate limiting)
   - Is this audience affected by this update?

2. COMPOSE MESSAGE (Audience-Appropriate)
   
   For ENGINEERS:
   - Technical details: metrics, services affected, actions taken
   - Include links to dashboards, logs, runbooks
   - Use technical terminology
   - Format: Slack with code blocks, links
   
   For EXECUTIVES:
   - Business impact: # users affected, revenue impact, SLA status
   - High-level summary: what, impact, ETA for resolution
   - Avoid technical jargon
   - Format: Brief bullet points
   
   For CUSTOMERS (Status Page):
   - Customer-facing: friendly, transparent, no jargon
   - What is affected: specific features/services
   - What we're doing: active steps being taken
   - ETA: realistic timeframe (or "investigating")
   - Format: Plain text, professional
   
   For ONCALL:
   - Action required: what needs to be done NOW
   - Context: brief background
   - Links: direct links to incident, runbooks, dashboards
   - Format: Concise, urgent, actionable

3. SELECT CHANNEL
   - Slack: #incidents, #engineering, DM
   - PagerDuty: Page with context
   - Jira: Create/update ticket
   - Status Page: Public update

OUTPUT FORMAT (JSON):
{
  "should_send": true,
  "messages": [
    {
      "audience": "engineers",
      "channel": "slack:#incidents",
      "priority": "normal",
      "content": "Formatted message",
      "mentions": ["@oncall-backend"],
      "attachments": {
        "dashboard_url": "...",
        "runbook_url": "..."
      }
    },
    {
      "audience": "oncall",
      "channel": "pagerduty",
      "priority": "high",
      "content": "Brief alert message",
      "dedup_key": "incident-{incident_id}"
    }
  ],
  "reasoning": "Why these messages to these audiences"
}

TONE GUIDELINES:
- Engineers: Technical, collaborative ("We're seeing...")
- Executives: Confident, factual ("Impact is limited to...")
- Customers: Empathetic, transparent ("We're aware...")
- Oncall: Urgent, directive ("ACTION REQUIRED: ...")
"""
```

**Example Messages:**

```python
# Scenario: Database connection pool exhausted, First Responder scaled up pool

## To Engineers (Slack #incidents)
"""
🔴 **Incident INC-2024-001234** - Database Connection Pool Exhausted

**Status**: Mitigated by First Responder Agent
**Severity**: P1 (High)
**Affected Services**: api-service, worker-service
**Duration**: 14:23 - 14:26 (3 minutes)

**What Happened**:
- Database connection pool hit max capacity (100 connections)
- API latency spiked to p99 5.2s (baseline: 450ms)
- Error rate increased to 8% (baseline: 0.2%)

**Remediation Taken** (by First Responder Agent):
✅ Scaled connection pool from 100 → 150 connections
✅ Latency returned to normal within 60 seconds

**Next Steps**:
- Investigator Agent analyzing root cause (ETA: 15 minutes)
- Monitoring for recurrence

📊 Dashboard: https://grafana.company.com/d/api-health
📖 Runbook: https://runbooks.company.com/db-pool-exhaustion
"""

## To Executives (Email)
"""
Subject: Resolved - Brief API Slowdown (3 min, <5% users impacted)

The API experienced elevated latency for 3 minutes (2:23-2:26 PM) due to database connection limits. Our automated systems detected and resolved the issue. Estimated impact: <5% of active users experienced slow page loads. No data loss or security impact.

Status: Resolved
Root cause analysis: In progress, ETA 30 minutes
"""

## To Status Page (Public)
"""
[RESOLVED] - API Performance Issues

We experienced elevated response times for API requests between 2:23 PM and 2:26 PM UTC. The issue has been resolved and all systems are operating normally. We're investigating the root cause to prevent recurrence.
"""

## To Oncall (PagerDuty) - if First Responder needed human
"""
🚨 P1 Alert - Database Connection Pool Exhausted

ACTION REQUIRED: Monitor for recurrence

First Responder scaled pool 100→150. Issue resolved but may recur if root cause (possible connection leak) not addressed.

Dashboard: [link]
Incident: INC-2024-001234
Runbook: /db-pool-exhaustion
"""
```

#### Tools & Actions

```python
class CommunicatorAgent:
    """Communicator Agent tool definitions"""
    
    def send_slack_message(self, channel: str, message: str, mentions: List[str] = None) -> str:
        """Post message to Slack channel"""
        
    def send_pagerduty_alert(self, message: str, severity: str, dedup_key: str) -> str:
        """Trigger PagerDuty alert for on-call"""
        
    def create_jira_ticket(self, summary: str, description: str, priority: str) -> str:
        """Create Jira ticket for action items"""
        
    def update_status_page(self, component: str, status: str, message: str) -> None:
        """Update public status page (e.g., Atlassian StatusPage)"""
        
    def send_email(self, recipients: List[str], subject: str, body: str) -> None:
        """Send email notification"""
        
    def get_oncall_engineer(self, schedule: str) -> Dict:
        """Query PagerDuty/Opsgenie for current on-call"""
        
    def get_message_history(self, incident_id: str) -> List[Message]:
        """Retrieve previous messages for context"""
        
    def rate_limit_check(self, channel: str, min_interval_minutes: int = 5) -> bool:
        """Prevent message spam (max 1 message per 5 min per channel)"""
```

#### Safety Boundaries

**CANNOT DO:**
- ❌ Send messages pretending to be a human
- ❌ Make commitments on behalf of team ("We'll have this fixed by...")
- ❌ Share sensitive data (logs with PII, credentials, internal details)
- ❌ Modify on-call schedules or escalation policies

**CAN DO:**
- ✅ Post as "Observability Bot" / "AI Agent" (clearly identified)
- ✅ Provide factual incident updates
- ✅ Suggest actions but clearly marked as recommendations
- ✅ Create tickets and trigger alerts

#### Handoff Criteria to Humans

**Require Human Approval:**
1. Messages to executives or external stakeholders (auto-draft, human approves)
2. Public status page updates for P0 incidents
3. Messages involving customer commitments or SLA implications

**Automatic Sending (No Approval):**
1. Internal engineering notifications (Slack #incidents)
2. Standard incident updates following templates
3. On-call pages for P1+ incidents (always trigger)

---

### 1.6 On-Call Coordinator Agent - "The Escalation Manager"

**Purpose:** Manages escalation chains, tracks acknowledgments, ensures incidents don't fall through cracks, and provides context to on-call engineers when they engage.

#### Input Sources

```yaml
Primary:
  - PagerDuty / Opsgenie API (on-call schedules, ack status)
  - Incident timeline (status changes, assignments)
  - Escalation policies (from configuration)
  
Secondary:
  - Human interaction events (Slack threads, ticket comments)
  - SLA timers (incident age, time-to-ack, time-to-resolution)

Trigger Method:
  - Event-driven (incident status changes)
  - Scheduled check (every 60 seconds for active incidents)
  - Human request ("@coordinator status INC-123")
```

#### LLM Capabilities & Prompts

**Model:** Claude 3.5 Haiku (fast decision-making, pattern matching)

**Core Prompt Template:**
```python
COORDINATOR_PROMPT = """
You are an On-Call Coordinator Agent managing incident escalation and ensuring no incident goes unattended.

ACTIVE INCIDENTS:
{incident_list}

ESCALATION POLICIES:
{escalation_rules}

ON-CALL SCHEDULES:
{oncall_schedule}

YOUR TASKS:

1. MONITOR INCIDENT STATES
   For each active incident:
   - Has it been acknowledged? (within SLA: P0=1min, P1=5min, P2=15min)
   - Is there active investigation? (activity in last 10 minutes)
   - Is it stuck? (no status change in 30+ minutes for P0/P1)
   - Is resolution verified? (issue marked resolved but metrics still degraded)

2. ESCALATION DECISIONS
   Trigger escalation if:
   - Incident not acknowledged within SLA
   - Assigned engineer not responding (no activity in 10 min for P0)
   - Incident severity increased (P2 → P1)
   - Multiple related incidents (potential widespread issue)
   - Resolution attempted but issue persists

3. CONTEXT PREPARATION
   When escalating or human engages:
   - Summarize "story so far" (what agents did, what failed)
   - Highlight key evidence (abnormal metrics, error patterns)
   - Link to relevant resources (dashboards, runbooks, similar incidents)
   - Suggest next investigation steps

4. HANDOFF MANAGEMENT
   - Track ownership (which human/agent is actively working)
   - Prevent duplicate work (multiple people investigating same issue)
   - Manage shift changes (brief incoming on-call engineer)

OUTPUT FORMAT (JSON):
{
  "incidents": [
    {
      "incident_id": "INC-2024-001234",
      "current_state": "acknowledged",
      "assigned_to": "engineer@company.com",
      "sla_status": {
        "time_to_ack": "45 seconds (SLA: 5 min) ✅",
        "time_to_resolution": "12 minutes (SLA: 30 min) ⏳"
      },
      "health_check": {
        "is_stuck": false,
        "last_activity": "2 minutes ago",
        "resolution_verified": null
      },
      "recommended_action": "monitor|escalate|request_update|close",
      "reasoning": "Brief explanation"
    }
  ],
  "escalations": [
    {
      "incident_id": "INC-2024-001235",
      "reason": "Not acknowledged after 6 minutes (SLA: 5 min)",
      "escalate_to": "secondary_oncall",
      "context_summary": "API latency spike, First Responder attempted pod restart (failed)",
      "suggested_next_steps": ["Check for recent deployments", "Review application logs for errors"]
    }
  ]
}
"""
```

**Context Summary Example:**
```python
# When engineer acknowledges page at 3 AM
CONTEXT_BRIEFING = """
📋 **Incident Context for INC-2024-001234**

**Quick Summary**:
Database connection pool exhausted → API latency spike → Auto-remediation attempted → Issue persists

**Timeline** (last 10 minutes):
- 02:47 AM: Sentinel Agent detected latency anomaly (+120% baseline)
- 02:48 AM: Triage Agent classified as P1, correlated 8 downstream alerts
- 02:49 AM: First Responder Agent scaled connection pool 100 → 150
- 02:51 AM: Partial improvement (latency reduced but still +60% baseline)
- 02:52 AM: First Responder escalated to human (rate limit: 2 actions already taken)
- 02:53 AM: YOU PAGED

**Current State**:
- API latency: p99 = 1.2s (baseline: 450ms) - Still degraded
- Error rate: 2.1% (baseline: 0.2%)
- Affected: ~10% of requests

**What We've Tried**:
✅ Scaled connection pool (partial improvement)
❌ Pod restart (First Responder blocked due to recent deployment in progress)

**Suggested Next Steps**:
1. Check if recent deployment (api-v2.3.4 at 02:40 AM) introduced connection leak
2. Review application logs for "connection timeout" errors
3. Consider rolling back deployment if evidence points to regression

**Resources**:
📊 Dashboard: https://grafana.company.com/d/api-health
📖 Runbook: https://runbooks.company.com/db-pool-exhaustion
🔍 Loki Query: {service="api"} |= "connection" | json | level="error"
"""
```

#### Tools & Actions

```python
class OnCallCoordinatorAgent:
    """On-Call Coordinator Agent tool definitions"""
    
    def get_active_incidents(self) -> List[Incident]:
        """Fetch all open/active incidents"""
        
    def get_oncall_schedule(self, team: str) -> Dict:
        """Query PagerDuty/Opsgenie for current on-call rotation"""
        
    def check_acknowledgment_status(self, incident_id: str) -> Dict:
        """Check if incident was acknowledged and by whom"""
        
    def calculate_sla_metrics(self, incident: Incident) -> Dict:
        """Calculate time-to-ack, time-to-resolution, SLA compliance"""
        
    def detect_stuck_incident(self, incident: Incident) -> bool:
        """Detect if incident has no recent activity"""
        
    def escalate_incident(self, incident_id: str, target: str, reason: str) -> None:
        """Trigger escalation (page next person in chain)"""
        
    def generate_context_summary(self, incident_id: str) -> str:
        """Create human-readable context brief for on-call engineer"""
        
    def track_incident_owner(self, incident_id: str, owner: str) -> None:
        """Update incident ownership"""
        
    def request_status_update(self, incident_id: str, assignee: str) -> None:
        """Prompt assignee for status update (via Slack DM)"""
        
    def verify_resolution(self, incident_id: str) -> Dict:
        """Check if metrics confirm incident is truly resolved"""
```

#### Safety Boundaries

**CANNOT DO:**
- ❌ Override escalation policies set by humans
- ❌ Skip escalation levels (always follow chain)
- ❌ Silence incidents or prevent pages
- ❌ Modify on-call schedules

**CAN DO:**
- ✅ Page on-call engineers per escalation policy
- ✅ Track and report SLA compliance
- ✅ Provide context summaries
- ✅ Request status updates (gentle nudges)

#### Handoff Criteria to Humans

**Always Notify Humans:**
1. P0 incidents (always page immediately, never handle autonomously)
2. Incidents exceeding time-to-ack SLA
3. Incidents with no resolution progress for >30 minutes (P1) or >2 hours (P2)
4. Shift changes (brief incoming on-call)

**Escalate to Leadership:**
1. Multiple P1 incidents simultaneously (potential crisis)
2. Incident duration exceeds SLA by >2x
3. Same incident recurring >3 times in 24 hours (systemic issue)

---

## 2. Claude API vs AWS Bedrock Analysis

### Decision Matrix

| Criteria | Claude API (Direct) | AWS Bedrock (Claude via Bedrock) | Recommendation |
|----------|---------------------|----------------------------------|----------------|
| **Latency** | 🟢 Lower (direct) 200-500ms p95 | 🟡 Slightly higher (+50-100ms overhead) | **Claude API** for latency-sensitive (Sentinel, Triage) |
| **Cost** | 🟡 $3/MTok (Haiku) $15/MTok (Sonnet) | 🟢 10-20% cheaper on Bedrock | **Bedrock** for cost-sensitive (Investigator bulk analysis) |
| **AWS Integration** | 🟡 Requires VPC NAT/Internet Gateway | 🟢 Native AWS service (no internet egress) | **Bedrock** for security/compliance |
| **Model Access** | 🟢 Latest models first (Claude 3.5 Sonnet, Opus) | 🟡 Delayed by 2-4 weeks | **Claude API** for latest capabilities |
| **Multi-Region** | 🟢 Global endpoints | 🟡 Limited AWS regions (us-east-1, us-west-2, eu-west-1) | **Claude API** for multi-region |
| **Monitoring** | 🟡 Manual logging | 🟢 CloudWatch native, X-Ray tracing | **Bedrock** for observability |
| **Rate Limits** | 🟡 Per-account (shared) | 🟢 Per-model quotas (higher) | **Bedrock** for scale |
| **Vendor Lock-In** | 🟢 Provider-agnostic | 🟡 AWS-specific | **Claude API** for portability |

### Recommended Hybrid Approach

**Use Claude API for:**
- **Sentinel Agent**: Needs lowest latency, latest models (pattern recognition)
- **Triage Agent**: Requires fast decision-making (<1s)
- **First Responder Agent**: Safety-critical decisions (latest Sonnet/Opus)

**Use AWS Bedrock for:**
- **Investigator Agent**: Bulk analysis, cost-sensitive (can use Haiku)
- **Communicator Agent**: Message generation (Haiku sufficient)
- **On-Call Coordinator Agent**: Background monitoring (non-latency-sensitive)

### Cost Comparison (50 Hosts, Monthly)

```
Scenario: 50 hosts, 5M metrics/min, 200 GB logs/day, 100K traces/day

CLAUDE API PRICING:
- Haiku: $0.25/MTok (input) $1.25/MTok (output)
- Sonnet: $3/MTok (input) $15/MTok (output)

BEDROCK PRICING (10-20% cheaper):
- Haiku: $0.20/MTok (input) $1/MTok (output)
- Sonnet: $2.40/MTok (input) $12/MTok (output)

ESTIMATED USAGE:
Agent                 | Invocations/Day | Tokens/Invocation | Model  | Monthly Cost (API) | Monthly Cost (Bedrock)
----------------------|-----------------|-------------------|--------|--------------------|----------------------
Sentinel              | 28,800          | 2K input, 500 out | Sonnet | $1,296             | $1,036
Triage                | 500             | 3K input, 800 out | Sonnet | $67.50             | $54
First Responder       | 50              | 4K input, 1K out  | Sonnet | $8.25              | $6.60
Investigator          | 20              | 20K input, 5K out | Sonnet | $19                | $15.20
Communicator          | 800             | 1K input, 300 out | Haiku  | $9.60              | $7.68
On-Call Coordinator   | 2,880           | 1.5K input, 500 out| Haiku | $17.28             | $13.82
----------------------|-----------------|-------------------|--------|--------------------|----------------------
TOTAL                 |                 |                   |        | $1,417/month       | $1,133/month

HYBRID APPROACH (Recommended):
- Sentinel, Triage, First Responder → Claude API: $1,371.75/month
- Investigator, Communicator, Coordinator → Bedrock: $36.70/month
TOTAL: $1,408/month (saves $9/month but better latency/model access)
```

**Winner: Hybrid Approach**
- Critical path agents (Sentinel, Triage, First Responder) use Claude API for latency + latest models
- Background agents (Investigator, Communicator, Coordinator) use Bedrock for cost savings + AWS integration

### Implementation Strategy

```python
# Agent Factory with Model Router
class AgentModelRouter:
    def __init__(self):
        self.claude_api = anthropic.Client(api_key=os.getenv("CLAUDE_API_KEY"))
        self.bedrock = boto3.client("bedrock-runtime", region_name="us-east-1")
    
    def get_client_for_agent(self, agent_type: str) -> LLMClient:
        """Route agent to appropriate LLM backend"""
        critical_path_agents = ["sentinel", "triage", "first_responder"]
        
        if agent_type in critical_path_agents:
            return ClaudeAPIClient(self.claude_api, model="claude-3-5-sonnet-20241022")
        else:
            return BedrockClient(self.bedrock, model_id="anthropic.claude-3-5-haiku-20241022-v1:0")
