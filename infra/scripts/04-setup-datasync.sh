#!/usr/bin/env bash
set -euo pipefail

# DataSync Setup: GCS -> S3 FAISS Index Transfer
# Requires: GCS HMAC keys, S3 bucket, DataSyncS3Role

REGION="${AWS_REGION:-ap-northeast-2}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="rag-qa-index-${ACCOUNT_ID}"
GCS_BUCKET="${GCS_BUCKET:-rag-qna-eval-data}"

echo "=== Phase B: DataSync Setup ==="

if [ -z "${GCS_HMAC_ACCESS_KEY:-}" ] || [ -z "${GCS_HMAC_SECRET_KEY:-}" ]; then
    echo "ERROR: GCS_HMAC_ACCESS_KEY and GCS_HMAC_SECRET_KEY must be set"
    echo ""
    echo "Generate HMAC keys in GCP Console:"
    echo "  Cloud Storage > Settings > Interoperability > Create HMAC key"
    exit 1
fi

# Source location: GCS (S3-compatible)
echo "[1/3] Creating source location (GCS)..."
SOURCE_ARN=$(aws datasync create-location-object-storage \
    --server-hostname storage.googleapis.com \
    --server-protocol HTTPS \
    --server-port 443 \
    --bucket-name "${GCS_BUCKET}" \
    --subdirectory "/index/" \
    --access-key "${GCS_HMAC_ACCESS_KEY}" \
    --secret-key "${GCS_HMAC_SECRET_KEY}" \
    --region "${REGION}" \
    --query LocationArn --output text)
echo "  -> Source: ${SOURCE_ARN}"

# Destination location: S3
echo "[2/3] Creating destination location (S3)..."
DATASYNC_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/DataSyncS3Role"
DEST_ARN=$(aws datasync create-location-s3 \
    --s3-bucket-arn "arn:aws:s3:::${BUCKET_NAME}" \
    --s3-config "BucketAccessRoleArn=${DATASYNC_ROLE_ARN}" \
    --subdirectory "/index/" \
    --region "${REGION}" \
    --query LocationArn --output text)
echo "  -> Destination: ${DEST_ARN}"

# DataSync task
echo "[3/3] Creating DataSync task..."
TASK_ARN=$(aws datasync create-task \
    --source-location-arn "${SOURCE_ARN}" \
    --destination-location-arn "${DEST_ARN}" \
    --name "gcs-to-s3-faiss-index" \
    --options '{
        "TransferMode": "CHANGED",
        "VerifyMode": "POINT_IN_TIME_CONSISTENT",
        "OverwriteMode": "ALWAYS",
        "PreserveDeletedFiles": "PRESERVE",
        "Atime": "BEST_EFFORT",
        "Mtime": "PRESERVE"
    }' \
    --region "${REGION}" \
    --query TaskArn --output text)
echo "  -> Task: ${TASK_ARN}"

echo ""
echo "=== DataSync Setup Complete ==="
echo "Task ARN: ${TASK_ARN}"
echo ""
echo "To run manually:"
echo "  aws datasync start-task-execution --task-arn ${TASK_ARN}"
echo ""
echo "Save this Task ARN for Airflow DAG integration:"
echo "  export DATASYNC_TASK_ARN=${TASK_ARN}"
