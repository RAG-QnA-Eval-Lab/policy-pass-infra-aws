# 팀 논의 필요 사항

> **최종 수정일**: 2026-05-10  
> **작성자**: Daehyun Kim  
> **상태**: 기초 인프라 구축 후, 팀원 합류 전 논의 필요

이 문서는 AWS 인프라 기초 구축(Phase A~B) 완료 후, 팀원들과 논의해야 할 사항을 정리한 것이다.

---

## 1. DataSync 사용을 위한 AWS 결제 카드 등록

### 현황

- 현재 AWS 계정(`355206939988`)은 **프리티어(무료 계정)** 상태
- DataSync는 프리티어에 포함되지 않아 사용 불가
- GCS → S3 FAISS 인덱스 전송을 위해 DataSync가 필요

### 필요 작업

1. AWS 콘솔 → **내 결제 대시보드(Billing)** → 결제 수단 등록 (신용/체크카드)
2. 등록 후 DataSync 태스크 생성 가능 (가이드: [aws-console-guide.md](./aws-console-guide.md) Phase B-1)
3. DataSync 비용: **~$0.04/GB** (FAISS 인덱스 크기 기준 월 수백원 수준)

### DataSync 없이 임시 대안

카드 등록 전까지는 수동 전송으로 대체 가능:

```bash
# GCS → 로컬 → S3 수동 전송
gsutil cp -r gs://{GCS_BUCKET}/index/ ./index/
aws s3 cp ./index/ s3://rag-qa-index-355206939988/index/ --recursive --profile rag-qa
```

### 논의 포인트

- 팀 공용 카드 등록 vs 개인 카드 등록 후 정산
- DataSync 자동화 (Airflow DAG 연동) vs 수동 전송으로 충분한지
- 월 예상 비용 공유: 전체 인프라 ~$10-25/월 (트래픽 최소 기준)

---

## 2. SSM Parameter Store 추가 파라미터

### 현재 생성 완료 (4개)

| 파라미터 | 타입 | 값 |
|----------|------|----|
| `/rag-qa/openai-api-key` | SecureString | OpenAI API 키 |
| `/rag-qa/mongodb-uri` | SecureString | MongoDB 연결 문자열 |
| `/rag-qa/s3-bucket` | String | `rag-qa-index-355206939988` |
| `/rag-qa/index-s3-prefix` | String | `index/` |

### 추가 생성 대기 중 (팀원 논의 후 결정)

| 파라미터 | 타입 | 기본값 | 논의 사항 |
|----------|------|--------|-----------|
| `/rag-qa/mongodb-db` | String | `rag_youth_policy` | DB명 변경 여부 |
| `/rag-qa/embedding-model` | String | `openai/text-embedding-3-small` | GCP에서 빌드한 인덱스와 동일 모델 유지 필수 |
| `/rag-qa/embedding-dim` | String | `1536` | 임베딩 모델 변경 시 차원도 변경 필요 |
| `/rag-qa/environment` | String | `production` | 환경 구분 (로깅/CORS 등 영향) |

### 팀원이 RAG 체인 개발 시 추가 고려

| 파라미터 | 타입 | 기본값 | 설명 |
|----------|------|--------|------|
| `/rag-qa/top-k` | String | `10` | 검색 시 상위 청크 수 (재배포 없이 튜닝 가능) |
| `/rag-qa/rerank-top-k` | String | `5` | Reranker 통과 후 LLM에 전달할 청크 수 |
| `/rag-qa/huggingface-api-key` | SecureString | - | Llama 등 HF 모델 사용 시 필요 |
| `/rag-qa/api-key` | SecureString | - | API 인증 키 (외부 무단 호출 방지) |

### 논의 포인트

- LLM 모델 선택은 팀원들이 LangChain 코드에서 직접 결정 (SSM에 넣지 않음)
- `top-k`, `rerank-top-k` 등 튜닝 파라미터를 SSM에 넣을지 vs 코드에 하드코딩할지
- API 인증 방식: API Key vs OAuth vs 인증 없음 (내부용이면 불필요할 수 있음)
- SSM에서 파라미터를 읽는 코드 패턴: 앱 시작 시 boto3로 일괄 로드 추천

---

## 3. RAG 체인 개발 역할 분담

### 인프라 담당 (Daehyun) 이 제공하는 것

- App Runner 서비스 URL (API 엔드포인트)
- CI/CD 파이프라인 (main 브랜치 push → 자동 배포)
- S3에서 FAISS 인덱스 다운로드하는 패턴 코드
- SSM Parameter Store 파라미터 관리
- CloudWatch 모니터링 알람

### 팀원들이 개발해야 할 것

- FastAPI API 코드 (`src/api/`) — RAG 체인 로직 포함
- Streamlit UI 코드 (`src/ui/`)
- LangChain 기반 RAG 파이프라인 (Retriever + Generator)
- `pyproject.toml`에 필요한 패키지 추가

### 논의 포인트

- FastAPI 프로젝트 구조 (GCP 레포 구조 그대로 vs 새로 설계)
- LangChain 버전 및 의존성 확정
- FAISS 인덱스 로드 방식: 앱 시작 시 S3 → 로컬 다운로드 후 메모리 로드
- MongoDB 접근 방식: GCP Compute Engine(34.47.80.98)에 직접 연결 — 방화벽 규칙 확인 필요

---

## 4. MongoDB 접근 경로

### 현황

- MongoDB는 GCP Compute Engine(`34.47.80.98:27017`)에서 운영 중
- AWS App Runner에서 이 IP로 직접 연결해야 함

### 확인 필요 사항

- GCP 방화벽 규칙에 App Runner의 아웃바운드 IP 허용 여부
- App Runner는 고정 IP가 없음 (NAT Gateway 없이 동적 IP 사용)
- MongoDB Atlas로 마이그레이션 검토 필요 여부

### 논의 포인트

- GCP 방화벽에서 `0.0.0.0/0`으로 27017 포트 열기 (보안 위험 있음) vs MongoDB Atlas 사용
- MongoDB 인증 (`admin:1129`)이 충분한 보안인지 검토

---

## 5. 비용 관리

### 예상 월 비용

| 서비스 | 예상 비용 | 비고 |
|--------|-----------|------|
| App Runner (API) | ~$5-15 | scale-to-zero 적용 시 |
| App Runner (UI) | ~$2-5 | 최소 사양 |
| ECR | ~$1 | 이미지 스토리지 |
| S3 | < $1 | FAISS 인덱스 저장 |
| DataSync | ~$0.04/GB | 카드 등록 후 사용 가능 |
| SSM | 무료 | Standard tier |
| CloudWatch | ~$1-3 | 알람 + 로그 |
| **합계** | **~$10-25/월** | |

### 비용 절감 옵션

- 개발 중에는 App Runner min-instances를 `0`으로 설정 (콜드 스타트 30-60초 발생)
- 사용하지 않을 때 App Runner 서비스 일시 중지(Pause) 가능
- 프로젝트 종료 후 전체 리소스 teardown ([가이드 참고](./aws-console-guide.md#리소스-정리-teardown))

### 논의 포인트

- 비용 분담 방식
- 프로젝트 종료 시점 및 리소스 정리 계획

---

## 체크리스트

- [ ] AWS 결제 카드 등록 여부 결정
- [ ] 추가 SSM 파라미터 목록 확정
- [ ] RAG 체인 개발 역할 분담 확정
- [ ] MongoDB 접근 방식 결정 (직접 연결 vs Atlas)
- [ ] LangChain 프로젝트 구조 확정
- [ ] 비용 분담 방식 합의
