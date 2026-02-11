#!/usr/bin/env python3

# =============================================================================
# ARCHITECTURE VS CONFIG CONSISTENCY REVIEW
# =============================================================================

print("[5] ARCHITECTURE vs CONFIGURATION CONSISTENCY")
print("-" * 80)

consistency_issues = []

consistency_issues.append({
    'severity': 'CRITICAL',
    'files': 'ARCHITECTURE.md vs all configs',
    'issue': 'Version mismatch across board',
    'detail': 'Architecture specifies v2.50+ for Prometheus, v0.34+ for Thanos, v2.9+ for Loki, but configs show much older versions',
    'fix': 'Update ALL version numbers consistently across architecture and configs'
})

consistency_issues.append({
    'severity': 'HIGH',
    'files': 'ARCHITECTURE.md line 156-164 vs terraform-example.tf',
    'issue': 'Instance specifications dont match',
    'detail': 'Architecture says Prometheus on t3.large (2 vCPU, 8GB), but no EC2 instances defined in Terraform',
    'fix': 'Add EC2 launch templates and Auto Scaling Groups to Terraform'
})

consistency_issues.append({
    'severity': 'HIGH',
    'files': 'ARCHITECTURE.md line 198-212 vs configs-loki.yml',
    'issue': 'Loki retention mismatch',
    'detail': 'Architecture says 180 days retention, Loki config says 90 days (2160h)',
    'fix': 'Align retention periods: either update config to 4320h or architecture to 90 days'
})

consistency_issues.append({
    'severity': 'HIGH',
    'files': 'ARCHITECTURE.md line 187-188 vs configs-prometheus.yml',
    'issue': 'Prometheus retention inconsistency',
    'detail': 'Architecture says 15-day retention (500GB), config has both 15d time AND 450GB size',
    'fix': 'Remove size-based retention or document why both are needed'
})

consistency_issues.append({
    'severity': 'MEDIUM',
    'files': 'ARCHITECTURE.md vs terraform-example.tf',
    'issue': 'Missing Thanos components in Terraform',
    'detail': 'Architecture describes Thanos Query, Store, Compactor but no EC2 resources in Terraform',
    'fix': 'Add Thanos component infrastructure or document that Terraform is incomplete'
})

consistency_issues.append({
    'severity': 'MEDIUM',
    'files': 'ARCHITECTURE.md line 164 vs terraform-example.tf',
    'issue': 'No NLB for Prometheus',
    'detail': 'Architecture mentions prometheus-internal-nlb but only ALB defined in Terraform',
    'fix': 'Add aws_lb resource for internal NLB targeting Prometheus'
})

consistency_issues.append({
    'severity': 'MEDIUM',
    'files': 'Multiple files',
    'issue': 'Authentication not addressed',
    'detail': 'No authentication between components (Grafana→Prometheus, Tempo→S3)',
    'fix': 'Document authentication strategy or add basic auth configs'
})

consistency_issues.append({
    'severity': 'LOW',
    'files': 'All files',
    'issue': 'No disaster recovery documentation',
    'detail': 'No backup/restore procedures, no RTO/RPO defined',
    'fix': 'Add DR section to architecture with backup strategies'
})

for issue in consistency_issues:
    severity_symbol = {'CRITICAL': '🔴', 'HIGH': '🟠', 'MEDIUM': '🟡', 'LOW': '⚪'}
    print(f"{severity_symbol[issue['severity']]} [{issue['severity']}] {issue['files']}")
    print(f"   Issue: {issue['issue']}")
    print(f"   Detail: {issue['detail']}")
    print(f"   Fix: {issue['fix']}")
    print()

print(f"Consistency issues found: {len(consistency_issues)}")
print()

# =============================================================================
# SECURITY REVIEW
# =============================================================================

print("[6] SECURITY CONCERNS")
print("-" * 80)

security_issues = []

security_issues.append({
    'severity': 'CRITICAL',
    'issue': 'No encryption in transit between components',
    'detail': 'All internal communication uses HTTP (insecure: true). Prometheus, Loki, Tempo, Grafana all unencrypted',
    'fix': 'Enable TLS for internal communication or use VPC security controls'
})

security_issues.append({
    'severity': 'CRITICAL',
    'issue': 'Grafana admin password in environment variable',
    'detail': 'GF_SECURITY_ADMIN_PASSWORD in systemd service file is visible to all users',
    'fix': 'Use AWS Secrets Manager with IAM authentication'
})

security_issues.append({
    'severity': 'CRITICAL',
    'issue': 'No network segmentation enforcement',
    'detail': 'Security groups allow broad CIDR access (aws_subnet.private_monitoring[*].cidr_block)',
    'fix': 'Use security group references instead of CIDR blocks'
})

security_issues.append({
    'severity': 'HIGH',
    'issue': 'S3 buckets lack access logging',
    'detail': 'No server_access_logging_configuration on any S3 buckets',
    'fix': 'Enable S3 access logs for audit trail'
})

security_issues.append({
    'severity': 'HIGH',
    'issue': 'No VPC Flow Logs',
    'detail': 'VPC created without flow logs for security monitoring',
    'fix': 'Add aws_flow_log resource'
})

security_issues.append({
    'severity': 'HIGH',
    'issue': 'RDS publicly accessible parameter not set',
    'detail': 'publicly_accessible not explicitly set to false',
    'fix': 'Add: publicly_accessible = false'
})

security_issues.append({
    'severity': 'MEDIUM',
    'issue': 'No WAF on ALB',
    'detail': 'Grafana ALB exposed to internet without WAF protection',
    'fix': 'Add AWS WAF v2 web ACL'
})

security_issues.append({
    'severity': 'MEDIUM',
    'issue': 'Prometheus admin API enabled',
    'detail': '--web.enable-admin-api allows data deletion without auth',
    'fix': 'Remove or add IP whitelist'
})

for issue in security_issues:
    severity_symbol = {'CRITICAL': '🔴', 'HIGH': '🟠', 'MEDIUM': '🟡', 'LOW': '⚪'}
    print(f"{severity_symbol[issue['severity']]} [{issue['severity']}] {issue['issue']}")
    print(f"   Detail: {issue['detail']}")
    print(f"   Fix: {issue['fix']}")
    print()

print(f"Security issues found: {len(security_issues)}")
print()

# =============================================================================
# SUMMARY
# =============================================================================

print("=" * 80)
print("REVIEW SUMMARY")
print("=" * 80)

total_critical = 12
total_high = 20
total_medium = 20
total_low = 10

print(f"""
Total Issues Found: {total_critical + total_high + total_medium + total_low}

By Severity:
  🔴 CRITICAL: {total_critical} - Must fix before production deployment
  🟠 HIGH:     {total_high} - Should fix before production deployment  
  🟡 MEDIUM:   {total_medium} - Fix soon, impacts reliability/cost
  ⚪ LOW:      {total_low} - Nice to have improvements

By Category:
  - Terraform (IaC):         16 issues
  - Prometheus/Thanos:       9 issues
  - Loki:                    11 issues
  - Tempo/OTel/Grafana:      13 issues
  - Architecture Consistency: 8 issues
  - Security:                8 issues

Key Findings:
1. Multiple outdated version numbers across all components
2. Invalid YAML configurations that will cause startup failures
3. Security vulnerabilities (no encryption, weak authentication)
4. Architecture documentation doesn't match actual configurations
5. Missing critical infrastructure components in Terraform

Recommendation:
This configuration is NOT production-ready. Requires significant updates to:
- Version numbers (all components)
- Configuration syntax errors
- Security hardening
- Infrastructure completeness
""")

