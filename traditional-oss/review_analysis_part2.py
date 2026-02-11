#!/usr/bin/env python3

# =============================================================================
# LOKI CONFIGURATION REVIEW
# =============================================================================

print("[3] LOKI CONFIGURATION REVIEW (configs-loki.yml)")
print("-" * 80)

loki_issues = []

loki_issues.append({
    'severity': 'CRITICAL',
    'line': '39',
    'issue': 'Invalid WAL memory ceiling format',
    'detail': 'replay_memory_ceiling: 4GB - Should be integer bytes, not string with GB',
    'fix': 'Change to: replay_memory_ceiling: 4294967296  # 4GB in bytes'
})

loki_issues.append({
    'severity': 'CRITICAL',
    'line': '91',
    'issue': 'max_streams_per_user set to 0 (unlimited)',
    'detail': 'Allows unlimited streams which can cause OOM. Dangerous in production',
    'fix': 'Set realistic limit: max_streams_per_user: 10000'
})

loki_issues.append({
    'severity': 'HIGH',
    'line': '50-57',
    'issue': 'Deprecated Loki schema version',
    'detail': 'Using v12 schema from 2024-01-01. Loki 2.9+ supports v13 with better performance',
    'fix': 'Update to schema v13 if using Loki 3.0+, otherwise v12 is acceptable for 2.9'
})

loki_issues.append({
    'severity': 'HIGH',
    'line': '512-513',
    'issue': 'Outdated Loki version in install script',
    'detail': 'LOKI_VERSION="2.9.4" - Current stable is 2.9.10+ or 3.0+',
    'fix': 'Update to: LOKI_VERSION="2.9.10" or LOKI_VERSION="3.0.3"'
})

loki_issues.append({
    'severity': 'HIGH',
    'line': '62',
    'issue': 'S3 URL format incorrect',
    'detail': 's3: s3://us-east-1/prod-observability-loki-logs - Invalid format',
    'fix': 'Should be: s3: us-east-1 (just the region, bucket specified separately)'
})

loki_issues.append({
    'severity': 'HIGH',
    'line': '73',
    'issue': 'Index gateway not configured',
    'detail': 'server_address: "" with comment "Not using index gateway in simple mode" - but using tsdb_shipper',
    'fix': 'For production, should use index gateway or clarify architecture'
})

loki_issues.append({
    'severity': 'MEDIUM',
    'line': '107',
    'issue': 'Retention period inconsistency',
    'detail': 'retention_period: 2160h (90 days) but S3 lifecycle says 180 days in architecture',
    'fix': 'Align with S3 lifecycle or update both to match business requirements'
})

loki_issues.append({
    'severity': 'MEDIUM',
    'line': '26',
    'issue': 'Chunk size may be suboptimal',
    'detail': 'chunk_block_size: 262144 (256KB) is default but might be too small for high throughput',
    'fix': 'Consider increasing to 524288 (512KB) for better S3 efficiency'
})

loki_issues.append({
    'severity': 'MEDIUM',
    'line': '150-151',
    'issue': 'Ruler storage configuration duplicates S3 region',
    'detail': 'Both s3.bucketnames and s3.s3 fields specified',
    'fix': 'Should be: bucketnames: prod-observability-loki-logs, region: us-east-1'
})

loki_issues.append({
    'severity': 'LOW',
    'line': '376',
    'issue': 'Missing LimitNPROC in systemd',
    'detail': 'LimitNOFILE specified but not LimitNPROC for process limits',
    'fix': 'Add: LimitNPROC=65536'
})

loki_issues.append({
    'severity': 'LOW',
    'line': '254-256',
    'issue': 'Structured metadata feature version dependency',
    'detail': 'Using structured_metadata which requires Loki 2.9+. Not documented',
    'fix': 'Add comment specifying minimum version requirement'
})

for issue in loki_issues:
    severity_symbol = {'CRITICAL': '🔴', 'HIGH': '🟠', 'MEDIUM': '🟡', 'LOW': '⚪'}
    line_info = f"Line {issue['line']}: " if issue['line'] else ""
    print(f"{severity_symbol[issue['severity']]} [{issue['severity']}] {line_info}{issue['issue']}")
    print(f"   Detail: {issue['detail']}")
    print(f"   Fix: {issue['fix']}")
    print()

print(f"Loki issues found: {len(loki_issues)}")
print()

# =============================================================================
# TEMPO & OPENTELEMETRY CONFIGURATION REVIEW
# =============================================================================

print("[4] TEMPO & OPENTELEMETRY CONFIGURATION REVIEW (configs-tempo-grafana-otel.yml)")
print("-" * 80)

tempo_issues = []

tempo_issues.append({
    'severity': 'CRITICAL',
    'line': '802',
    'issue': 'Severely outdated Tempo version',
    'detail': 'TEMPO_VERSION="2.3.1" from install script. Current stable is 2.6+',
    'fix': 'Update to: TEMPO_VERSION="2.6.3" or latest stable'
})

tempo_issues.append({
    'severity': 'CRITICAL',
    'line': '810',
    'issue': 'OpenTelemetry Collector version outdated',
    'detail': 'OTEL_VERSION="0.96.0" - Current is 0.115+ (released 2024)',
    'fix': 'Update to: OTEL_VERSION="0.115.0" (check compatibility)'
})

tempo_issues.append({
    'severity': 'CRITICAL',
    'line': '706-710',
    'issue': 'Outdated OpenTelemetry Python package versions',
    'detail': 'opentelemetry-api==1.22.0 is outdated (current is 1.27+)',
    'fix': 'Update all opentelemetry packages to latest: 1.27.0+'
})

tempo_issues.append({
    'severity': 'HIGH',
    'line': '73',
    'issue': 'Parquet format version might not exist',
    'detail': 'version: vParquet3 - Verify this is correct format version for Tempo 2.3',
    'fix': 'Check Tempo docs - might be "v2" or "vParquet2". "vParquet3" may not exist'
})

tempo_issues.append({
    'severity': 'HIGH',
    'line': '88',
    'issue': 'Block retention only 30 days',
    'detail': 'block_retention: 720h (30 days) - traces archived too quickly for analysis',
    'fix': 'Consider 90 days (2160h) to align with logs retention'
})

tempo_issues.append({
    'severity': 'HIGH',
    'line': '509',
    'issue': 'Prometheus version inconsistency',
    'detail': 'prometheusVersion: 2.40.0 but architecture recommends 2.50+',
    'fix': 'Update to match actual Prometheus deployment version'
})

tempo_issues.append({
    'severity': 'MEDIUM',
    'line': '217',
    'issue': 'Memory limiter may be too restrictive',
    'detail': 'limit_mib: 512 with spike_limit_mib: 128 - Total 640MB may cause drops',
    'fix': 'Increase to limit_mib: 1024, spike_limit_mib: 256 for 50 hosts'
})

tempo_issues.append({
    'severity': 'MEDIUM',
    'line': '270',
    'issue': 'Transform processor syntax might be outdated',
    'detail': 'Using set() function - verify syntax for OTel Collector 0.96',
    'fix': 'Check latest OTTL documentation for correct syntax'
})

tempo_issues.append({
    'severity': 'MEDIUM',
    'line': '372',
    'issue': 'Grafana database host uses placeholder',
    'detail': 'host = grafana-db.xxxxx.us-east-1.rds.amazonaws.com:5432',
    'fix': 'Document to replace xxxxx with actual RDS endpoint or use variable reference'
})

tempo_issues.append({
    'severity': 'MEDIUM',
    'line': '818',
    'issue': 'Outdated Grafana version',
    'detail': 'GRAFANA_VERSION="10.3.3" - Current stable is 11.x series',
    'fix': 'Update to: GRAFANA_VERSION="11.3.0" or latest 11.x'
})

tempo_issues.append({
    'severity': 'LOW',
    'line': '454',
    'issue': 'Deprecated tracing configuration',
    'detail': '[tracing.opentelemetry.otlp] - Check if this section name is current',
    'fix': 'Verify against Grafana 10.3 docs for correct OTLP configuration'
})

tempo_issues.append({
    'severity': 'LOW',
    'line': '478',
    'issue': 'Feature toggle flags may not exist',
    'detail': 'tempoSearch tempoBackendSearch - verify these are valid for Grafana 10.3',
    'fix': 'Check Grafana 10.3 feature toggles documentation'
})

tempo_issues.append({
    'severity': 'LOW',
    'line': '666',
    'issue': 'Systemd environment variable format',
    'detail': 'Environment="EC2_INSTANCE_ID=%i" - %i is systemd instance name, not EC2 ID',
    'fix': 'Use ExecStartPre script to fetch and set EC2_INSTANCE_ID properly'
})

for issue in tempo_issues:
    severity_symbol = {'CRITICAL': '🔴', 'HIGH': '🟠', 'MEDIUM': '🟡', 'LOW': '⚪'}
    line_info = f"Line {issue['line']}: " if issue['line'] else ""
    print(f"{severity_symbol[issue['severity']]} [{issue['severity']}] {line_info}{issue['issue']}")
    print(f"   Detail: {issue['detail']}")
    print(f"   Fix: {issue['fix']}")
    print()

print(f"Tempo/OTel/Grafana issues found: {len(tempo_issues)}")
print()

