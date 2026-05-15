#!/usr/bin/env bash
set -euo pipefail

# S3 + CloudFront Setup for Frontend (React SPA)
# Creates: S3 UI bucket, CloudFront OAC, CloudFront Distribution, S3 bucket policy

REGION="${AWS_REGION:-ap-northeast-2}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
UI_BUCKET="policy-pass-ui-${ACCOUNT_ID}"

echo "=== Phase D: S3 + CloudFront Setup ==="
echo "Account: ${ACCOUNT_ID}"
echo "UI Bucket: ${UI_BUCKET}"

# --- S3 Bucket ---
echo ""
echo "[1/4] Creating S3 bucket for frontend..."

aws s3api create-bucket \
    --bucket "${UI_BUCKET}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}" \
    2>/dev/null || echo "  -> Bucket already exists"

aws s3api put-public-access-block \
    --bucket "${UI_BUCKET}" \
    --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "  -> ${UI_BUCKET} created (public access blocked)"

# --- CloudFront OAC ---
echo ""
echo "[2/4] Creating CloudFront Origin Access Control..."

OAC_ID=$(aws cloudfront list-origin-access-controls \
    --query "OriginAccessControlList.Items[?Name=='policy-pass-ui-oac'].Id | [0]" \
    --output text 2>/dev/null)

if [ "${OAC_ID}" = "None" ] || [ -z "${OAC_ID}" ]; then
    OAC_ID=$(aws cloudfront create-origin-access-control \
        --origin-access-control-config '{
            "Name": "policy-pass-ui-oac",
            "Description": "OAC for Policy Pass UI S3 bucket",
            "SigningProtocol": "sigv4",
            "SigningBehavior": "always",
            "OriginAccessControlOriginType": "s3"
        }' \
        --query 'OriginAccessControl.Id' --output text)
    echo "  -> Created OAC: ${OAC_ID}"
else
    echo "  -> OAC already exists: ${OAC_ID}"
fi

# --- CloudFront Distribution ---
echo ""
echo "[3/4] Creating CloudFront Distribution..."

EXISTING_DIST=$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?Origins.Items[?Id=='policy-pass-ui-origin']].Id | [0]" \
    --output text 2>/dev/null)

if [ "${EXISTING_DIST}" = "None" ] || [ -z "${EXISTING_DIST}" ]; then
    S3_ORIGIN="${UI_BUCKET}.s3.${REGION}.amazonaws.com"

    DIST_CONFIG=$(cat <<EOF
{
    "CallerReference": "policy-pass-ui-$(date +%s)",
    "Comment": "Policy Pass Frontend (React SPA)",
    "Enabled": true,
    "Origins": {
        "Quantity": 1,
        "Items": [{
            "Id": "policy-pass-ui-origin",
            "DomainName": "${S3_ORIGIN}",
            "OriginAccessControlId": "${OAC_ID}",
            "S3OriginConfig": {
                "OriginAccessIdentity": ""
            }
        }]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "policy-pass-ui-origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": {
            "Quantity": 2,
            "Items": ["GET", "HEAD"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"]
            }
        },
        "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
        "Compress": true
    },
    "DefaultRootObject": "index.html",
    "CustomErrorResponses": {
        "Quantity": 2,
        "Items": [
            {
                "ErrorCode": 403,
                "ResponsePagePath": "/index.html",
                "ResponseCode": "200",
                "ErrorCachingMinTTL": 0
            },
            {
                "ErrorCode": 404,
                "ResponsePagePath": "/index.html",
                "ResponseCode": "200",
                "ErrorCachingMinTTL": 0
            }
        ]
    },
    "PriceClass": "PriceClass_200",
    "ViewerCertificate": {
        "CloudFrontDefaultCertificate": true,
        "MinimumProtocolVersion": "TLSv1.2_2021"
    }
}
EOF
    )

    DIST_ID=$(aws cloudfront create-distribution \
        --distribution-config "${DIST_CONFIG}" \
        --query 'Distribution.Id' --output text)
    DIST_DOMAIN=$(aws cloudfront get-distribution \
        --id "${DIST_ID}" \
        --query 'Distribution.DomainName' --output text)
    echo "  -> Created Distribution: ${DIST_ID}"
    echo "  -> Domain: ${DIST_DOMAIN}"
else
    DIST_ID="${EXISTING_DIST}"
    DIST_DOMAIN=$(aws cloudfront get-distribution \
        --id "${DIST_ID}" \
        --query 'Distribution.DomainName' --output text)
    echo "  -> Distribution already exists: ${DIST_ID} (${DIST_DOMAIN})"
fi

# --- S3 Bucket Policy ---
echo ""
echo "[4/4] Setting S3 bucket policy (CloudFront OAC only)..."

BUCKET_POLICY=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowCloudFrontOAC",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudfront.amazonaws.com"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${UI_BUCKET}/*",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${DIST_ID}"
                }
            }
        }
    ]
}
EOF
)

aws s3api put-bucket-policy \
    --bucket "${UI_BUCKET}" \
    --policy "${BUCKET_POLICY}"

echo "  -> Bucket policy set (CloudFront only access)"

echo ""
echo "=== CloudFront Setup Complete ==="
echo ""
echo "Resources:"
echo "  S3 Bucket: ${UI_BUCKET}"
echo "  CloudFront Distribution: ${DIST_ID}"
echo "  CloudFront Domain: https://${DIST_DOMAIN}"
echo "  OAC: ${OAC_ID}"
echo ""
echo "Next steps:"
echo "  1. Set GitHub Secret UI_S3_BUCKET=${UI_BUCKET}"
echo "  2. Set GitHub Secret CLOUDFRONT_DISTRIBUTION_ID=${DIST_ID}"
echo "  3. Set GitHub Secret API_BASE_URL=http://<API_ELASTIC_IP>:8080"
echo "  4. Add CORS to FastAPI: allow_origins=['https://${DIST_DOMAIN}']"
