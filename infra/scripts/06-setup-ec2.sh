#!/usr/bin/env bash
set -euo pipefail

# EC2 Instance Setup
# Creates: Security groups + 3 instances (API, UI, Monitor)
# Requires: EC2InstanceRole instance profile, key pair

REGION="${AWS_REGION:-ap-northeast-2}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
KEY_NAME="${KEY_NAME:-policy-pass-key}"
VPC_ID=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true \
    --query 'Vpcs[0].VpcId' --output text --region "${REGION}")

echo "=== Phase D: EC2 Instance Setup ==="
echo "VPC: ${VPC_ID}"
echo "Key pair: ${KEY_NAME}"

# --- Security Groups ---
echo ""
echo "[1/4] Creating security groups..."

create_sg() {
    local name=$1 desc=$2
    local sg_id
    sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${name}" "Name=vpc-id,Values=${VPC_ID}" \
        --query 'SecurityGroups[0].GroupId' --output text --region "${REGION}" 2>/dev/null)

    if [ "${sg_id}" = "None" ] || [ -z "${sg_id}" ]; then
        sg_id=$(aws ec2 create-security-group \
            --group-name "${name}" \
            --description "${desc}" \
            --vpc-id "${VPC_ID}" \
            --region "${REGION}" \
            --query GroupId --output text)
        echo "  -> Created ${name}: ${sg_id}"
    else
        echo "  -> ${name} already exists: ${sg_id}"
    fi
    echo "${sg_id}"
}

API_SG=$(create_sg "policy-pass-api-sg" "Policy Pass API server")
UI_SG=$(create_sg "policy-pass-ui-sg" "Policy Pass UI server")
MONITOR_SG=$(create_sg "policy-pass-monitor-sg" "Policy Pass monitoring server")

add_ingress() {
    local sg_id=$1 port=$2 cidr=$3 desc=$4
    aws ec2 authorize-security-group-ingress \
        --group-id "${sg_id}" \
        --protocol tcp \
        --port "${port}" \
        --cidr "${cidr}" \
        --region "${REGION}" \
        2>/dev/null || true
}

MY_IP=$(curl -s https://checkip.amazonaws.com)/32

add_ingress "${API_SG}" 22 "${MY_IP}" "SSH"
add_ingress "${API_SG}" 8080 "0.0.0.0/0" "API"

add_ingress "${UI_SG}" 22 "${MY_IP}" "SSH"
add_ingress "${UI_SG}" 8501 "0.0.0.0/0" "Streamlit"

add_ingress "${MONITOR_SG}" 22 "${MY_IP}" "SSH"
add_ingress "${MONITOR_SG}" 3000 "0.0.0.0/0" "Grafana"
add_ingress "${MONITOR_SG}" 9090 "${MY_IP}" "Prometheus"

# --- Get latest Amazon Linux 2023 AMI ---
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023.*-x86_64" "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text --region "${REGION}")
echo "AMI: ${AMI_ID}"

# --- User data scripts ---
API_USER_DATA=$(cat <<'USERDATA'
#!/bin/bash
yum update -y
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

cat > /home/ec2-user/deploy.sh << 'DEPLOY'
#!/bin/bash
REGION=ap-northeast-2
ACCOUNT_ID=$(curl -s http://169.254.169.254/latest/meta-data/identity-credentials/ec2/info | grep AccountId | cut -d'"' -f4)
ECR_REGISTRY=${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com
IMAGE=${ECR_REGISTRY}/rag-api:latest

aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}
docker pull ${IMAGE}
docker stop rag-api 2>/dev/null
docker rm rag-api 2>/dev/null
docker run -d --name rag-api -p 8080:8080 \
  -e DOWNLOAD_INDEX_FROM_S3=true \
  -e S3_BUCKET=rag-qa-index-${ACCOUNT_ID} \
  -e INDEX_S3_PREFIX=index/ \
  -e ENVIRONMENT=production \
  --restart unless-stopped \
  ${IMAGE}
DEPLOY
chmod +x /home/ec2-user/deploy.sh
chown ec2-user:ec2-user /home/ec2-user/deploy.sh
USERDATA
)

UI_USER_DATA=$(cat <<'USERDATA'
#!/bin/bash
yum update -y
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

cat > /home/ec2-user/deploy.sh << 'DEPLOY'
#!/bin/bash
REGION=ap-northeast-2
ACCOUNT_ID=$(curl -s http://169.254.169.254/latest/meta-data/identity-credentials/ec2/info | grep AccountId | cut -d'"' -f4)
ECR_REGISTRY=${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com
IMAGE=${ECR_REGISTRY}/rag-ui:latest

aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}
docker pull ${IMAGE}
docker stop rag-ui 2>/dev/null
docker rm rag-ui 2>/dev/null
docker run -d --name rag-ui -p 8501:8501 \
  -e API_BASE_URL=${API_BASE_URL:-http://localhost:8080} \
  --restart unless-stopped \
  ${IMAGE}
DEPLOY
chmod +x /home/ec2-user/deploy.sh
chown ec2-user:ec2-user /home/ec2-user/deploy.sh
USERDATA
)

MONITOR_USER_DATA=$(cat <<'USERDATA'
#!/bin/bash
yum update -y
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

mkdir -p /home/ec2-user/monitoring

cat > /home/ec2-user/monitoring/docker-compose.yml << 'COMPOSE'
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=policypass2026
    volumes:
      - grafana_data:/var/lib/grafana
    restart: unless-stopped

volumes:
  prometheus_data:
  grafana_data:
COMPOSE

cat > /home/ec2-user/monitoring/prometheus.yml << 'PROM'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
PROM

chown -R ec2-user:ec2-user /home/ec2-user/monitoring
USERDATA
)

# --- Launch instances ---
echo ""
echo "[2/4] Launching API instance (t3.medium)..."
API_INSTANCE=$(aws ec2 run-instances \
    --image-id "${AMI_ID}" \
    --instance-type t3.medium \
    --key-name "${KEY_NAME}" \
    --security-group-ids "${API_SG}" \
    --iam-instance-profile Name=EC2InstanceRole \
    --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":20,"VolumeType":"gp3"}}]' \
    --user-data "${API_USER_DATA}" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=policy-pass-api}]" \
    --region "${REGION}" \
    --query 'Instances[0].InstanceId' --output text)
echo "  -> API Instance: ${API_INSTANCE}"

echo "[3/4] Launching UI instance (t3.small)..."
UI_INSTANCE=$(aws ec2 run-instances \
    --image-id "${AMI_ID}" \
    --instance-type t3.small \
    --key-name "${KEY_NAME}" \
    --security-group-ids "${UI_SG}" \
    --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":10,"VolumeType":"gp3"}}]' \
    --user-data "${UI_USER_DATA}" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=policy-pass-ui}]" \
    --region "${REGION}" \
    --query 'Instances[0].InstanceId' --output text)
echo "  -> UI Instance: ${UI_INSTANCE}"

echo "[4/4] Launching Monitor instance (t3.small)..."
MONITOR_INSTANCE=$(aws ec2 run-instances \
    --image-id "${AMI_ID}" \
    --instance-type t3.small \
    --key-name "${KEY_NAME}" \
    --security-group-ids "${MONITOR_SG}" \
    --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":15,"VolumeType":"gp3"}}]' \
    --user-data "${MONITOR_USER_DATA}" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=policy-pass-monitor}]" \
    --region "${REGION}" \
    --query 'Instances[0].InstanceId' --output text)
echo "  -> Monitor Instance: ${MONITOR_INSTANCE}"

echo ""
echo "Waiting for instances to be running..."
aws ec2 wait instance-running \
    --instance-ids "${API_INSTANCE}" "${UI_INSTANCE}" "${MONITOR_INSTANCE}" \
    --region "${REGION}"

echo ""
echo "=== EC2 Setup Complete ==="
echo ""
echo "Instance IPs:"
for INST in "${API_INSTANCE}" "${UI_INSTANCE}" "${MONITOR_INSTANCE}"; do
    NAME=$(aws ec2 describe-tags --filters "Name=resource-id,Values=${INST}" "Name=key,Values=Name" \
        --query 'Tags[0].Value' --output text --region "${REGION}")
    IP=$(aws ec2 describe-instances --instance-ids "${INST}" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' --output text --region "${REGION}")
    echo "  ${NAME}: ${IP}"
done
echo ""
echo "Next: Allocate Elastic IPs (recommended) and run deploy.sh on each instance"
