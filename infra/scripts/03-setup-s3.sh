#!/usr/bin/env bash
set -euo pipefail

# S3 Bucket Setup for FAISS Index Storage
# Creates: rag-qa-index-{ACCOUNT_ID} with versioning + lifecycle

REGION="${AWS_REGION:-ap-northeast-2}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="rag-qa-index-${ACCOUNT_ID}"

echo "=== Phase A: S3 Bucket Setup ==="
echo "Bucket: ${BUCKET_NAME}"

aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}" \
    2>/dev/null || echo "  -> Bucket already exists"

aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled

aws s3api put-public-access-block \
    --bucket "${BUCKET_NAME}" \
    --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-lifecycle-configuration \
    --bucket "${BUCKET_NAME}" \
    --lifecycle-configuration '{
        "Rules": [{
            "ID": "delete-old-versions",
            "Status": "Enabled",
            "NoncurrentVersionExpiration": {"NoncurrentDays": 30},
            "Filter": {"Prefix": ""}
        }]
    }'

# Create index/ prefix
aws s3api put-object \
    --bucket "${BUCKET_NAME}" \
    --key "index/" \
    2>/dev/null || true

echo ""
echo "=== S3 Setup Complete ==="
echo "Bucket: s3://${BUCKET_NAME}/"
echo "  - Versioning: enabled"
echo "  - Public access: blocked"
echo "  - Lifecycle: old versions deleted after 30 days"
