# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AWS Online Serving infrastructure for **Policy Pass**, a multicloud RAG QnA system (Korean youth policy chatbot). GCP handles the offline data pipeline (crawling, chunking, embedding, FAISS index build); this repo manages the AWS side that serves real-time search, LLM responses, and the frontend.

This is an **infrastructure-only repo** — no application source code lives here. Application code is in a separate team repo deployed via CI/CD pipelines defined here.

## Architecture

- **EC2 instances** (all in `ap-northeast-2`):
  - `policy-pass-api` (t3.medium) — FastAPI backend container, FAISS search, LLM calls (port 8080)
  - `policy-pass-monitor` (t3.small) — Prometheus + Grafana stack (ports 9090, 3000)
- **UI deployment** — S3 static hosting + CloudFront CDN (migrated from EC2 container). The React SPA is built in CI and synced to S3 bucket `policy-pass-ui-{ACCOUNT_ID}`. CloudFront handles HTTPS, caching, and SPA routing (403/404 → `/index.html`).
- **ECR** — `rag-api` image repo (plus legacy `rag-ui`)
- **S3** — `rag-qa-index-{ACCOUNT_ID}` for FAISS index files synced from GCP
- **SSM Parameter Store** — Secrets under `/rag-qa/*`
- **DataSync** — GCS-to-S3 incremental transfer using GCS HMAC keys
- **CloudWatch** — CPU and status check alarms

FAISS index flow: GCP Airflow DAG builds index daily → GCS → DataSync → S3 → EC2 API container downloads at startup.

## Key Commands

### Infrastructure setup (sequential, from `infra/scripts/`)
```bash
./01-setup-iam.sh          # IAM roles: EC2InstanceRole, DataSyncS3Role
./02-setup-ecr.sh          # ECR repos
./03-setup-s3.sh           # S3 bucket for FAISS indexes
./04-setup-datasync.sh     # DataSync GCS->S3 (needs GCS_HMAC_ACCESS_KEY, GCS_HMAC_SECRET_KEY)
./05-setup-ssm.sh          # SSM params (needs OPENAI_API_KEY, MONGODB_URI)
./06-setup-ec2.sh          # EC2 instances + security groups (needs KEY_NAME)
./07-setup-monitoring.sh   # CloudWatch alarms
./08-teardown.sh           # Destroy ALL resources (interactive confirmation)
./09-setup-cloudfront.sh   # S3 UI bucket + CloudFront distribution + OAC
```

### Operations
```bash
./infra/scripts/toggle-instances.sh start   # Start EC2 instances
./infra/scripts/toggle-instances.sh stop    # Stop all (saves compute cost)
```

### Docker builds
```bash
docker build -f services/api/Dockerfile -t rag-api services/api
docker build -f services/ui/Dockerfile -t rag-ui services/ui   # legacy, UI now deploys via S3
```

### UI development
```bash
cd services/ui
npm ci
npm run dev       # Vite dev server
npm run build     # tsc + vite build
npm run lint      # ESLint
```

## Infrastructure Patterns

- **No IaC tool** — Managed via idempotent bash scripts (AWS CLI), not Terraform/CDK. Scripts are numbered for sequential execution order.
- **All scripts default** `AWS_REGION=ap-northeast-2` and derive `ACCOUNT_ID` from `aws sts get-caller-identity`.
- **Elastic IPs** are assigned to both EC2 instances (API: `3.35.151.233`, Monitor: `3.35.247.34`). IPs persist across instance stop/start.
- **Security groups** allow SSH from `0.0.0.0/0` (for CI/CD); service ports are open to `0.0.0.0/0`. Node-exporter (9100) on API SG is restricted to Monitor EIP only.
- **EC2 user data** scripts install Docker and create a `deploy.sh` on each instance that pulls from ECR and runs the container.
- **Naming convention**: AWS resources use `policy-pass-*` or `rag-qa-*` prefixes.
- **Env var templates** are split per service: root `.env.example` (infra/CI), `services/api/.env.example` (backend), `services/ui/.env.example` (frontend).

## CI/CD

GitHub Actions workflows in `.github/workflows/aws/`:
- **`deploy-api.yml`** — Triggered on `services/api/**` changes, `repository_dispatch`, or manual. Builds Docker → pushes to ECR → SSH deploys to EC2.
- **`deploy-ui.yml`** — Triggered on `services/ui/**` changes. Builds React SPA → syncs to S3 (hashed assets get `immutable` cache headers, `index.html` gets `no-cache`) → invalidates CloudFront.
- **`deploy-monitoring.yml`** — SCPs monitoring configs to EC2 and restarts docker-compose.

Cross-repo trigger: GCP Airflow DAG can invoke `repository_dispatch` to trigger AWS deployment after index rebuild.

Required GitHub Secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `EC2_API_HOST`, `EC2_SSH_KEY`, `UI_S3_BUCKET`, `CLOUDFRONT_DISTRIBUTION_ID`, `API_BASE_URL`.

GCP workflows under `.github/workflows/gcp/` are archived and not active.

## Related Repos

- `RAG-QA-pipeline-GCP` — GCP offline pipeline (crawling, indexing, Airflow DAGs, MongoDB)
- Team application repo — FastAPI API + React frontend source code
