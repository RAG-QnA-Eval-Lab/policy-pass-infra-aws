#!/usr/bin/env bash
set -euo pipefail

# SSM Parameter Store Setup
# Creates parameters under /rag-qa/ prefix

REGION="${AWS_REGION:-ap-northeast-2}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=== Phase B: SSM Parameter Store Setup ==="

put_param() {
    local name=$1 type=$2 value=$3 desc=$4
    aws ssm put-parameter \
        --name "${name}" \
        --type "${type}" \
        --value "${value}" \
        --description "${desc}" \
        --overwrite \
        --region "${REGION}" \
        > /dev/null
    echo "  -> ${name} (${type})"
}

# Required parameters
echo "Creating parameters..."

if [ -n "${OPENAI_API_KEY:-}" ]; then
    put_param "/rag-qa/openai-api-key" "SecureString" "${OPENAI_API_KEY}" "OpenAI API Key"
else
    echo "  SKIP: /rag-qa/openai-api-key (OPENAI_API_KEY not set)"
fi

if [ -n "${MONGODB_URI:-}" ]; then
    put_param "/rag-qa/mongodb-uri" "SecureString" "${MONGODB_URI}" "MongoDB connection URI"
else
    echo "  SKIP: /rag-qa/mongodb-uri (MONGODB_URI not set)"
fi

put_param "/rag-qa/s3-bucket" "String" "rag-qa-index-${ACCOUNT_ID}" "FAISS index S3 bucket"
put_param "/rag-qa/index-s3-prefix" "String" "index/" "S3 prefix for FAISS index files"
put_param "/rag-qa/mongodb-db" "String" "${MONGODB_DB:-rag_youth_policy}" "MongoDB database name"
put_param "/rag-qa/embedding-model" "String" "openai/text-embedding-3-small" "Embedding model (must match GCP)"
put_param "/rag-qa/embedding-dim" "String" "1536" "Embedding dimensions"
put_param "/rag-qa/environment" "String" "${ENVIRONMENT:-production}" "Deployment environment"

echo ""
echo "=== SSM Setup Complete ==="
echo "Parameters created under /rag-qa/"
echo ""
echo "Verify:"
echo "  aws ssm get-parameters-by-path --path /rag-qa/ --region ${REGION}"
