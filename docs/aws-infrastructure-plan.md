# AWS Online Serving 인프라 구축 계획서

> **최종 수정일**: 2026-05-17  
> **담당자**: Daehyun Kim (인프라)  
> **관련 문서**: [멀티클라우드 아키텍처 정리본](../multicloud_architecture_summary.md)

---

## 1. 개요

본 문서는 멀티클라우드 RAG QnA 시스템(청년정책 챗봇)의 **AWS Online Serving Layer** 인프라 구축 계획을 정리한 것이다.

GCP 측(Offline Data Pipeline: 크롤링 → 청킹 → 임베딩 → FAISS 인덱스 빌드)은 이미 구축 완료되었으며, 이 문서는 AWS 측 인프라만을 다룬다.

### 최종 아키텍처 요약

#### AWS 영역

AWS는 **온라인 서빙 레이어**를 담당한다.

* **Route 53**
  * 사용자 도메인 요청을 CloudFront로 라우팅

* **CloudFront**
  * 정적 프론트엔드 콘텐츠를 캐싱 및 배포
  * S3 Front-End Static 버킷과 연결

* **S3 (Front-End Static)**
  * React SPA 정적 파일 저장
  * CloudFront를 통해 사용자에게 제공

* **EC2 (BE, RAG Serving)**
  * Public Subnet에 위치 (Security Group 강화로 보안 확보)
  * FastAPI 기반 API 서버
  * LangChain 기반 RAG 오케스트레이션 수행
  * S3 Index Bucket에서 FAISS 인덱스를 로드하여 메모리 상에서 검색 수행
  * 외부 LLM API 호출 후 응답 생성

* **EC2 (Monitoring)**
  * Prometheus + Grafana 기반 모니터링 서버
  * 서비스 상태 및 ETL 관련 메트릭 시각화

* **S3 (Index Bucket)**
  * GCP에서 생성된 FAISS 인덱스 파일 저장
  * DataSync를 통해 GCS에서 동기화

* **ECR**
  * 백엔드 API Docker 이미지 저장소

#### GCP 영역

GCP는 **오프라인 데이터 파이프라인**을 담당한다.

* **Airflow**: ETL 오케스트레이션 (크롤링 → 청킹 → 임베딩 → FAISS 인덱스 빌드)
* **GCS**: 생성된 FAISS 인덱스 파일 저장
* **MongoDB VM**: 정책 메타데이터 저장

---

### 흐름별 정리

#### 1. 페이지 요청

사용자의 웹 페이지 요청은 **Route 53**을 거쳐 **CloudFront**로 전달된다.
CloudFront가 **S3 (Front-End Static)** 에 저장된 React 정적 파일을 사용자에게 제공한다.

```
User → Route 53 → CloudFront → S3 (Front-End Static)
```

#### 2. API 요청

브라우저에서 백엔드 API 요청이 발생하면, **Public Subnet의 EC2 (BE, RAG Serving)** 로 직접 전달된다.
백엔드가 검색 및 LLM 추론을 수행한 뒤 응답을 반환한다.

```
Browser API Request → EC2 (BE, RAG Serving)
```

#### 3. RAG 서빙 흐름

백엔드 EC2가 **S3 (Index Bucket)** 에서 FAISS 인덱스를 로드한다.
질의가 들어오면 FAISS를 메모리에서 검색하고, 검색 결과를 기반으로 LangChain + FastAPI가 프롬프트를 구성한다.
외부 LLM API를 호출하고, 추론 결과를 사용자에게 반환한다.

```
EC2(BE) → FAISS(in-memory) → LLM Inference → Response
```

#### 4. 배포 흐름

개발자가 GitHub Repository에 코드를 Push하면 GitHub Actions가 실행된다.
백엔드 이미지는 **ECR**에 Push된 뒤 EC2에 배포되고, 프론트엔드는 빌드 후 **S3**에 동기화되어 **CloudFront**를 통해 제공된다.

```
Developer → GitHub Push → GitHub Actions
  ├── BE: Docker Build → ECR Push → EC2 Deploy (SSH)
  └── FE: vite build → S3 Sync → CloudFront Invalidation
```

#### 5. 데이터 파이프라인 흐름 (GCP → AWS)

GCP Airflow가 매일 ETL을 수행하여 FAISS 인덱스를 빌드한다.
**DataSync (Enhanced Mode)** 가 GCS의 인덱스를 **S3 (Index Bucket)** 으로 동기화한다.
AWS 백엔드 EC2가 해당 인덱스를 로드하여 사용한다.

```
GCP Airflow → GCS → AWS DataSync → S3 (Index Bucket) → EC2 (BE)
```

#### 6. 모니터링 흐름

**EC2 (Monitoring)** 에서 Prometheus + Grafana를 운영한다.
개발자는 Grafana 대시보드를 통해 서비스 상태, ETL 상태, 인프라 상태를 확인한다.

```
Developer → Monitoring Dashboard (Grafana)
```

---

### 한 줄 요약

이 아키텍처는 **AWS에서 프론트엔드 서빙과 백엔드 RAG API를 운영하고**, **GCP에서 생성한 FAISS 인덱스를 DataSync로 AWS S3에 동기화한 뒤**, **백엔드 EC2가 이를 로드하여 검색과 LLM 응답 생성을 수행하는 구조**이다.

### 역할 분리

- **본인(Daehyun)**: AWS 인프라 구축 및 운영 (IAM, ECR, S3, CloudFront, DataSync, EC2, CI/CD, 모니터링)
- **팀원들**: 애플리케이션 코드 개발 (FastAPI API, React/TypeScript UI, RAG 로직)

---

## 2. 핵심 의사결정

| 항목 | 선택 | 대안 | 선택 근거 |
|------|------|------|-----------|
| API 컴퓨팅 | **EC2** (t3.medium) | App Runner, ECS | 학생 프로젝트 규모에서 직관적, SSH 디버깅 가능, Docker 기반 배포 |
| FAISS 인덱스 전송 | **AWS DataSync** | boto3 직접 업로드 | GB 단위 인덱스 대응, 증분 전송, 체크섬 검증, 자동 재시도 |
| 시크릿 관리 | **SSM Parameter Store** | Secrets Manager | 무료 (Secrets Manager는 시크릿당 $0.40/월) |
| IaC 방식 | **CLI 셋업 스크립트** | Terraform | 학생 프로젝트 규모(~10개 리소스), 학습 목적 |
| 크로스 레포 CI/CD | **repository_dispatch** | 수동 트리거 | GCP 레포에서 자동으로 AWS 배포 트리거 가능 |
| 프론트엔드 호스팅 | **S3 + CloudFront** | EC2 Docker | React+Vite SPA는 정적 빌드 결과물 → S3 정적 호스팅이 최적. EC2 대비 월 ~$14.5 절감, 서버 관리 불필요, CDN 엣지 캐싱으로 성능 향상 |
| BE 네트워크 | **Public Subnet + SG 강화** | Private Subnet + API Gateway HTTP API | Private Subnet은 NAT Gateway($44/월) + NLB($17/월) + VPC Link($7/월) = 월 +$68 추가. 현재 예산($48.5) 대비 140% 증가로 과도함. Security Group 강화로 비용 $0으로 동등한 보안 확보 가능 |

---

## 3. 생성할 파일 목록

### 3.1 인프라 셋업 스크립트 (`infra/scripts/`)

| # | 파일명 | 역할 |
|---|--------|------|
| 1 | `01-setup-iam.sh` | IAM 역할 생성: EC2 인스턴스 역할 (ECR + S3 + SSM 읽기) |
| 2 | `02-setup-ecr.sh` | ECR 레포지토리: `rag-api` (수명주기: 이미지 5개 유지) |
| 3 | `03-setup-s3.sh` | FAISS 인덱스용 S3 버킷 (`rag-qa-index-{ACCOUNT_ID}`) + 버전 관리 |
| 4 | `04-setup-datasync.sh` | DataSync: GCS 소스(HMAC) → S3 대상, 증분 전송 태스크 |
| 5 | `05-setup-ssm.sh` | SSM Parameter Store: OPENAI_API_KEY, MONGODB_URI, S3_BUCKET 등 |
| 6 | `06-setup-ec2.sh` | EC2 인스턴스 2개: API (t3.medium), Monitor (t3.small) |
| 7 | `07-setup-monitoring.sh` | CloudWatch 알람: CPU 사용률, 상태 체크 |
| 8 | `08-teardown.sh` | 전체 리소스 역순 정리 |
| 9 | `09-setup-cloudfront.sh` | S3 버킷 + CloudFront Distribution (프론트엔드 호스팅) |
| 10 | `toggle-instances.sh` | EC2 인스턴스 시작/중지 (비용 절감) |

### 3.2 CI/CD 워크플로우 (`.github/workflows/aws/`)

| 파일명 | 역할 |
|--------|------|
| `deploy-api.yml` | API Docker build → ECR push → SSH deploy to EC2. 트리거: main 푸시 + repository_dispatch |
| `deploy-ui.yml` | `vite build` → S3 sync → CloudFront invalidation. 트리거: main 푸시 |

### 3.3 애플리케이션 (`services/`)

| 파일명 | 역할 |
|--------|------|
| `services/api/Dockerfile` | API 컨테이너: python:3.11-slim, 포트 8080 |
| `services/api/requirements.txt` | API Python 의존성 |
| `services/ui/package.json` | UI 의존성: React 19 + Vite + TypeScript |
| `.env.example` | 필수 환경변수 템플릿 |

---

## 4. 인프라 아키텍처 상세

### 4.1 IAM 역할 (Phase A) ✅ 완료

```
EC2InstanceRole
├── Trust: ec2.amazonaws.com
└── Policies:
    ├── AmazonEC2ContainerRegistryReadOnly (ECR pull 권한)
    ├── S3: GetObject, ListBucket (인덱스 버킷)
    └── SSM: GetParameter, GetParametersByPath (/rag-qa/*)

DataSyncS3Role
├── Trust: datasync.amazonaws.com
└── Inline Policy:
    └── S3: GetObject, PutObject, DeleteObject, ListBucket (인덱스 버킷)

GitHub Actions IAM User
└── Policies:
    ├── ECR: GetAuthorizationToken, BatchCheckLayerAvailability, PutImage, ...
    ├── S3: PutObject, DeleteObject, ListBucket (UI 버킷)
    └── CloudFront: CreateInvalidation
```

### 4.2 ECR 레지스트리 (Phase A) ✅ 완료

```
rag-api  ← API 컨테이너 이미지

수명주기 정책: untagged 이미지 5개 초과 시 자동 삭제
이미지 태그 형식: {github.sha}

※ rag-ui ECR 레포는 불필요 (프론트엔드는 S3 + CloudFront로 서빙)
```

### 4.3 S3 버킷 (Phase A) ✅ 완료

```
rag-qa-index-${ACCOUNT_ID}
├── 버전 관리: 활성화
├── 수명주기: 이전 버전 30일 후 삭제
└── 구조:
    └── index/
        ├── faiss.index      (FAISS 벡터 인덱스)
        └── metadata.json    (정책 메타데이터)
```

### 4.4 DataSync (Phase B) ✅ 완료

GCS에서 S3로 FAISS 인덱스를 증분 전송한다. GCS의 S3 호환 API(HMAC 키)를 활용한다.

```
Source Location:
├── 유형: Object Storage (S3-compatible)
├── ServerHostname: storage.googleapis.com
├── BucketName: ${GCS_BUCKET}
├── Subdirectory: /index/
├── AccessKey/SecretKey: GCS HMAC 키
└── AgentArns: [] (클라우드 간 직접 전송, 에이전트 불필요)

Destination Location:
├── 유형: S3
├── S3BucketArn: arn:aws:s3:::rag-qa-index-${ACCOUNT_ID}
├── Subdirectory: /index/
└── S3Config.BucketAccessRoleArn: DataSyncS3Role ARN

Task 설정:
├── TransferMode: CHANGED (변경분만 전송)
├── VerifyMode: POINT_IN_TIME_CONSISTENT (체크섬 검증)
└── OverwriteMode: ALWAYS
```

### 4.5 SSM Parameter Store (Phase B) ✅ 완료

> **구축일**: 2026-05-16  
> **스크립트**: `infra/scripts/05-setup-ssm.sh`

```
/rag-qa/openai-api-key     (SecureString) ← OpenAI API 키 (GCP .env에서 가져옴)
/rag-qa/mongodb-uri         (SecureString) ← MongoDB 연결 문자열 (GCP MongoDB: 34.47.80.98)
/rag-qa/mongodb-db          (String)       ← "rag_youth_policy"
/rag-qa/s3-bucket           (String)       ← "rag-qa-index-355206939988"
/rag-qa/index-s3-prefix     (String)       ← "index/"
/rag-qa/embedding-model     (String)       ← "openai/text-embedding-3-small"
/rag-qa/embedding-dim       (String)       ← "1536"
/rag-qa/environment         (String)       ← "production"
```

검증: `aws ssm get-parameters-by-path --path /rag-qa/ --region ap-northeast-2`

### 4.6 EC2 인스턴스 (Phase D) ✅ 완료

> **구축일**: 2026-05-16  
> **스크립트**: `infra/scripts/06-setup-ec2.sh`

| 리소스 | ID / 값 |
|--------|---------|
| VPC | vpc-02bdbd24195a7a8f8 (10.0.0.0/16) |
| Subnet | subnet-08684e9866f7952aa (ap-northeast-2a) |
| API Instance | i-0fe59710ffcf75aa1 (t3.medium) |
| API Elastic IP | 3.35.151.233 (eipalloc-07cba6bd9ee9b838a) |
| Monitor Instance | i-08ba9acd4db6d29ce (t3.small) |
| Monitor Elastic IP | 3.35.247.34 (eipalloc-0519c2b41e0344fe0) |
| API SG | sg-054aab8ad977f8944 |
| Monitor SG | sg-06a8a422dcd94c507 |

EC2는 **Public Subnet**에 배치한다. Private Subnet + API Gateway 구성은 NAT Gateway($44/월) + NLB($17/월) + VPC Link($7/월)로 월 +$68 추가 비용이 발생하여 현재 규모에서는 과도하다. 대신 Security Group 강화로 동등한 보안을 확보한다.

#### API 서버

```
인스턴스: t3.medium (2vCPU, 4GB)
이미지: Amazon Linux 2023
EBS: 20GB gp3
네트워크: Public Subnet (Elastic IP 할당)
IAM 역할: EC2InstanceRole (S3 + SSM + ECR 읽기)
배포: Docker (ECR에서 pull)
환경변수:
├── S3_BUCKET
├── INDEX_S3_PREFIX
└── DOWNLOAD_INDEX_FROM_S3=true
```

#### Monitor 서버

```
인스턴스: t3.small (2vCPU, 2GB)
EBS: 15GB gp3
네트워크: Public Subnet (Elastic IP 할당)
스택: docker-compose (Prometheus + Grafana)
```

#### Security Group 강화 (Private Subnet 대체)

Private Subnet 대신 Security Group을 강화하여 비용 $0으로 보안을 확보한다.

**policy-pass-api-sg:**

| 방향 | 포트 | 소스 | 설명 |
|------|------|------|------|
| Inbound | 8080 | 0.0.0.0/0 | API (브라우저에서 직접 호출) |
| Inbound | 22 | 0.0.0.0/0 | SSH (CI/CD 배포용) |
| Inbound | 9100 | 3.35.247.34/32 | Node Exporter (모니터링 서버 Elastic IP만 허용) |
| Outbound | All | 0.0.0.0/0 | OpenAI API, GCP MongoDB, ECR, S3 등 |

**policy-pass-monitor-sg:**

| 방향 | 포트 | 소스 | 설명 |
|------|------|------|------|
| Inbound | 3000 | 0.0.0.0/0 | Grafana |
| Inbound | 9090 | 0.0.0.0/0 | Prometheus |
| Inbound | 22 | 0.0.0.0/0 | SSH (CI/CD 배포용) |

**추가 보안 조치:**

| 조치 | 효과 | 비용 |
|------|------|------|
| SSH → SSM Session Manager 전환 | 22번 포트 완전 폐쇄, SSH 키 관리 불필요 | $0 |
| Network ACL 추가 | Subnet 레벨 이중 방화벽 | $0 |
| fail2ban 설치 | 무차별 대입 공격 차단 | $0 |

#### Private Subnet 전환 시점

아래 조건 중 2개 이상 해당 시 전환 검토:

- 인스턴스 2대 이상으로 스케일 (ALB 비용 분산 가능)
- Auto Scaling Group 도입
- 월 예산 $120 이상 확보
- PCI-DSS, HIPAA 등 컴플라이언스 요구사항 발생

### 4.7 프론트엔드 — S3 + CloudFront (Phase D) ✅ 완료

> **구축일**: 2026-05-16

| 리소스 | 값 |
|--------|---|
| S3 버킷 | policy-pass-ui-355206939988 |
| Distribution ID | E2HV6ON5OEZJTS |
| 도메인 | dnoi7zxhwqqog.cloudfront.net |
| OAC | EH87KH1N3ZNH6 (policy-pass-ui-oac) |
| 에러 페이지 | 403/404 → /index.html (200) |
| 기본 루트 객체 | index.html |
| WAF | 기본 보호 포함 (무료) |

EC2 Docker 컨테이너 대신 S3 정적 호스팅 + CloudFront CDN을 사용한다.
React + Vite + TypeScript SPA는 `vite build`로 정적 파일(`dist/`)을 생성하므로 서버가 필요 없다.

#### S3 버킷

```
버킷명: policy-pass-ui-${ACCOUNT_ID}
리전: ap-northeast-2
설정:
├── 퍼블릭 액세스: 차단 (CloudFront OAC 통해서만 접근)
├── 정적 웹 호스팅: 비활성화 (CloudFront가 직접 서빙)
├── 버전 관리: 비활성화 (빌드 결과물은 덮어쓰기)
└── 수명주기: 없음
```

#### CloudFront Distribution

```
Origin:
├── S3 Origin
│   ├── 도메인: policy-pass-ui-${ACCOUNT_ID}.s3.ap-northeast-2.amazonaws.com
│   └── OAC (Origin Access Control): CloudFront만 S3 접근 허용

기본 캐시 동작:
├── Viewer Protocol Policy: redirect-to-https
├── 캐시 정책: CachingOptimized
├── 압축: Gzip + Brotli 활성화
└── TTL: 기본 86400초 (24시간)

SPA 라우팅 처리:
├── 커스텀 에러 응답: 403/404 → /index.html (HTTP 200)
└── 이유: React Router 클라이언트 사이드 라우팅 지원

가격 등급: PriceClass_200 (아시아 + 미주 + 유럽)

SSL:
├── ACM 인증서 (us-east-1, CloudFront 필수)
├── 커스텀 도메인 등록 시 적용, 없으면 기본 도메인 사용
└── 최소 TLS: TLSv1.2_2021
```

#### S3 버킷 정책

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontOAC",
      "Effect": "Allow",
      "Principal": { "Service": "cloudfront.amazonaws.com" },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::policy-pass-ui-${ACCOUNT_ID}/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${DISTRIBUTION_ID}"
        }
      }
    }
  ]
}
```

#### 캐시 전략

| 파일 유형 | Cache-Control | 이유 |
|-----------|--------------|------|
| JS/CSS/이미지 (해시 포함) | `max-age=31536000, immutable` | Vite가 파일명에 해시 포함 → 영구 캐싱 |
| `index.html` | `no-cache, must-revalidate` | 항상 최신 버전 로드 (새 JS/CSS 참조) |
| `*.json` (manifest 등) | `no-cache, must-revalidate` | 설정 파일은 항상 최신 |

#### API 연동 (CORS)

UI와 API가 별도 도메인이므로 FastAPI에 CORS 설정이 필요하다:

```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://${CF_DOMAIN}"],
    allow_methods=["*"],
    allow_headers=["*"],
)
```

빌드 시 `VITE_API_BASE_URL`에 EC2 API 주소(Elastic IP 또는 도메인)를 주입한다.

### 4.8 CI/CD 파이프라인 (Phase E)

#### API 배포

```
트리거: push to main (services/api/**) 또는 repository_dispatch
파이프라인:
1. aws-actions/configure-aws-credentials@v4
2. aws-actions/amazon-ecr-login@v2
3. docker build + push (태그: ${GITHUB_SHA} + latest)
4. SSH into EC2 → deploy.sh (docker pull + docker run)
```

#### UI 배포

```
트리거: push to main (services/ui/**)
파이프라인:
1. Node.js 20 setup + npm ci
2. vite build (VITE_API_BASE_URL 주입)
3. aws s3 sync dist/ → S3 버킷
   - JS/CSS/이미지: Cache-Control max-age=31536000, immutable
   - index.html: Cache-Control no-cache, must-revalidate
4. aws cloudfront create-invalidation --paths "/*"
```

#### 크로스 레포 배포

```
GCP Airflow DAG → GitHub API (repository_dispatch) → AWS 레포 워크플로우 실행
```

### 4.9 CloudWatch 모니터링 (Phase E) ✅ 완료

> **구축일**: 2026-05-16  
> **스크립트**: `infra/scripts/07-setup-monitoring.sh`

```
알람 1: policy-pass-api-cpu-high (CPU > 80%, 10분 지속)
알람 2: policy-pass-monitor-cpu-high (CPU > 80%, 10분 지속)
알람 3: policy-pass-api-status-check (상태 체크 실패)
알람 4: policy-pass-monitor-status-check (상태 체크 실패)
(선택) SNS 토픽을 연결하여 이메일 알림 가능
```

---

## 5. GCP Airflow DAG 연동 (Phase F)

GCP 레포(`RAG-QA-pipeline-GCP`)의 `dag_collect_index.py`에 2개 태스크를 추가한다.

### 추가 태스크

```python
@task()
def sync_index_to_s3(indexed: dict) -> dict:
    """DataSync 태스크를 실행하여 FAISS 인덱스를 GCS에서 S3로 동기화"""
    import boto3
    client = boto3.client("datasync", region_name="ap-northeast-2")
    response = client.start_task_execution(TaskArn=DATASYNC_TASK_ARN)
    # 완료까지 폴링
    return {"execution_arn": response["TaskExecutionArn"]}

@task()
def trigger_api_redeploy(synced: dict) -> dict:
    """GitHub repository_dispatch로 API 재배포 트리거"""
    import requests
    requests.post(
        "https://api.github.com/repos/{owner}/policy-pass-infra-aws/dispatches",
        headers={"Authorization": f"token {GITHUB_TOKEN}"},
        json={"event_type": "deploy-api"}
    )
    return {"status": "redeploying"}
```

### 변경된 DAG 체인

```
(기존) collect_all_sources() >> rebuild_index() >> restart_api()
(변경) collect_all_sources() >> rebuild_index() >> restart_api() >> sync_index_to_s3() >> trigger_api_redeploy()
```

---

## 6. 구현 순서

```
Phase A: Foundation ✅
  01-setup-iam.sh → 02-setup-ecr.sh → 03-setup-s3.sh

Phase B: Data Sync + Secrets ✅
  04-setup-datasync.sh → 05-setup-ssm.sh

Phase C: Application Build ✅
  API Docker 이미지 빌드 → ECR push (latest: 6b4d0b86, 2026-05-10)

Phase D: Compute + Frontend ✅
  06-setup-ec2.sh (API + Monitor 인스턴스) ✅
  09-setup-cloudfront.sh (S3 버킷 + CloudFront Distribution) ✅

Phase E: CI/CD + Monitoring ✅
  deploy-api.yml (Docker → ECR → SSH deploy) ✅ GitHub Secrets 8개 설정
  deploy-ui.yml (vite build → S3 sync → CloudFront invalidation) ✅
  07-setup-monitoring.sh ✅

Phase F: GCP Airflow DAG Integration
  dag_collect_index.py 수정 (DataSync Task ARN 확정 후)

Utility:
  08-teardown.sh, toggle-instances.sh
```

---

## 7. 검증 방법

| 단계 | 검증 명령어 | 기대 결과 |
|------|-------------|-----------|
| IAM | `aws iam get-role --role-name EC2InstanceRole` | 역할 존재 확인 |
| ECR | `aws ecr describe-repositories` | rag-api 레포 존재 |
| S3 | `aws s3 ls s3://rag-qa-index-${ACCOUNT_ID}/` | 버킷 접근 가능 |
| DataSync | `aws datasync start-task-execution --task-arn ...` | S3에 인덱스 파일 도착 |
| SSM | `aws ssm get-parameters-by-path --path /rag-qa/ --with-decryption` | 파라미터 조회 가능 |
| EC2 API | `curl http://<EC2_API_IP>:8080/health` | HTTP 200 |
| CloudFront | `curl -I https://<CF_DOMAIN>/` | HTTP 200, Content-Type: text/html |
| SPA 라우팅 | `curl -I https://<CF_DOMAIN>/any/route` | HTTP 200 (index.html 반환) |
| API 연동 | 브라우저에서 검색 실행 | CORS 에러 없이 API 응답 수신 |
| CI/CD API | `services/api/` 변경 push → ECR 이미지 확인 → EC2 배포 | 자동 배포 성공 |
| CI/CD UI | `services/ui/` 변경 push → S3 동기화 → CloudFront 무효화 | 자동 배포 성공 |
| 모니터링 | `aws cloudwatch describe-alarms --alarm-name-prefix rag-qa` | 알람 설정 확인 |
| E2E | UI에서 정책 질문 → RAG 응답 확인 | 정책 데이터 기반 답변 |

---

## 8. 비용 예상 (월 기준)

| 서비스 | 예상 비용 | 비고 |
|--------|-----------|------|
| EC2 API (t3.medium) | ~$30 | On-demand, 미사용 시 중지 |
| EC2 Monitor (t3.small) | ~$15 | On-demand, 미사용 시 중지 |
| S3 (UI 정적 파일) | ~$0.02 | 빌드 결과물 저장 |
| CloudFront | ~$0.5-1 | CDN 배포, 트래픽 소량 |
| ECR | ~$1 | API 이미지 스토리지 |
| S3 (FAISS 인덱스) | < $1 | 인덱스 파일 저장 |
| DataSync | ~$0.04/GB | 전송량 기준 |
| SSM Parameter Store | 무료 | Standard tier |
| CloudWatch | ~$1-3 | 알람 + 로그 |
| **합계 (always on)** | **~$48.5/월** | |
| **합계 (dev, stopped)** | **~$5-10/월** | EBS + S3 + CloudFront만 |

---

## 9. 팀원 안내사항

### 팀원들에게 제공할 것

- EC2 API 엔드포인트 (Elastic IP)
- CloudFront UI 도메인 (`https://<distribution>.cloudfront.net`)
- CI/CD 파이프라인 (main 브랜치 push 시 자동 배포)
- FAISS 인덱스 S3 다운로드 패턴 (`ensure_index_files()` 참고)
- 환경변수 관리 방식 (SSM Parameter Store)

### 팀원들이 해야 할 것

- FastAPI API 코드 (`services/api/`) 개발
- React/TypeScript UI 코드 (`services/ui/`) 개발
- RAG 파이프라인 로직 구현
- FastAPI CORS 설정 (CloudFront 도메인 허용)

### 주의사항

- **인덱스 데이터는 컨테이너 이미지에 포함하지 않는다** → 런타임에 S3에서 다운로드
- **시크릿은 코드에 하드코딩하지 않는다** → SSM Parameter Store 사용
- **main 브랜치에 push하면 자동 배포된다** → PR 리뷰 후 머지 권장
- **UI 환경변수는 빌드 타임에 주입된다** → `VITE_` 접두사 사용, 런타임 변경 불가
