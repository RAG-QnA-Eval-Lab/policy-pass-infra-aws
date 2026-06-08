#!/usr/bin/env bash
set -euo pipefail

# EC2 Instance Setup
# Creates: VPC + Public Subnet + IGW + Security Groups + 2 instances (API, Monitor) + Elastic IPs
# Requires: EC2InstanceRole instance profile, key pair

REGION="${AWS_REGION:-ap-northeast-2}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
KEY_NAME="${KEY_NAME:-policy-pass-key}"
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR="10.0.1.0/24"
SUBNET_AZ="${REGION}a"

echo "=== Phase D: EC2 Instance Setup ==="
echo "Account: ${ACCOUNT_ID}"
echo "Region: ${REGION}"
echo "Key pair: ${KEY_NAME}"

# --- VPC ---
echo ""
echo "[1/6] Creating VPC..."

VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=policy-pass-vpc" \
    --query 'Vpcs[0].VpcId' --output text --region "${REGION}" 2>/dev/null)

if [ "${VPC_ID}" = "None" ] || [ -z "${VPC_ID}" ]; then
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block "${VPC_CIDR}" \
        --region "${REGION}" \
        --query 'Vpc.VpcId' --output text)
    aws ec2 create-tags --resources "${VPC_ID}" \
        --tags Key=Name,Value=policy-pass-vpc --region "${REGION}"
    aws ec2 modify-vpc-attribute --vpc-id "${VPC_ID}" \
        --enable-dns-support '{"Value":true}' --region "${REGION}"
    aws ec2 modify-vpc-attribute --vpc-id "${VPC_ID}" \
        --enable-dns-hostnames '{"Value":true}' --region "${REGION}"
    echo "  -> Created VPC: ${VPC_ID}"
else
    echo "  -> VPC already exists: ${VPC_ID}"
fi

# --- Internet Gateway ---
echo "[2/6] Creating Internet Gateway..."

IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=tag:Name,Values=policy-pass-igw" \
    --query 'InternetGateways[0].InternetGatewayId' --output text --region "${REGION}" 2>/dev/null)

if [ "${IGW_ID}" = "None" ] || [ -z "${IGW_ID}" ]; then
    IGW_ID=$(aws ec2 create-internet-gateway \
        --region "${REGION}" \
        --query 'InternetGateway.InternetGatewayId' --output text)
    aws ec2 create-tags --resources "${IGW_ID}" \
        --tags Key=Name,Value=policy-pass-igw --region "${REGION}"
    aws ec2 attach-internet-gateway \
        --internet-gateway-id "${IGW_ID}" --vpc-id "${VPC_ID}" --region "${REGION}"
    echo "  -> Created IGW: ${IGW_ID}"
else
    echo "  -> IGW already exists: ${IGW_ID}"
fi

# --- Public Subnet ---
echo "[3/6] Creating Public Subnet..."

SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=policy-pass-public-subnet" "Name=vpc-id,Values=${VPC_ID}" \
    --query 'Subnets[0].SubnetId' --output text --region "${REGION}" 2>/dev/null)

if [ "${SUBNET_ID}" = "None" ] || [ -z "${SUBNET_ID}" ]; then
    SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id "${VPC_ID}" \
        --cidr-block "${SUBNET_CIDR}" \
        --availability-zone "${SUBNET_AZ}" \
        --region "${REGION}" \
        --query 'Subnet.SubnetId' --output text)
    aws ec2 create-tags --resources "${SUBNET_ID}" \
        --tags Key=Name,Value=policy-pass-public-subnet --region "${REGION}"
    aws ec2 modify-subnet-attribute \
        --subnet-id "${SUBNET_ID}" --map-public-ip-on-launch --region "${REGION}"
    echo "  -> Created Subnet: ${SUBNET_ID} (${SUBNET_AZ})"
else
    echo "  -> Subnet already exists: ${SUBNET_ID}"
fi

# --- Route Table ---
RTB_ID=$(aws ec2 describe-route-tables \
    --filters "Name=tag:Name,Values=policy-pass-public-rtb" "Name=vpc-id,Values=${VPC_ID}" \
    --query 'RouteTables[0].RouteTableId' --output text --region "${REGION}" 2>/dev/null)

if [ "${RTB_ID}" = "None" ] || [ -z "${RTB_ID}" ]; then
    RTB_ID=$(aws ec2 create-route-table \
        --vpc-id "${VPC_ID}" --region "${REGION}" \
        --query 'RouteTable.RouteTableId' --output text)
    aws ec2 create-tags --resources "${RTB_ID}" \
        --tags Key=Name,Value=policy-pass-public-rtb --region "${REGION}"
    aws ec2 create-route \
        --route-table-id "${RTB_ID}" \
        --destination-cidr-block "0.0.0.0/0" \
        --gateway-id "${IGW_ID}" --region "${REGION}"
    aws ec2 associate-route-table \
        --route-table-id "${RTB_ID}" --subnet-id "${SUBNET_ID}" --region "${REGION}" > /dev/null
    echo "  -> Created Route Table: ${RTB_ID} (0.0.0.0/0 -> IGW)"
else
    echo "  -> Route Table already exists: ${RTB_ID}"
fi

# --- Security Groups ---
echo "[4/6] Creating Security Groups..."

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
        echo "  -> Created ${name}: ${sg_id}" >&2
    else
        echo "  -> ${name} already exists: ${sg_id}" >&2
    fi
    echo "${sg_id}"
}

API_SG=$(create_sg "policy-pass-api-sg" "Policy Pass API server")
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

# API SG: 8080 public, SSH admin only
add_ingress "${API_SG}" 22 "${MY_IP}" "SSH"
add_ingress "${API_SG}" 8080 "0.0.0.0/0" "API"

# Monitor SG: Grafana + Prometheus admin only
add_ingress "${MONITOR_SG}" 22 "${MY_IP}" "SSH"
add_ingress "${MONITOR_SG}" 3000 "${MY_IP}" "Grafana"
add_ingress "${MONITOR_SG}" 9090 "${MY_IP}" "Prometheus"

echo "  -> Security Group rules configured (SSH: ${MY_IP})"

# --- Get latest Amazon Linux 2023 AMI ---
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023.*-x86_64" "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text --region "${REGION}")
echo "  -> AMI: ${AMI_ID}"

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
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region ${REGION})
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
echo "[5/6] Launching EC2 instances..."

echo "  Launching API instance (t3.medium)..."
API_INSTANCE=$(aws ec2 run-instances \
    --image-id "${AMI_ID}" \
    --instance-type t3.medium \
    --key-name "${KEY_NAME}" \
    --security-group-ids "${API_SG}" \
    --subnet-id "${SUBNET_ID}" \
    --iam-instance-profile Name=EC2InstanceRole \
    --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":20,"VolumeType":"gp3"}}]' \
    --user-data "${API_USER_DATA}" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=policy-pass-api}]" \
    --region "${REGION}" \
    --query 'Instances[0].InstanceId' --output text)
echo "  -> API Instance: ${API_INSTANCE}"

echo "  Launching Monitor instance (t3.small)..."
MONITOR_INSTANCE=$(aws ec2 run-instances \
    --image-id "${AMI_ID}" \
    --instance-type t3.small \
    --key-name "${KEY_NAME}" \
    --security-group-ids "${MONITOR_SG}" \
    --subnet-id "${SUBNET_ID}" \
    --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":15,"VolumeType":"gp3"}}]' \
    --user-data "${MONITOR_USER_DATA}" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=policy-pass-monitor}]" \
    --region "${REGION}" \
    --query 'Instances[0].InstanceId' --output text)
echo "  -> Monitor Instance: ${MONITOR_INSTANCE}"

echo ""
echo "  Waiting for instances to be running..."
aws ec2 wait instance-running \
    --instance-ids "${API_INSTANCE}" "${MONITOR_INSTANCE}" \
    --region "${REGION}"

# --- Elastic IPs ---
echo ""
echo "[6/6] Allocating Elastic IPs..."

allocate_eip() {
    local instance_id=$1 name=$2
    local alloc_id
    alloc_id=$(aws ec2 allocate-address \
        --domain vpc --region "${REGION}" \
        --query 'AllocationId' --output text)
    aws ec2 create-tags --resources "${alloc_id}" \
        --tags Key=Name,Value="${name}" --region "${REGION}"
    aws ec2 associate-address \
        --allocation-id "${alloc_id}" \
        --instance-id "${instance_id}" \
        --region "${REGION}" > /dev/null
    local eip
    eip=$(aws ec2 describe-addresses --allocation-ids "${alloc_id}" \
        --query 'Addresses[0].PublicIp' --output text --region "${REGION}")
    echo "  -> ${name}: ${eip} (${alloc_id})"
}

allocate_eip "${API_INSTANCE}" "policy-pass-api-eip"
allocate_eip "${MONITOR_INSTANCE}" "policy-pass-monitor-eip"

echo ""
echo "=== EC2 Setup Complete ==="
echo ""
echo "Resources created:"
echo "  VPC: ${VPC_ID} (${VPC_CIDR})"
echo "  Subnet: ${SUBNET_ID} (${SUBNET_CIDR}, ${SUBNET_AZ})"
echo "  API SG: ${API_SG} (8080 public, SSH admin only)"
echo "  Monitor SG: ${MONITOR_SG} (3000/9090 admin only)"
echo ""
echo "Instance IPs:"
for INST in "${API_INSTANCE}" "${MONITOR_INSTANCE}"; do
    NAME=$(aws ec2 describe-tags --filters "Name=resource-id,Values=${INST}" "Name=key,Values=Name" \
        --query 'Tags[0].Value' --output text --region "${REGION}")
    IP=$(aws ec2 describe-instances --instance-ids "${INST}" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' --output text --region "${REGION}")
    echo "  ${NAME}: ${IP}"
done
echo ""
echo "Next steps:"
echo "  1. SSH: ssh -i ${KEY_NAME}.pem ec2-user@<IP>"
echo "  2. Deploy API: ./deploy.sh (on API instance)"
echo "  3. Start monitoring: cd monitoring && docker-compose up -d (on Monitor instance)"
