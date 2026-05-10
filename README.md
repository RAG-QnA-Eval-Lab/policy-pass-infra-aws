# Policy Pass - AWS Online Serving Infrastructure

## Overview

이 레포지토리는 멀티클라우드 RAG QnA 시스템(Policy Pass)의 **AWS Online Serving Layer** 인프라를 관리한다.

**GCP**(Offline Pipeline)에서 데이터 수집, 청킹, 임베딩, FAISS 인덱스 빌드를 수행하고, **AWS**(Online Serving)에서 해당 인덱스를 로드하여 실시간 검색, LLM 응답 생성, UI 서빙을 담당한다.

```
GCP (Offline Pipeline)                    AWS (Online Serving)
========================                   ========================
Data Crawling                              FastAPI Backend (EC2)
Chunking & Embedding                       Frontend (EC2, React/Vue/TS)
FAISS Index Build                          FAISS Index Load & Search
GCS Storage                    ─────>      S3 (via DataSync)
Airflow Orchestration                      LLM Call & Response
MongoDB (Metadata)                         Monitoring (Grafana + Prometheus)
```

---

## Architecture

![RAG QA Pipeline - Multicloud Architecture](docs/architecture.png)

### AWS Services

| Service | Resource | Purpose |
|---------|----------|---------|
| **EC2** | `policy-pass-api` (t3.medium) | FastAPI backend, FAISS search, LLM call |
| **EC2** | `policy-pass-ui` (t3.small) | Frontend (React/Vue/TS) |
| **EC2** | `policy-pass-monitor` (t3.small) | Grafana + Prometheus |
| **ECR** | `rag-api`, `rag-ui` | Docker image registry |
| **S3** | `rag-qa-index-{ACCOUNT_ID}` | FAISS index storage |
| **DataSync** | GCS → S3 task | FAISS index sync from GCP |
| **SSM** | `/rag-qa/*` | Secret & config management |
| **CloudWatch** | CPU, status alarms | Monitoring & alerting |

---

## Repository Structure

```
policy-pass-infra-aws/
├── .github/workflows/
│   ├── deploy-monitoring.yml       # Monitoring: SCP configs → restart stack (활성)
│   ├── aws/                        # AWS API/UI 워크플로 (비활성, 필요시 활성화)
│   │   ├── deploy-api.yml
│   │   └── deploy-ui.yml
│   └── gcp/                        # GCP 워크플로 아카이빙 (실행 안 됨)
│       ├── ci.yml
│       ├── deploy-api.yml
│       ├── deploy-ui.yml
│       ├── deploy-jobs.yml
│       └── deploy-airflow.yml
├── infra/scripts/
│   ├── 01-setup-iam.sh             # IAM roles (EC2, DataSync)
│   ├── 02-setup-ecr.sh             # ECR repositories
│   ├── 03-setup-s3.sh              # S3 bucket + versioning
│   ├── 04-setup-datasync.sh        # DataSync GCS → S3
│   ├── 05-setup-ssm.sh             # SSM Parameter Store
│   ├── 06-setup-ec2.sh             # EC2 instances + security groups
│   ├── 07-setup-monitoring.sh      # CloudWatch alarms
│   ├── 08-teardown.sh              # Destroy all resources
│   └── toggle-instances.sh         # Start/stop instances
├── services/
│   ├── api/
│   │   ├── Dockerfile              # API container (python:3.11-slim)
│   │   ├── .env.example            # API env vars (LLM keys, MongoDB, S3)
│   │   └── requirements.txt        # API dependencies
│   └── ui/
│       ├── Dockerfile              # UI container (node:20-alpine)
│       ├── .env.example            # UI env vars (API URL)
│       └── package.json            # UI dependencies (React + Vite + TS)
├── monitoring/
│   ├── docker-compose.yml          # Prometheus + Grafana stack
│   └── prometheus.yml              # Prometheus scrape config
├── docs/
│   ├── aws-infrastructure-plan.md
│   ├── aws-console-guide.md
│   ├── team-discussion-items.md
│   ├── multicloud_architecture_summary.md
│   └── plan.md
├── .env.example                    # Infra/CI env vars (AWS, EC2, DataSync)
└── .gitignore
```

---

## Quick Start

### Prerequisites

- AWS CLI v2 configured (`aws configure`)
- Docker installed
- Node.js 20+ (UI build)
- AWS account with billing enabled (DataSync, EC2 require billing)
- GCS HMAC keys (for DataSync)

### Phase A: Foundation

```bash
cd infra/scripts

# 1. IAM Roles
./01-setup-iam.sh

# 2. ECR Repositories
./02-setup-ecr.sh

# 3. S3 Bucket
./03-setup-s3.sh
```

### Phase B: Data Sync + Secrets

```bash
# 4. DataSync (requires GCS HMAC keys)
export GCS_HMAC_ACCESS_KEY="..."
export GCS_HMAC_SECRET_KEY="..."
./04-setup-datasync.sh

# 5. SSM Parameters
export OPENAI_API_KEY="sk-..."
export MONGODB_URI="mongodb://34.47.80.98:27017"
./05-setup-ssm.sh
```

### Phase C: Application Build

```bash
# Push initial images to ECR
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2

aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# API image
docker build -f services/api/Dockerfile -t rag-api services/api
docker tag rag-api:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/rag-api:initial
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/rag-api:initial

# UI image
docker build -f services/ui/Dockerfile -t rag-ui services/ui
docker tag rag-ui:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/rag-ui:initial
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/rag-ui:initial
```

### Phase D: EC2 Instances

```bash
# Create key pair first (AWS Console or CLI)
aws ec2 create-key-pair --key-name policy-pass-key --query 'KeyMaterial' \
  --output text > policy-pass-key.pem
chmod 400 policy-pass-key.pem

# Launch 3 instances
./06-setup-ec2.sh
```

### Phase E: Monitoring

```bash
./07-setup-monitoring.sh
```

---

## CI/CD Pipeline

```
main branch push
    │
    ├── deploy-api.yml (src/api/**, Dockerfile changes)
    │   └── Docker build → ECR push → SSH deploy to EC2
    │
    └── deploy-ui.yml (src/ui/**, Dockerfile.ui changes)
        └── Docker build → ECR push → SSH deploy to EC2
```

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `EC2_API_HOST` | API EC2 public IP (Elastic IP) |
| `EC2_UI_HOST` | UI EC2 public IP (Elastic IP) |
| `EC2_SSH_KEY` | SSH private key (`policy-pass-key.pem` contents) |

### Cross-Repo Deployment

GCP Airflow DAG can trigger AWS deployment via `repository_dispatch`:

```python
# In GCP Airflow DAG
@task()
def trigger_aws_deploy():
    import requests
    requests.post(
        "https://api.github.com/repos/{owner}/policy-pass-infra-aws/dispatches",
        headers={"Authorization": f"token {GITHUB_TOKEN}"},
        json={"event_type": "deploy-api"}
    )
```

---

## Operations

### Start/Stop Instances (Cost Saving)

```bash
# Stop all instances (saves compute cost)
./infra/scripts/toggle-instances.sh stop

# Start all instances
./infra/scripts/toggle-instances.sh start
```

### Manual Deploy

```bash
ssh -i policy-pass-key.pem ec2-user@{EC2_IP}
./deploy.sh
```

### Full Teardown

```bash
./infra/scripts/08-teardown.sh
```

---

## Cost Estimate

| Service | Monthly Cost | Notes |
|---------|-------------|-------|
| EC2 API (t3.medium) | ~$30 | On-demand, stopped when unused |
| EC2 UI (t3.small) | ~$15 | On-demand, stopped when unused |
| EC2 Monitor (t3.small) | ~$15 | On-demand, stopped when unused |
| ECR | ~$1 | Image storage |
| S3 | < $1 | FAISS index only |
| DataSync | ~$0.04/GB | Per transfer |
| SSM | Free | Standard tier |
| CloudWatch | ~$1-3 | Alarms + logs |
| **Total (always on)** | **~$63/month** | |
| **Total (dev, stopped)** | **~$5-10/month** | EBS + storage only |

---

## FAISS Index Flow

```
GCP                                         AWS
─────────────────────                       ─────────────────────
Airflow DAG (02:00 KST)                    EC2 API Container
    │                                           │
    ├── collect_policies                        ├── S3 download
    ├── rebuild_index                           │   (faiss.index +
    │   └── FAISS Build                         │    metadata.pkl)
    │       └── GCS Upload                      │
    │           (index/faiss.index)              ├── FAISS Load (2GB)
    │           (index/metadata.pkl)             │
    │                                           └── Real-time Search
    └── sync_index_to_s3
        └── DataSync: GCS → S3
```

---

## Team Responsibilities

### Infra Owner (Daehyun)
- AWS infrastructure setup & maintenance
- CI/CD pipeline management
- GCP data pipeline (separate repo)
- DataSync, monitoring, cost management

### Team Members (Application)
- FastAPI API development (`src/api/`)
- Frontend development (`src/ui/`, React/Vue/TS)
- RAG pipeline logic (retrieval, generation)
- Prompt engineering & evaluation

---

## Related Repositories

| Repository | Owner | Purpose |
|-----------|-------|---------|
| `RAG-QA-pipeline-GCP` | Daehyun | GCP offline pipeline (crawling, indexing, Airflow) |
| `policy-pass-infra-aws` | Daehyun | **This repo** - AWS infrastructure |
| Team app repo | Team members | Application code (FastAPI + React/Vue/TS) |

---

## Documentation

- [AWS Infrastructure Plan](docs/aws-infrastructure-plan.md) - Detailed architecture decisions
- [AWS Console Guide](docs/aws-console-guide.md) - Step-by-step console setup
- [Team Discussion Items](docs/team-discussion-items.md) - Pending team decisions
- [Multicloud Architecture](multicloud_architecture_summary.md) - GCP/AWS role separation
