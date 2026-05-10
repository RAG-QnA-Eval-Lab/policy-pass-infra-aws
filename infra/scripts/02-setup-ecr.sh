#!/usr/bin/env bash
set -euo pipefail

# ECR Repository Setup
# Creates: rag-api, rag-ui repositories with lifecycle policies

REGION="${AWS_REGION:-ap-northeast-2}"

echo "=== Phase A: ECR Repository Setup ==="

LIFECYCLE_POLICY='{
    "rules": [{
        "rulePriority": 1,
        "description": "Keep only 5 untagged images",
        "selection": {
            "tagStatus": "untagged",
            "countType": "imageCountMoreThan",
            "countNumber": 5
        },
        "action": {"type": "expire"}
    }]
}'

for REPO in rag-api rag-ui; do
    echo "Creating ECR repository: ${REPO}..."

    aws ecr create-repository \
        --repository-name "${REPO}" \
        --region "${REGION}" \
        --image-scanning-configuration scanOnPush=true \
        2>/dev/null || echo "  -> ${REPO} already exists"

    aws ecr put-lifecycle-policy \
        --repository-name "${REPO}" \
        --lifecycle-policy-text "${LIFECYCLE_POLICY}" \
        --region "${REGION}"

    echo "  -> ${REPO} created with lifecycle policy"
done

echo ""
echo "=== ECR Setup Complete ==="
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Registry: ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
echo "Repositories: rag-api, rag-ui"
