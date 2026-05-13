# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AWS Online Serving infrastructure for **Policy Pass**, a multicloud RAG QnA system (Korean youth policy chatbot). GCP handles offline data pipeline (crawling, chunking, embedding, FAISS index build); this repo manages the AWS side that loads FAISS indexes and serves real-time search, LLM responses, and the frontend.

This is an **infrastructure-only repo** — no application source code lives here. Application code is developed in a separate team repo and deployed via the CI/CD pipelines defined here.

## Architecture

- **3 EC2 instances** (all in `ap-northeast-2`):
  - `policy-pass-api` (t3.medium) — FastAPI backend container, FAISS search, LLM calls (port 8080)
  - `policy-pass-ui` (t3.small) — React/Vite/TS frontend container (port 3000)
  - `policy-pass-monitor` (t3.small) — Prometheus + Grafana stack (ports 9090, 3000)
- **ECR** — Two repos: `rag-api`, `rag-ui`
- **S3** — `rag-qa-index-{ACCOUNT_ID}` bucket for FAISS index files synced from GCP via DataSync
- **SSM Parameter Store** — Secrets under `/rag-qa/*` (OpenAI key, MongoDB URI, S3 bucket)
- **DataSync** — GCS-to-S3 incremental transfer using GCS HMAC keys (S3-compatible API)
- **CloudWatch** — CPU and status check alarms

FAISS index flow: GCP Airflow DAG builds index daily -> GCS -> DataSync -> S3 -> EC2 API container downloads at startup.

## Key Commands

### Infrastructure setup (sequential, from `infra/scripts/`)
```bash
./01-setup-iam.sh          # IAM roles: EC2InstanceRole, DataSyncS3Role
./02-setup-ecr.sh          # ECR repos: rag-api, rag-ui
./03-setup-s3.sh           # S3 bucket with versioning
./04-setup-datasync.sh     # DataSync GCS->S3 (needs GCS_HMAC_ACCESS_KEY, GCS_HMAC_SECRET_KEY)
./05-setup-ssm.sh          # SSM params (needs OPENAI_API_KEY, MONGODB_URI)
./06-setup-ec2.sh          # 3 EC2 instances + security groups (needs KEY_NAME)
./07-setup-monitoring.sh   # CloudWatch alarms
./08-teardown.sh           # Destroy ALL resources (interactive confirmation)
```

### Operations
```bash
./infra/scripts/toggle-instances.sh start   # Start all 3 instances
./infra/scripts/toggle-instances.sh stop    # Stop all (saves compute cost)
```

### Docker builds
```bash
# API
docker build -f services/api/Dockerfile -t rag-api services/api

# UI
docker build -f services/ui/Dockerfile -t rag-ui services/ui
```

### UI development
```bash
cd services/ui
npm ci
npm run dev       # Vite dev server
npm run build     # tsc + vite build
npm run lint      # ESLint
```

### Monitoring (on monitor EC2)
```bash
cd ~/monitoring
docker-compose up -d
```

## Infrastructure Patterns

- **No IaC tool** — Infrastructure is managed via idempotent bash scripts (AWS CLI), not Terraform/CDK. Scripts are numbered for sequential execution order.
- **All scripts default** `AWS_REGION=ap-northeast-2` and derive `ACCOUNT_ID` from `aws sts get-caller-identity`.
- **Security groups** restrict SSH to the deployer's current IP (`checkip.amazonaws.com`); service ports are open to `0.0.0.0/0`.
- **EC2 user data** scripts install Docker and create a `deploy.sh` on each instance that pulls from ECR and runs the container.
- **Naming convention**: All AWS resources use `policy-pass-*` or `rag-qa-*` prefixes.

## CI/CD

Three GitHub Actions workflows:
- `.github/workflows/aws/deploy-api.yml` — Triggered on `services/api/**` changes, `repository_dispatch`, or manual. Builds Docker -> pushes to ECR -> SSH deploys to EC2.
- `.github/workflows/aws/deploy-ui.yml` — Same pattern for the UI service.
- `.github/workflows/deploy-monitoring.yml` — SCPs monitoring configs to EC2 and restarts the docker-compose stack.

Cross-repo trigger: GCP Airflow DAG can invoke `repository_dispatch` to trigger AWS deployment after index rebuild.

Required GitHub Secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `EC2_API_HOST`, `EC2_UI_HOST`, `EC2_MONITOR_HOST`, `EC2_SSH_KEY`.

## Related Repos

- `RAG-QA-pipeline-GCP` — GCP offline pipeline (crawling, indexing, Airflow DAGs, MongoDB)
- Team application repo — FastAPI API + React frontend source code
