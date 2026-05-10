# AWS Online Serving 인프라 구축 계획서

> **최종 수정일**: 2026-05-10  
> **담당자**: Daehyun Kim (인프라)  
> **관련 문서**: [멀티클라우드 아키텍처 정리본](../multicloud_architecture_summary.md)

---

## 1. 개요

본 문서는 멀티클라우드 RAG QnA 시스템(청년정책 챗봇)의 **AWS Online Serving Layer** 인프라 구축 계획을 정리한 것이다.

GCP 측(Offline Data Pipeline: 크롤링 → 청킹 → 임베딩 → FAISS 인덱스 빌드)은 이미 구축 완료되었으며, 이 문서는 AWS 측 인프라만을 다룬다.

### 역할 분리

- **본인(Daehyun)**: AWS 인프라 구축 및 운영 (IAM, ECR, S3, DataSync, App Runner, CI/CD, 모니터링)
- **팀원들**: 애플리케이션 코드 개발 (FastAPI API, Streamlit UI, RAG 로직)

---

## 2. 핵심 의사결정

| 항목 | 선택 | 대안 | 선택 근거 |
|------|------|------|-----------|
| 컴퓨팅 서비스 | **App Runner** | ECS Fargate | 60-90% 저렴, VPC/ALB/NAT 불필요, 내장 HTTPS, scale-to-zero |
| FAISS 인덱스 전송 | **AWS DataSync** | boto3 직접 업로드 | GB 단위 인덱스 대응, 증분 전송, 체크섬 검증, 자동 재시도 |
| 시크릿 관리 | **SSM Parameter Store** | Secrets Manager | 무료 (Secrets Manager는 시크릿당 $0.40/월) |
| IaC 방식 | **CLI 셋업 스크립트** | Terraform | 학생 프로젝트 규모(~10개 리소스), 학습 목적 |
| 크로스 레포 CI/CD | **repository_dispatch** | 수동 트리거 | GCP 레포에서 자동으로 AWS 배포 트리거 가능 |
| 프론트엔드 호스팅 | **App Runner** | S3+CloudFront | Streamlit은 서버사이드 Python + WebSocket, 정적 사이트 불가 |

---

## 3. 생성할 파일 목록 (18개)

### 3.1 인프라 셋업 스크립트 (`infra/scripts/`)

| # | 파일명 | 역할 |
|---|--------|------|
| 1 | `01-setup-iam.sh` | IAM 역할 생성: App Runner ECR 접근, 인스턴스 역할 (S3 + SSM 읽기) |
| 2 | `02-setup-ecr.sh` | ECR 레포지토리 2개: `rag-api`, `rag-ui` (수명주기: 이미지 5개 유지) |
| 3 | `03-setup-s3.sh` | FAISS 인덱스용 S3 버킷 (`rag-qa-index-{ACCOUNT_ID}`) + 버전 관리 |
| 4 | `04-setup-datasync.sh` | DataSync: GCS 소스(HMAC) → S3 대상, 증분 전송 태스크 |
| 5 | `05-setup-ssm.sh` | SSM Parameter Store: OPENAI_API_KEY, MONGODB_URI, S3_BUCKET 등 |
| 6 | `06-setup-apprunner.sh` | App Runner 서비스 2개: API (1vCPU/2GB) + UI (0.25vCPU/0.5GB) |
| 7 | `07-setup-monitoring.sh` | CloudWatch 알람: 5xx 비율, p99 지연시간, CPU 사용률 |
| 8 | `08-teardown.sh` | 전체 리소스 역순 정리 |
| 9 | `toggle-min-instances.sh` | API min-instances 전환 (0=개발, 1=운영) |

### 3.2 App Runner 설정 (`infra/`)

| 파일명 | 역할 |
|--------|------|
| `apprunner-api.json` | API 서비스: 1vCPU, 2GB, 포트 8080, 헬스체크 `/health`, 오토스케일 1-3 |
| `apprunner-ui.json` | UI 서비스: 0.25vCPU, 0.5GB, 포트 8501, 헬스체크 `/healthz`, 오토스케일 1-2 |

### 3.3 CI/CD 워크플로우 (`.github/workflows/`)

| 파일명 | 역할 |
|--------|------|
| `deploy-api.yml` | API 이미지 빌드 → ECR 푸시 → App Runner 배포. 트리거: main 푸시 + repository_dispatch |
| `deploy-ui.yml` | UI 이미지 빌드 → ECR 푸시 → App Runner 배포. 트리거: main 푸시 + repository_dispatch |

### 3.4 애플리케이션 스캐폴딩 (레포 루트)

| 파일명 | 역할 |
|--------|------|
| `Dockerfile` | API 컨테이너: python:3.11-slim, pip install, 포트 8080 (GCP 버전 기반) |
| `Dockerfile.ui` | UI 컨테이너: python:3.11-slim, pip install + plotly, 포트 8501 (GCP 버전 기반) |
| `pyproject.toml` | 의존성 관리: `[api]`, `[ui]` extras (GCP 프로젝트와 동일 구조) |
| `.env.example` | 필수 환경변수 템플릿 |
| `.gitignore` | Python + AWS + IDE 무시 패턴 |

---

## 4. 인프라 아키텍처 상세

### 4.1 IAM 역할 (Phase A)

```
AppRunnerECRAccessRole
├── Trust: build.apprunner.amazonaws.com, apprunner.amazonaws.com
└── Policy: AmazonEC2ContainerRegistryReadOnly (ECR pull 권한)

AppRunnerInstanceRole
├── Trust: tasks.apprunner.amazonaws.com
└── Inline Policy:
    ├── S3: GetObject, ListBucket (인덱스 버킷만)
    └── SSM: GetParameter, GetParametersByPath (/rag-qa/*)

DataSyncS3Role
├── Trust: datasync.amazonaws.com
└── Inline Policy:
    └── S3: GetObject, PutObject, DeleteObject, ListBucket (인덱스 버킷)
```

### 4.2 ECR 레지스트리 (Phase A)

```
rag-api  ← API 컨테이너 이미지
rag-ui   ← UI 컨테이너 이미지

수명주기 정책: untagged 이미지 5개 초과 시 자동 삭제
이미지 태그 형식: {github.sha}
```

### 4.3 S3 버킷 (Phase A)

```
rag-qa-index-${ACCOUNT_ID}
├── 버전 관리: 활성화
├── 수명주기: 이전 버전 30일 후 삭제
└── 구조:
    └── index/
        ├── faiss.index      (FAISS 벡터 인덱스)
        └── metadata.json    (정책 메타데이터)
```

### 4.4 DataSync (Phase B)

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

### 4.5 SSM Parameter Store (Phase B)

```
/rag-qa/openai-api-key     (SecureString) ← OpenAI API 키
/rag-qa/mongodb-uri         (SecureString) ← MongoDB 연결 문자열
/rag-qa/s3-bucket           (String)       ← 인덱스 버킷명
/rag-qa/index-s3-prefix     (String)       ← 인덱스 경로 (기본값: "index/")
```

### 4.6 App Runner 서비스 (Phase D)

#### API 서비스

```
이미지: ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/rag-api
CPU: 1 vCPU
메모리: 2 GB
포트: 8080
헬스체크: /health (간격 10초, 타임아웃 5초, 임계값 3)
오토스케일: min=1, max=3, 동시 요청=50
인스턴스 역할: AppRunnerInstanceRole
환경변수:
├── S3_BUCKET
├── INDEX_S3_PREFIX
└── DOWNLOAD_INDEX_FROM_S3=true
```

#### UI 서비스

```
이미지: ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/rag-ui
CPU: 0.25 vCPU
메모리: 0.5 GB
포트: 8501
헬스체크: /healthz (간격 20초, 타임아웃 10초, 임계값 3)
오토스케일: min=1, max=2, 동시 요청=20
환경변수:
└── API_BASE_URL → API 서비스 URL
```

### 4.7 CI/CD 파이프라인 (Phase E)

```
트리거:
├── push to main (경로 필터: src/api/**, Dockerfile 등)
└── repository_dispatch (GCP Airflow에서 호출)

파이프라인:
1. aws-actions/configure-aws-credentials@v4
2. aws-actions/amazon-ecr-login@v2
3. docker build + push (태그: ${GITHUB_SHA})
4. aws apprunner start-deployment

크로스 레포 배포:
GCP Airflow DAG → GitHub API (repository_dispatch) → AWS 레포 워크플로우 실행
```

### 4.8 CloudWatch 모니터링 (Phase E)

```
알람 1: API 5xx 비율 > 5% (5분 윈도우)
알람 2: API p99 지연시간 > 10초
알람 3: CPU 사용률 > 80% (10분 지속)
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
def trigger_apprunner_redeploy(synced: dict) -> dict:
    """App Runner 재배포를 트리거하여 새 인덱스 반영"""
    import boto3
    client = boto3.client("apprunner", region_name="ap-northeast-2")
    client.start_deployment(ServiceArn=APPRUNNER_API_SERVICE_ARN)
    return {"status": "redeploying"}
```

### 변경된 DAG 체인

```
(기존) collect_all_sources() >> rebuild_index() >> restart_api()
(변경) collect_all_sources() >> rebuild_index() >> restart_api() >> sync_index_to_s3() >> trigger_apprunner_redeploy()
```

---

## 6. 구현 순서

```
Phase A: Foundation
  01-setup-iam.sh → 02-setup-ecr.sh → 03-setup-s3.sh

Phase B: Data Sync + Secrets
  04-setup-datasync.sh → 05-setup-ssm.sh

Phase C: Application Scaffolding
  Dockerfile, Dockerfile.ui, pyproject.toml, .env.example, .gitignore

Phase D: App Runner Services
  06-setup-apprunner.sh (ECR 이미지 존재 후 실행)

Phase E: CI/CD + Monitoring
  deploy-api.yml, deploy-ui.yml, 07-setup-monitoring.sh

Phase F: GCP Airflow DAG Integration
  dag_collect_index.py 수정 (DataSync Task ARN 확정 후)

Utility:
  08-teardown.sh, toggle-min-instances.sh
```

---

## 7. 검증 방법

| 단계 | 검증 명령어 | 기대 결과 |
|------|-------------|-----------|
| IAM | `aws iam get-role --role-name AppRunnerInstanceRole` | 역할 존재 확인 |
| ECR | `aws ecr describe-repositories` | rag-api, rag-ui 레포 존재 |
| S3 | `aws s3 ls s3://rag-qa-index-${ACCOUNT_ID}/` | 버킷 접근 가능 |
| DataSync | `aws datasync start-task-execution --task-arn ...` | S3에 인덱스 파일 도착 |
| SSM | `aws ssm get-parameters-by-path --path /rag-qa/ --with-decryption` | 파라미터 조회 가능 |
| App Runner | `curl https://<service-url>/health` | HTTP 200 |
| CI/CD | main에 push → ECR 이미지 확인 → App Runner 업데이트 | 자동 배포 성공 |
| 모니터링 | `aws cloudwatch describe-alarms --alarm-name-prefix rag-qa` | 알람 설정 확인 |
| E2E | Streamlit UI에서 질문 → RAG 응답 확인 | 정책 데이터 기반 답변 |

---

## 8. 비용 예상 (월 기준)

| 서비스 | 예상 비용 | 비고 |
|--------|-----------|------|
| App Runner (API) | ~$5-15 | 1vCPU/2GB, scale-to-zero 적용 시 |
| App Runner (UI) | ~$2-5 | 0.25vCPU/0.5GB |
| ECR | ~$1 | 이미지 스토리지 |
| S3 | < $1 | 인덱스 파일 저장 |
| DataSync | ~$0.04/GB | 전송량 기준 |
| SSM Parameter Store | 무료 | Standard tier |
| CloudWatch | ~$1-3 | 알람 + 로그 |
| **합계** | **~$10-25/월** | 트래픽 최소 기준 |

---

## 9. 팀원 안내사항

### 팀원들에게 제공할 것

- App Runner 서비스 URL (API 엔드포인트)
- CI/CD 파이프라인 (main 브랜치 push 시 자동 배포)
- FAISS 인덱스 S3 다운로드 패턴 (`ensure_index_files()` 참고)
- 환경변수 관리 방식 (SSM Parameter Store → App Runner 환경변수)

### 팀원들이 해야 할 것

- FastAPI API 코드 (`src/api/`) 개발
- Streamlit UI 코드 (`src/ui/`) 개발
- RAG 파이프라인 로직 구현
- `pyproject.toml`에 필요한 패키지 추가

### 주의사항

- **인덱스 데이터는 컨테이너 이미지에 포함하지 않는다** → 런타임에 S3에서 다운로드
- **시크릿은 코드에 하드코딩하지 않는다** → SSM Parameter Store 사용
- **main 브랜치에 push하면 자동 배포된다** → PR 리뷰 후 머지 권장
