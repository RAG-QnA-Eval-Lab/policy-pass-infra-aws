#!/usr/bin/env bash
set -euo pipefail

# Teardown all AWS resources in reverse order
# WARNING: This deletes ALL Policy Pass AWS resources

REGION="${AWS_REGION:-ap-northeast-2}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
INDEX_BUCKET="rag-qa-index-${ACCOUNT_ID}"
UI_BUCKET="policy-pass-ui-${ACCOUNT_ID}"

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
echo "[1/10] Deleting CloudWatch alarms..."
aws cloudwatch delete-alarms \
    --alarm-names \
        policy-pass-api-cpu-high \
        policy-pass-monitor-cpu-high \
        policy-pass-api-status-check \
        policy-pass-monitor-status-check \
    --region "${REGION}" 2>/dev/null || true

# 2. CloudFront Distribution
echo "[2/10] Disabling and deleting CloudFront distribution..."
DIST_ID=$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?Origins.Items[?Id=='policy-pass-ui-origin']].Id | [0]" \
    --output text 2>/dev/null)
if [ -n "${DIST_ID}" ] && [ "${DIST_ID}" != "None" ]; then
    ETAG=$(aws cloudfront get-distribution-config --id "${DIST_ID}" --query 'ETag' --output text)
    CONFIG=$(aws cloudfront get-distribution-config --id "${DIST_ID}" --query 'DistributionConfig')
    DISABLED_CONFIG=$(echo "${CONFIG}" | sed 's/"Enabled": true/"Enabled": false/')
    aws cloudfront update-distribution --id "${DIST_ID}" --if-match "${ETAG}" \
        --distribution-config "${DISABLED_CONFIG}" > /dev/null 2>&1 || true
    echo "  -> Distribution ${DIST_ID} disabled (manual deletion may be needed after propagation)"
else
    echo "  -> No CloudFront distribution found"
fi

# 3. CloudFront OAC
echo "[3/10] Deleting CloudFront OAC..."
OAC_ID=$(aws cloudfront list-origin-access-controls \
    --query "OriginAccessControlList.Items[?Name=='policy-pass-ui-oac'].Id | [0]" \
    --output text 2>/dev/null)
if [ -n "${OAC_ID}" ] && [ "${OAC_ID}" != "None" ]; then
    OAC_ETAG=$(aws cloudfront get-origin-access-control --id "${OAC_ID}" --query 'ETag' --output text)
    aws cloudfront delete-origin-access-control --id "${OAC_ID}" --if-match "${OAC_ETAG}" 2>/dev/null || true
    echo "  -> Deleted OAC: ${OAC_ID}"
else
    echo "  -> No OAC found"
fi

# 4. EC2 Instances
echo "[4/10] Terminating EC2 instances..."
for NAME in policy-pass-api policy-pass-monitor; do
    INSTANCE_ID=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=${NAME}" "Name=instance-state-name,Values=running,stopped" \
        --query 'Reservations[0].Instances[0].InstanceId' --output text \
        --region "${REGION}" 2>/dev/null)
    if [ "${INSTANCE_ID}" != "None" ] && [ -n "${INSTANCE_ID}" ]; then
        aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}" --region "${REGION}" > /dev/null
        echo "  -> Terminated ${NAME} (${INSTANCE_ID})"
    fi
done

# 5. Elastic IPs
echo "[5/10] Releasing Elastic IPs..."
for ALLOC_ID in $(aws ec2 describe-addresses \
    --query 'Addresses[?Tags[?Key==`Name` && starts_with(Value, `policy-pass`)]].AllocationId' \
    --output text --region "${REGION}" 2>/dev/null); do
    aws ec2 release-address --allocation-id "${ALLOC_ID}" --region "${REGION}" 2>/dev/null || true
    echo "  -> Released ${ALLOC_ID}"
done

# 6. Security Groups (wait for instances to terminate)
echo "[6/10] Waiting for instances to terminate..."
sleep 30
for SG_NAME in policy-pass-api-sg policy-pass-monitor-sg; do
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${SG_NAME}" \
        --query 'SecurityGroups[0].GroupId' --output text \
        --region "${REGION}" 2>/dev/null)
    if [ "${SG_ID}" != "None" ] && [ -n "${SG_ID}" ]; then
        aws ec2 delete-security-group --group-id "${SG_ID}" --region "${REGION}" 2>/dev/null || true
        echo "  -> Deleted ${SG_NAME}"
    fi
done

# 7. VPC (Subnet, Route Table, IGW)
echo "[7/10] Deleting VPC resources..."
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=policy-pass-vpc" \
    --query 'Vpcs[0].VpcId' --output text --region "${REGION}" 2>/dev/null)
if [ -n "${VPC_ID}" ] && [ "${VPC_ID}" != "None" ]; then
    # Route table associations
    for ASSOC_ID in $(aws ec2 describe-route-tables \
        --filters "Name=tag:Name,Values=policy-pass-public-rtb" \
        --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' \
        --output text --region "${REGION}" 2>/dev/null); do
        aws ec2 disassociate-route-table --association-id "${ASSOC_ID}" --region "${REGION}" 2>/dev/null || true
    done
    # Route table
    RTB_ID=$(aws ec2 describe-route-tables \
        --filters "Name=tag:Name,Values=policy-pass-public-rtb" \
        --query 'RouteTables[0].RouteTableId' --output text --region "${REGION}" 2>/dev/null)
    if [ -n "${RTB_ID}" ] && [ "${RTB_ID}" != "None" ]; then
        aws ec2 delete-route-table --route-table-id "${RTB_ID}" --region "${REGION}" 2>/dev/null || true
        echo "  -> Deleted route table"
    fi
    # Subnet
    SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name,Values=policy-pass-public-subnet" \
        --query 'Subnets[0].SubnetId' --output text --region "${REGION}" 2>/dev/null)
    if [ -n "${SUBNET_ID}" ] && [ "${SUBNET_ID}" != "None" ]; then
        aws ec2 delete-subnet --subnet-id "${SUBNET_ID}" --region "${REGION}" 2>/dev/null || true
        echo "  -> Deleted subnet"
    fi
    # IGW
    IGW_ID=$(aws ec2 describe-internet-gateways \
        --filters "Name=tag:Name,Values=policy-pass-igw" \
        --query 'InternetGateways[0].InternetGatewayId' --output text --region "${REGION}" 2>/dev/null)
    if [ -n "${IGW_ID}" ] && [ "${IGW_ID}" != "None" ]; then
        aws ec2 detach-internet-gateway --internet-gateway-id "${IGW_ID}" --vpc-id "${VPC_ID}" --region "${REGION}" 2>/dev/null || true
        aws ec2 delete-internet-gateway --internet-gateway-id "${IGW_ID}" --region "${REGION}" 2>/dev/null || true
        echo "  -> Deleted IGW"
    fi
    # VPC
    aws ec2 delete-vpc --vpc-id "${VPC_ID}" --region "${REGION}" 2>/dev/null || true
    echo "  -> Deleted VPC: ${VPC_ID}"
else
    echo "  -> No policy-pass-vpc found"
fi

# 8. SSM Parameters
echo "[8/10] Deleting SSM parameters..."
for PARAM in $(aws ssm get-parameters-by-path --path /rag-qa/ --recursive \
    --query 'Parameters[].Name' --output text --region "${REGION}" 2>/dev/null); do
    aws ssm delete-parameter --name "${PARAM}" --region "${REGION}" 2>/dev/null || true
    echo "  -> Deleted ${PARAM}"
done

# 9. S3 Buckets
echo "[9/10] Deleting S3 buckets..."
for BUCKET in "${INDEX_BUCKET}" "${UI_BUCKET}"; do
    if aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
        aws s3 rm "s3://${BUCKET}" --recursive 2>/dev/null || true
        aws s3api delete-objects \
            --bucket "${BUCKET}" \
            --delete "$(aws s3api list-object-versions --bucket "${BUCKET}" \
            --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' 2>/dev/null)" \
            2>/dev/null || true
        aws s3 rb "s3://${BUCKET}" 2>/dev/null || true
        echo "  -> Deleted ${BUCKET}"
    else
        echo "  -> ${BUCKET} not found"
    fi
done

# 10. ECR Repositories
echo "[10/10] Deleting ECR repositories..."
aws ecr delete-repository \
    --repository-name "rag-api" \
    --force \
    --region "${REGION}" 2>/dev/null || true
echo "  -> Deleted rag-api"

# IAM (last)
echo ""
echo "Deleting IAM roles..."
for ROLE in EC2InstanceRole DataSyncS3Role; do
    for POLICY_ARN in $(aws iam list-attached-role-policies --role-name "${ROLE}" \
        --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
        aws iam detach-role-policy --role-name "${ROLE}" --policy-arn "${POLICY_ARN}" 2>/dev/null || true
    done
    for POLICY_NAME in $(aws iam list-role-policies --role-name "${ROLE}" \
        --query 'PolicyNames[]' --output text 2>/dev/null); do
        aws iam delete-role-policy --role-name "${ROLE}" --policy-name "${POLICY_NAME}" 2>/dev/null || true
    done
    aws iam remove-role-from-instance-profile \
        --instance-profile-name "${ROLE}" --role-name "${ROLE}" 2>/dev/null || true
    aws iam delete-instance-profile --instance-profile-name "${ROLE}" 2>/dev/null || true
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
echo "  - CloudFront distribution (if still propagating, retry after ~15min)"
