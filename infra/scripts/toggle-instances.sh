#!/usr/bin/env bash
set -euo pipefail

# Start or stop all Policy Pass EC2 instances
# Usage: ./toggle-instances.sh start|stop

REGION="${AWS_REGION:-ap-northeast-2}"
ACTION="${1:-}"

if [ -z "${ACTION}" ] || { [ "${ACTION}" != "start" ] && [ "${ACTION}" != "stop" ]; }; then
    echo "Usage: $0 <start|stop>"
    echo ""
    echo "  start  - Start all Policy Pass instances"
    echo "  stop   - Stop all instances (saves compute cost, EBS still billed)"
    exit 1
fi

INSTANCE_NAMES=("policy-pass-api" "policy-pass-ui" "policy-pass-monitor")

echo "=== ${ACTION^} Policy Pass Instances ==="

for NAME in "${INSTANCE_NAMES[@]}"; do
    INSTANCE_ID=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=${NAME}" \
        --query 'Reservations[0].Instances[?State.Name!=`terminated`].InstanceId' \
        --output text --region "${REGION}" 2>/dev/null)

    if [ -z "${INSTANCE_ID}" ] || [ "${INSTANCE_ID}" = "None" ]; then
        echo "  ${NAME}: not found"
        continue
    fi

    if [ "${ACTION}" = "start" ]; then
        aws ec2 start-instances --instance-ids "${INSTANCE_ID}" --region "${REGION}" > /dev/null 2>&1
        echo "  ${NAME}: starting (${INSTANCE_ID})"
    else
        aws ec2 stop-instances --instance-ids "${INSTANCE_ID}" --region "${REGION}" > /dev/null 2>&1
        echo "  ${NAME}: stopping (${INSTANCE_ID})"
    fi
done

echo ""
if [ "${ACTION}" = "start" ]; then
    echo "Waiting for instances to be running..."
    sleep 10
    for NAME in "${INSTANCE_NAMES[@]}"; do
        IP=$(aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=${NAME}" "Name=instance-state-name,Values=running" \
            --query 'Reservations[0].Instances[0].PublicIpAddress' --output text \
            --region "${REGION}" 2>/dev/null)
        echo "  ${NAME}: ${IP:-pending...}"
    done
fi

echo ""
echo "Done."
