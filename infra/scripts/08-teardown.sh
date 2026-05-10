#!/usr/bin/env bash
set -euo pipefail

# Teardown all AWS resources in reverse order
# WARNING: This deletes ALL Policy Pass AWS resources

REGION="${AWS_REGION:-ap-northeast-2}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="rag-qa-index-${ACCOUNT_ID}"

echo "============================================="
echo "  WARNING: This will delete ALL resources"
echo "  Account: ${ACCOUNT_ID}"
echo "  Region: ${REGION}"
echo "============================================="
echo ""
read -r -p "Type 'DELETE' to confirm: " CONFIRM
if [ "${CONFIRM}" != "DELETE" ]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "=== Teardown Starting ==="

# 1. CloudWatch Alarms
echo "[1/7] Deleting CloudWatch alarms..."
aws cloudwatch delete-alarms \
    --alarm-names \
        policy-pass-api-cpu-high \
        policy-pass-ui-cpu-high \
        policy-pass-api-status-check \
        policy-pass-ui-status-check \
    --region "${REGION}" 2>/dev/null || true

# 2. EC2 Instances
echo "[2/7] Terminating EC2 instances..."
for NAME in policy-pass-api policy-pass-ui policy-pass-monitor; do
    INSTANCE_ID=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=${NAME}" "Name=instance-state-name,Values=running,stopped" \
        --query 'Reservations[0].Instances[0].InstanceId' --output text \
        --region "${REGION}" 2>/dev/null)
    if [ "${INSTANCE_ID}" != "None" ] && [ -n "${INSTANCE_ID}" ]; then
        aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}" --region "${REGION}" > /dev/null
        echo "  -> Terminated ${NAME} (${INSTANCE_ID})"
    fi
done

# 3. Elastic IPs
echo "[3/7] Releasing Elastic IPs..."
for ALLOC_ID in $(aws ec2 describe-addresses \
    --query 'Addresses[?Tags[?Key==`Name` && starts_with(Value, `policy-pass`)]].AllocationId' \
    --output text --region "${REGION}" 2>/dev/null); do
    aws ec2 release-address --allocation-id "${ALLOC_ID}" --region "${REGION}" 2>/dev/null || true
    echo "  -> Released ${ALLOC_ID}"
done

# 4. Security Groups (wait for instances to terminate)
echo "[4/7] Waiting for instances to terminate..."
sleep 30
for SG_NAME in policy-pass-api-sg policy-pass-ui-sg policy-pass-monitor-sg; do
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${SG_NAME}" \
        --query 'SecurityGroups[0].GroupId' --output text \
        --region "${REGION}" 2>/dev/null)
    if [ "${SG_ID}" != "None" ] && [ -n "${SG_ID}" ]; then
        aws ec2 delete-security-group --group-id "${SG_ID}" --region "${REGION}" 2>/dev/null || true
        echo "  -> Deleted ${SG_NAME}"
    fi
done

# 5. SSM Parameters
echo "[5/7] Deleting SSM parameters..."
for PARAM in $(aws ssm get-parameters-by-path --path /rag-qa/ --recursive \
    --query 'Parameters[].Name' --output text --region "${REGION}" 2>/dev/null); do
    aws ssm delete-parameter --name "${PARAM}" --region "${REGION}" 2>/dev/null || true
    echo "  -> Deleted ${PARAM}"
done

# 6. S3 Bucket
echo "[6/7] Deleting S3 bucket..."
aws s3 rm "s3://${BUCKET_NAME}" --recursive --region "${REGION}" 2>/dev/null || true
aws s3api delete-objects \
    --bucket "${BUCKET_NAME}" \
    --delete "$(aws s3api list-object-versions --bucket "${BUCKET_NAME}" \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' 2>/dev/null)" \
    --region "${REGION}" 2>/dev/null || true
aws s3 rb "s3://${BUCKET_NAME}" --region "${REGION}" 2>/dev/null || true
echo "  -> Deleted ${BUCKET_NAME}"

# 7. ECR Repositories
echo "[7/7] Deleting ECR repositories..."
for REPO in rag-api rag-ui; do
    aws ecr delete-repository \
        --repository-name "${REPO}" \
        --force \
        --region "${REGION}" 2>/dev/null || true
    echo "  -> Deleted ${REPO}"
done

# IAM (last)
echo ""
echo "Deleting IAM roles..."
for ROLE in EC2InstanceRole DataSyncS3Role; do
    # Detach managed policies
    for POLICY_ARN in $(aws iam list-attached-role-policies --role-name "${ROLE}" \
        --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
        aws iam detach-role-policy --role-name "${ROLE}" --policy-arn "${POLICY_ARN}" 2>/dev/null || true
    done
    # Delete inline policies
    for POLICY_NAME in $(aws iam list-role-policies --role-name "${ROLE}" \
        --query 'PolicyNames[]' --output text 2>/dev/null); do
        aws iam delete-role-policy --role-name "${ROLE}" --policy-name "${POLICY_NAME}" 2>/dev/null || true
    done
    # Remove from instance profile
    aws iam remove-role-from-instance-profile \
        --instance-profile-name "${ROLE}" --role-name "${ROLE}" 2>/dev/null || true
    aws iam delete-instance-profile --instance-profile-name "${ROLE}" 2>/dev/null || true
    # Delete role
    aws iam delete-role --role-name "${ROLE}" 2>/dev/null || true
    echo "  -> Deleted ${ROLE}"
done

echo ""
echo "=== Teardown Complete ==="
echo "All Policy Pass AWS resources have been deleted."
echo ""
echo "Remaining manual cleanup:"
echo "  - DataSync tasks/locations (if created)"
echo "  - Key pairs: aws ec2 delete-key-pair --key-name policy-pass-key"
