-- AI Agent Incident Storage Schema
-- PostgreSQL database schema for AI-First Observability Platform
-- Version: 1.0
-- Compatible with: PostgreSQL 15+

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- For fuzzy text search

-- ============================================================================
-- INCIDENTS TABLE - Core incident records
-- ============================================================================

CREATE TYPE incident_severity AS ENUM ('P0', 'P1', 'P2', 'P3', 'P4');
CREATE TYPE incident_status AS ENUM ('open', 'investigating', 'mitigated', 'resolved', 'closed');

CREATE TABLE incidents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    incident_number SERIAL UNIQUE NOT NULL,  -- Human-friendly: INC-2024-001234
    
    -- Core metadata
    title VARCHAR(500) NOT NULL,
    description TEXT,
    severity incident_severity NOT NULL,
    status incident_status NOT NULL DEFAULT 'open',
    
    -- Service information
    service_name VARCHAR(255) NOT NULL,
    environment VARCHAR(50) DEFAULT 'production',
    affected_services TEXT[],  -- Array of downstream services
    
    -- Agent tracking
    detected_by VARCHAR(50),  -- 'sentinel', 'alertmanager', 'human'
    triaged_by VARCHAR(50),   -- 'triage_agent', 'human'
    handled_by VARCHAR(50),   -- 'first_responder', 'investigator', 'human'
    
    -- Timestamps
    detected_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    acknowledged_at TIMESTAMP WITH TIME ZONE,
    resolved_at TIMESTAMP WITH TIME ZONE,
    closed_at TIMESTAMP WITH TIME ZONE,
    
    -- Correlation
    related_incident_id UUID REFERENCES incidents(id),  -- Link to root cause incident
    is_root_cause BOOLEAN DEFAULT TRUE,
    
    -- Human assignment
    assigned_to VARCHAR(255),  -- Email of on-call engineer
    escalated_to VARCHAR(255),
    escalation_level INT DEFAULT 0,
    
    -- Metrics
    mttr_seconds INT,  -- Mean Time To Resolution (calculated)
    customer_impact_score INT CHECK (customer_impact_score BETWEEN 0 AND 10),
    
    -- Metadata
    tags TEXT[],
    labels JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_incidents_status ON incidents(status);
CREATE INDEX idx_incidents_severity ON incidents(severity);
CREATE INDEX idx_incidents_service ON incidents(service_name);
CREATE INDEX idx_incidents_detected_at ON incidents(detected_at DESC);
CREATE INDEX idx_incidents_assigned_to ON incidents(assigned_to);
CREATE INDEX idx_incidents_related ON incidents(related_incident_id);
CREATE INDEX idx_incidents_labels ON incidents USING GIN(labels);
CREATE INDEX idx_incidents_tags ON incidents USING GIN(tags);

-- Full-text search on title and description
CREATE INDEX idx_incidents_search ON incidents USING GIN(to_tsvector('english', title || ' ' || COALESCE(description, '')));

-- ============================================================================
-- INCIDENT_TIMELINE - Event history for each incident
-- ============================================================================

CREATE TYPE timeline_event_type AS ENUM (
    'detection',
    'triage',
    'remediation_attempt',
    'remediation_success',
    'remediation_failure',
    'escalation',
    'acknowledgment',
    'human_action',
    'status_change',
    'comment',
    'metrics_snapshot'
);

CREATE TABLE incident_timeline (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    incident_id UUID NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
    
    event_type timeline_event_type NOT NULL,
    event_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    
    actor VARCHAR(255) NOT NULL,  -- Agent name or human email
    actor_type VARCHAR(50) NOT NULL,  -- 'agent', 'human', 'system'
    
    title VARCHAR(500) NOT NULL,
    description TEXT,
    
    -- Event-specific data (JSON for flexibility)
    metadata JSONB,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_timeline_incident ON incident_timeline(incident_id, event_time DESC);
CREATE INDEX idx_timeline_event_type ON incident_timeline(event_type);

-- ============================================================================
-- ANOMALIES - Raw anomaly detections from Sentinel
-- ============================================================================

CREATE TYPE anomaly_status AS ENUM ('detected', 'triaged', 'false_positive', 'resolved');

CREATE TABLE anomalies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    incident_id UUID REFERENCES incidents(id),  -- NULL if not escalated to incident
    
    -- Detection info
    service_name VARCHAR(255) NOT NULL,
    detected_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    detected_by VARCHAR(50) DEFAULT 'sentinel',
    
    -- Anomaly details
    metric_name VARCHAR(255) NOT NULL,
    current_value DOUBLE PRECISION NOT NULL,
    baseline_mean DOUBLE PRECISION,
    baseline_std DOUBLE PRECISION,
    deviation_pct DOUBLE PRECISION,
    
    -- LLM analysis
    confidence DOUBLE PRECISION CHECK (confidence BETWEEN 0 AND 1),
    anomaly_type VARCHAR(100),  -- 'spike', 'gradual_increase', 'drop', 'oscillation'
    reasoning TEXT,
    recommended_action VARCHAR(100),
    
    -- Status
    status anomaly_status NOT NULL DEFAULT 'detected',
    escalated_to_incident BOOLEAN DEFAULT FALSE,
    
    -- Context
    context JSONB,  -- Store deployment events, traffic patterns, etc.
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_anomalies_service ON anomalies(service_name);
CREATE INDEX idx_anomalies_detected_at ON anomalies(detected_at DESC);
CREATE INDEX idx_anomalies_status ON anomalies(status);
CREATE INDEX idx_anomalies_incident ON anomalies(incident_id);

-- ============================================================================
-- ALERTS - External alerts (from Prometheus, Grafana, etc.)
-- ============================================================================

CREATE TYPE alert_status AS ENUM ('firing', 'acknowledged', 'suppressed', 'resolved');

CREATE TABLE alerts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    incident_id UUID REFERENCES incidents(id),  -- Linked by Triage Agent
    
    -- Alert source
    external_alert_id VARCHAR(255) UNIQUE,  -- ID from Alertmanager
    alert_source VARCHAR(100) NOT NULL,  -- 'prometheus', 'grafana', 'cloudwatch'
    
    -- Alert details
    alert_name VARCHAR(255) NOT NULL,
    service_name VARCHAR(255) NOT NULL,
    severity VARCHAR(50) NOT NULL,
    description TEXT,
    labels JSONB,
    annotations JSONB,
    
    -- Timing
    fired_at TIMESTAMP WITH TIME ZONE NOT NULL,
    acknowledged_at TIMESTAMP WITH TIME ZONE,
    resolved_at TIMESTAMP WITH TIME ZONE,
    
    -- Triage
    status alert_status NOT NULL DEFAULT 'firing',
    triaged_by VARCHAR(50),  -- 'triage_agent', 'human'
    is_duplicate BOOLEAN DEFAULT FALSE,
    suppression_reason TEXT,
    
    -- Correlation
    root_cause_alert_id UUID REFERENCES alerts(id),  -- Link to root cause
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_alerts_incident ON alerts(incident_id);
CREATE INDEX idx_alerts_service ON alerts(service_name);
CREATE INDEX idx_alerts_status ON alerts(status);
CREATE INDEX idx_alerts_fired_at ON alerts(fired_at DESC);
CREATE INDEX idx_alerts_external_id ON alerts(external_alert_id);
CREATE INDEX idx_alerts_root_cause ON alerts(root_cause_alert_id);

-- ============================================================================
-- RUNBOOKS - Automated remediation procedures
-- ============================================================================

CREATE TABLE runbooks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    runbook_id VARCHAR(100) UNIQUE NOT NULL,  -- e.g., "RB-POD-OOM-RESTART"
    
    title VARCHAR(500) NOT NULL,
    description TEXT,
    
    -- Matching criteria
    symptom_pattern TEXT NOT NULL,  -- Fuzzy match against incident title/description
    service_pattern VARCHAR(255),   -- Regex pattern for service name
    
    -- Automation
    safe_for_automation BOOLEAN DEFAULT FALSE,  -- Only TRUE if human-approved
    approved_by VARCHAR(255),  -- Email of approver
    approved_at TIMESTAMP WITH TIME ZONE,
    
    -- Action definition (JSON for flexibility)
    actions JSONB NOT NULL,  -- Array of action steps
    /*
    Example actions JSON:
    [
      {
        "type": "restart_single_pod",
        "target_selector": "app=api-service",
        "namespace": "production",
        "safety_checks": ["replica_count > 1", "no_recent_deployment"]
      }
    ]
    */
    
    -- Success criteria
    expected_outcome TEXT,
    success_metrics JSONB,  -- Metrics to check post-remediation
    rollback_plan TEXT,
    
    -- Usage stats
    times_used INT DEFAULT 0,
    success_rate DOUBLE PRECISION,
    avg_resolution_time_seconds INT,
    
    -- Metadata
    tags TEXT[],
    created_by VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_runbooks_safe_automation ON runbooks(safe_for_automation);
CREATE INDEX idx_runbooks_service_pattern ON runbooks(service_pattern);
CREATE INDEX idx_runbooks_search ON runbooks USING GIN(to_tsvector('english', title || ' ' || description || ' ' || symptom_pattern));

-- ============================================================================
-- REMEDIATION_ACTIONS - Log of all actions taken by First Responder
-- ============================================================================

CREATE TYPE action_status AS ENUM ('pending', 'executing', 'success', 'failed', 'aborted');

CREATE TABLE remediation_actions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    incident_id UUID NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
    runbook_id UUID REFERENCES runbooks(id),
    
    -- Action details
    action_type VARCHAR(100) NOT NULL,  -- 'restart_pod', 'scale_deployment', etc.
    target VARCHAR(500) NOT NULL,       -- Resource identifier
    
    -- Safety checks
    safety_checks_passed BOOLEAN NOT NULL,
    safety_check_results JSONB,
    blast_radius VARCHAR(100),  -- 'single_pod', 'single_instance', etc.
    
    -- Execution
    status action_status NOT NULL DEFAULT 'pending',
    executed_by VARCHAR(50) NOT NULL DEFAULT 'first_responder',
    executed_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    
    -- Results
    success BOOLEAN,
    error_message TEXT,
    output TEXT,  -- Command output or API response
    
    -- Pre/post metrics for validation
    pre_action_metrics JSONB,
    post_action_metrics JSONB,
    metrics_improved BOOLEAN,
    
    -- Rollback
    rollback_available BOOLEAN DEFAULT FALSE,
    rollback_executed BOOLEAN DEFAULT FALSE,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_remediation_incident ON remediation_actions(incident_id);
CREATE INDEX idx_remediation_runbook ON remediation_actions(runbook_id);
CREATE INDEX idx_remediation_status ON remediation_actions(status);
CREATE INDEX idx_remediation_success ON remediation_actions(success);
CREATE INDEX idx_remediation_executed_at ON remediation_actions(executed_at DESC);

-- ============================================================================
-- AGENT_DECISIONS - LLM reasoning audit trail
-- ============================================================================

CREATE TABLE agent_decisions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    incident_id UUID REFERENCES incidents(id),
    anomaly_id UUID REFERENCES anomalies(id),
    alert_id UUID REFERENCES alerts(id),
    
    agent_name VARCHAR(50) NOT NULL,
    agent_version VARCHAR(20),
    
    -- LLM metadata
    llm_model VARCHAR(100) NOT NULL,  -- 'claude-3-5-sonnet-20241022'
    llm_provider VARCHAR(50),  -- 'anthropic_api', 'bedrock'
    
    -- Prompt and response
    system_prompt TEXT,
    user_prompt TEXT,
    llm_response JSONB NOT NULL,  -- Full structured response
    
    -- Token usage (for cost tracking)
    input_tokens INT,
    output_tokens INT,
    estimated_cost_usd DOUBLE PRECISION,
    
    -- Decision metadata
    decision_type VARCHAR(100) NOT NULL,  -- 'anomaly_detection', 'triage', 'remediation'
    confidence DOUBLE PRECISION,
    reasoning TEXT,
    
    -- Outcome tracking (filled in later)
    was_correct BOOLEAN,  -- Human review
    feedback TEXT,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_agent_decisions_incident ON agent_decisions(incident_id);
CREATE INDEX idx_agent_decisions_agent ON agent_decisions(agent_name);
CREATE INDEX idx_agent_decisions_created_at ON agent_decisions(created_at DESC);
CREATE INDEX idx_agent_decisions_model ON agent_decisions(llm_model);

-- ============================================================================
-- BASELINE_METRICS - Statistical baselines for anomaly detection
-- ============================================================================

CREATE TABLE baseline_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    service_name VARCHAR(255) NOT NULL,
    metric_name VARCHAR(255) NOT NULL,
    
    -- Time window
    window_start TIMESTAMP WITH TIME ZONE NOT NULL,
    window_end TIMESTAMP WITH TIME ZONE NOT NULL,
    sample_count INT NOT NULL,
    
    -- Statistical measures
    mean DOUBLE PRECISION NOT NULL,
    std_dev DOUBLE PRECISION NOT NULL,
    p50 DOUBLE PRECISION NOT NULL,
    p95 DOUBLE PRECISION NOT NULL,
    p99 DOUBLE PRECISION NOT NULL,
    min_value DOUBLE PRECISION NOT NULL,
    max_value DOUBLE PRECISION NOT NULL,
    
    -- Time-of-day patterns (optional, for seasonal baselines)
    hour_of_day INT CHECK (hour_of_day BETWEEN 0 AND 23),
    day_of_week INT CHECK (day_of_week BETWEEN 0 AND 6),  -- 0=Monday, 6=Sunday
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_baseline_service_metric ON baseline_metrics(service_name, metric_name);
CREATE INDEX idx_baseline_window ON baseline_metrics(window_start, window_end);
CREATE UNIQUE INDEX idx_baseline_unique ON baseline_metrics(service_name, metric_name, window_start, hour_of_day, day_of_week) 
    WHERE hour_of_day IS NOT NULL AND day_of_week IS NOT NULL;

-- ============================================================================
-- COST_TRACKING - LLM and infrastructure costs
-- ============================================================================

CREATE TABLE cost_tracking (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    date DATE NOT NULL,
    agent_name VARCHAR(50) NOT NULL,
    
    -- LLM costs
    llm_invocations INT DEFAULT 0,
    llm_input_tokens BIGINT DEFAULT 0,
    llm_output_tokens BIGINT DEFAULT 0,
    llm_cost_usd DOUBLE PRECISION DEFAULT 0.0,
    
    -- Infrastructure costs (daily allocation)
    compute_cost_usd DOUBLE PRECISION DEFAULT 0.0,
    storage_cost_usd DOUBLE PRECISION DEFAULT 0.0,
    network_cost_usd DOUBLE PRECISION DEFAULT 0.0,
    
    -- Total
    total_cost_usd DOUBLE PRECISION GENERATED ALWAYS AS (
        llm_cost_usd + compute_cost_usd + storage_cost_usd + network_cost_usd
    ) STORED,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_cost_tracking_date_agent ON cost_tracking(date, agent_name);
CREATE INDEX idx_cost_tracking_date ON cost_tracking(date DESC);

-- ============================================================================
-- VIEWS - Useful aggregations
-- ============================================================================

-- Active incidents summary
CREATE VIEW active_incidents_summary AS
SELECT 
    i.id,
    i.incident_number,
    i.title,
    i.severity,
    i.status,
    i.service_name,
    i.detected_by,
    i.assigned_to,
    EXTRACT(EPOCH FROM (NOW() - i.detected_at)) / 60 AS minutes_open,
    COUNT(t.id) AS timeline_event_count
FROM incidents i
LEFT JOIN incident_timeline t ON t.incident_id = i.id
WHERE i.status IN ('open', 'investigating', 'mitigated')
GROUP BY i.id;

-- Agent performance metrics
CREATE VIEW agent_performance AS
SELECT 
    agent_name,
    DATE(created_at) AS date,
    COUNT(*) AS decision_count,
    AVG(confidence) AS avg_confidence,
    SUM(CASE WHEN was_correct = true THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(*), 0) AS accuracy_rate,
    SUM(estimated_cost_usd) AS daily_cost
FROM agent_decisions
WHERE was_correct IS NOT NULL  -- Only include reviewed decisions
GROUP BY agent_name, DATE(created_at);

-- Runbook effectiveness
CREATE VIEW runbook_effectiveness AS
SELECT 
    r.runbook_id,
    r.title,
    r.safe_for_automation,
    COUNT(ra.id) AS times_used,
    AVG(CASE WHEN ra.success THEN 1.0 ELSE 0.0 END) AS success_rate,
    AVG(EXTRACT(EPOCH FROM (ra.completed_at - ra.executed_at))) AS avg_execution_time_seconds
FROM runbooks r
LEFT JOIN remediation_actions ra ON ra.runbook_id = r.id
WHERE ra.status = 'success' OR ra.status = 'failed'
GROUP BY r.id;

-- Daily cost summary
CREATE VIEW daily_cost_summary AS
SELECT 
    date,
    SUM(llm_cost_usd) AS llm_cost,
    SUM(compute_cost_usd) AS compute_cost,
    SUM(storage_cost_usd) AS storage_cost,
    SUM(network_cost_usd) AS network_cost,
    SUM(total_cost_usd) AS total_cost
FROM cost_tracking
GROUP BY date
ORDER BY date DESC;

-- ============================================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================================

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_incidents_updated_at BEFORE UPDATE ON incidents
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_alerts_updated_at BEFORE UPDATE ON alerts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_runbooks_updated_at BEFORE UPDATE ON runbooks
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Calculate MTTR when incident is resolved
CREATE OR REPLACE FUNCTION calculate_mttr()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.resolved_at IS NOT NULL AND OLD.resolved_at IS NULL THEN
        NEW.mttr_seconds := EXTRACT(EPOCH FROM (NEW.resolved_at - NEW.detected_at));
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER calculate_incident_mttr BEFORE UPDATE ON incidents
    FOR EACH ROW EXECUTE FUNCTION calculate_mttr();

-- ============================================================================
-- SAMPLE DATA (for testing)
-- ============================================================================

-- Sample runbook
INSERT INTO runbooks (runbook_id, title, description, symptom_pattern, service_pattern, safe_for_automation, approved_by, actions, expected_outcome, tags)
VALUES (
    'RB-POD-OOM-RESTART',
    'Pod OutOfMemory - Restart to Clear Memory Leak',
    'Restarts a single pod experiencing OutOfMemoryError to clear transient memory leaks',
    'pod.*oom|memory.*exhausted|out of memory',
    'api-service|worker-service',
    true,
    'platform-team@company.com',
    '[
      {
        "type": "restart_single_pod",
        "safety_checks": ["replica_count > 1", "no_recent_deployment"],
        "blast_radius": "single_pod"
      }
    ]'::jsonb,
    'Pod restarts successfully, memory usage returns to baseline',
    ARRAY['kubernetes', 'memory', 'auto-remediation']
);

-- ============================================================================
-- PERMISSIONS (for application user)
-- ============================================================================

-- Create read-write user for agents
CREATE USER ai_agent_app WITH PASSWORD 'CHANGE_ME_IN_PRODUCTION';

GRANT CONNECT ON DATABASE incidents TO ai_agent_app;
GRANT USAGE ON SCHEMA public TO ai_agent_app;

GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO ai_agent_app;
GRANT SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO ai_agent_app;

-- Read-only user for dashboards/analytics
CREATE USER ai_agent_readonly WITH PASSWORD 'CHANGE_ME_IN_PRODUCTION';

GRANT CONNECT ON DATABASE incidents TO ai_agent_readonly;
GRANT USAGE ON SCHEMA public TO ai_agent_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO ai_agent_readonly;
GRANT SELECT ON ALL VIEWS IN SCHEMA public TO ai_agent_readonly;

-- ============================================================================
-- MAINTENANCE QUERIES
-- ============================================================================

-- Archive old incidents (run monthly)
-- DELETE FROM incidents WHERE closed_at < NOW() - INTERVAL '90 days';

-- Vacuum and analyze (run weekly)
-- VACUUM ANALYZE;

-- Check database size
-- SELECT pg_size_pretty(pg_database_size('incidents'));

-- Check table sizes
-- SELECT 
--     schemaname,
--     tablename,
--     pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
-- FROM pg_tables
-- WHERE schemaname = 'public'
-- ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================
