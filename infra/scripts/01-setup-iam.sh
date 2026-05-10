#!/usr/bin/env bash
set -euo pipefail

# IAM Role Setup for Policy Pass AWS Infrastructure
# Creates: EC2InstanceRole, DataSyncS3Role

REGION="${AWS_REGION:-ap-northeast-2}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="rag-qa-index-${ACCOUNT_ID}"

echo "=== Phase A: IAM Role Setup ==="
echo "Account ID: ${ACCOUNT_ID}"
echo "Region: ${REGION}"

# --- EC2InstanceRole ---
echo "[1/2] Creating EC2InstanceRole..."

aws iam create-role \
    --role-name EC2InstanceRole \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "ec2.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }' \
    --description "EC2 instance role for Policy Pass API/UI servers" \
    2>/dev/null || echo "  -> EC2InstanceRole already exists, skipping creation"

aws iam attach-role-policy \
    --role-name EC2InstanceRole \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly \
    2>/dev/null || true

aws iam put-role-policy \
    --role-name EC2InstanceRole \
    --policy-name EC2InstancePolicy \
    --policy-document "{
        \"Version\": \"2012-10-17\",
        \"Statement\": [
            {
                \"Sid\": \"S3ReadIndex\",
                \"Effect\": \"Allow\",
                \"Action\": [\"s3:GetObject\", \"s3:ListBucket\"],
                \"Resource\": [
                    \"arn:aws:s3:::${BUCKET_NAME}\",
                    \"arn:aws:s3:::${BUCKET_NAME}/*\"
                ]
            },
            {
                \"Sid\": \"SSMReadParams\",
                \"Effect\": \"Allow\",
                \"Action\": [\"ssm:GetParameter\", \"ssm:GetParametersByPath\"],
                \"Resource\": \"arn:aws:ssm:${REGION}:${ACCOUNT_ID}:parameter/rag-qa/*\"
            }
        ]
    }"

aws iam create-instance-profile \
    --instance-profile-name EC2InstanceRole \
    2>/dev/null || echo "  -> Instance profile already exists"

aws iam add-role-to-instance-profile \
    --instance-profile-name EC2InstanceRole \
    --role-name EC2InstanceRole \
    2>/dev/null || echo "  -> Role already attached to instance profile"

echo "  -> EC2InstanceRole created"

# --- DataSyncS3Role ---
echo "[2/2] Creating DataSyncS3Role..."

aws iam create-role \
    --role-name DataSyncS3Role \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "datasync.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }' \
    --description "DataSync role for GCS to S3 FAISS index transfer" \
    2>/dev/null || echo "  -> DataSyncS3Role already exists, skipping creation"

aws iam put-role-policy \
    --role-name DataSyncS3Role \
    --policy-name DataSyncS3Policy \
    --policy-document "{
        \"Version\": \"2012-10-17\",
        \"Statement\": [{
            \"Sid\": \"S3DataSync\",
            \"Effect\": \"Allow\",
            \"Action\": [
                \"s3:GetObject\",
                \"s3:PutObject\",
                \"s3:DeleteObject\",
                \"s3:ListBucket\",
                \"s3:GetBucketLocation\"
            ],
            \"Resource\": [
                \"arn:aws:s3:::${BUCKET_NAME}\",
                \"arn:aws:s3:::${BUCKET_NAME}/*\"
            ]
        }]
    }"

echo "  -> DataSyncS3Role created"

echo ""
echo "=== IAM Setup Complete ==="
echo "Roles created:"
echo "  - EC2InstanceRole (ECR pull + S3 read + SSM read)"
echo "  - DataSyncS3Role (S3 read/write for DataSync)"
