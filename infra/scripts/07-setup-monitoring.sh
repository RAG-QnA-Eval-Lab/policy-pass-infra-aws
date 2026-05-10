#!/usr/bin/env bash
set -euo pipefail

# CloudWatch Alarm Setup
# Creates alarms for API and UI EC2 instances

REGION="${AWS_REGION:-ap-northeast-2}"

echo "=== Phase E: CloudWatch Monitoring Setup ==="

# Find instance IDs by Name tag
get_instance_id() {
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$1" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' --output text \
        --region "${REGION}"
}

API_INSTANCE=$(get_instance_id "policy-pass-api")
UI_INSTANCE=$(get_instance_id "policy-pass-ui")

echo "API Instance: ${API_INSTANCE}"
echo "UI Instance: ${UI_INSTANCE}"

# --- CPU Alarms ---
create_cpu_alarm() {
    local name=$1 instance_id=$2 threshold=$3
    aws cloudwatch put-metric-alarm \
        --alarm-name "${name}" \
        --alarm-description "CPU utilization exceeds ${threshold}% for 10 minutes" \
        --metric-name CPUUtilization \
        --namespace AWS/EC2 \
        --statistic Average \
        --period 300 \
        --threshold "${threshold}" \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions "Name=InstanceId,Value=${instance_id}" \
        --region "${REGION}"
    echo "  -> ${name} created"
}

echo ""
echo "Creating CloudWatch alarms..."

create_cpu_alarm "policy-pass-api-cpu-high" "${API_INSTANCE}" 80
create_cpu_alarm "policy-pass-ui-cpu-high" "${UI_INSTANCE}" 80

# --- Status Check Alarm ---
create_status_alarm() {
    local name=$1 instance_id=$2
    aws cloudwatch put-metric-alarm \
        --alarm-name "${name}" \
        --alarm-description "Instance status check failed" \
        --metric-name StatusCheckFailed \
        --namespace AWS/EC2 \
        --statistic Maximum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 2 \
        --dimensions "Name=InstanceId,Value=${instance_id}" \
        --region "${REGION}"
    echo "  -> ${name} created"
}

create_status_alarm "policy-pass-api-status-check" "${API_INSTANCE}"
create_status_alarm "policy-pass-ui-status-check" "${UI_INSTANCE}"

echo ""
echo "=== Monitoring Setup Complete ==="
echo "Alarms created:"
echo "  - policy-pass-api-cpu-high (>80% for 10min)"
echo "  - policy-pass-ui-cpu-high (>80% for 10min)"
echo "  - policy-pass-api-status-check"
echo "  - policy-pass-ui-status-check"
echo ""
echo "View alarms:"
echo "  aws cloudwatch describe-alarms --alarm-name-prefix policy-pass --region ${REGION}"
