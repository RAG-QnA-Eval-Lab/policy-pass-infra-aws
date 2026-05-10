# 멀티클라우드 RAG 아키텍처 정리본

## 1. 현재 논의의 결론

이번 구조는 **A안**으로 정리한다.

A안의 핵심은 다음과 같다.

- **GCP**: 데이터 수집, 청킹, 임베딩, FAISS 인덱스 생성
- **AWS**: 생성된 FAISS 인덱스를 로드하여 검색 서빙, LLM 호출, 사용자 응답 제공

즉, **FAISS build는 GCP**, **FAISS load/search serving은 AWS**로 역할을 나눈다.

---

## 2. 왜 A안이 적합한가

팀원들이 이후 서빙 로직, 프롬프트, 출력 형식, 프론트엔드 등을 자주 수정해야 하므로, 실시간 서비스 계층은 AWS에 두는 것이 협업 측면에서 더 유리하다.

특히 아래 이유 때문에 A안이 현실적이다.

1. **팀원 수정 편의성**  
   프론트엔드, 프롬프트 엔지니어링, 평가 로직 등은 서비스 레이어에서 자주 수정될 가능성이 높다. 이 부분을 AWS에 모으면 협업이 편해진다.

2. **책임 분리 명확화**  
   GCP는 offline pipeline, AWS는 online serving으로 구분되므로 각 역할이 분명해진다.

3. **운영 관점 단순화**  
   데이터 파이프라인과 사용자 서비스 레이어를 구분하면 장애 분석과 운영이 쉬워진다.

---

## 3. GCP에서 담당하는 영역

현재 그림 기준으로 GCP에는 이미 데이터 엔지니어링 및 인덱싱 관련 역할이 거의 모두 포함되어 있다.

### GCP 담당 범위

- 외부 정책 데이터 수집
  - 공공데이터포털
  - 한국장학재단
  - 정책 문서(PDF)
- **Airflow DAG 기반 주기 실행** (매일 02:00 KST, `dag_collect_index.py`)
- Data Crawler 실행
- 원본 데이터 저장
- 정제 데이터 저장
- 청킹(Chunking)
- 임베딩(Embedding) — `openai/text-embedding-3-small` (1536차원, LiteLLM 경유)
- FAISS 인덱스 생성(Build)
- GCS에 Policies / Chunks / Index 저장
- **Airflow task chaining 기반 후속 파이프라인 트리거** (수집 → 인덱싱 자동 연결)
- MongoDB 기반 메타데이터 저장
- Cloud Logging / Cloud Monitoring

### GCP의 역할 정의

GCP는 **Offline Data / RAG Preparation Layer**로 정의한다.

즉,

- 데이터를 모으고
- 검색 가능한 형태로 가공하고
- 인덱스를 만들어 저장하는 역할

까지를 맡는다.

---

## 4. AWS에서 담당하는 영역

문서 기준 원래 AWS는 다음을 담당하도록 되어 있었다.

- Front-End
- Back-End
- FAISS 로드 후 검색 수행
- LLM 호출
- 평가 파이프라인 실행
- 운영 및 모니터링

이번 논의 기준으로도 AWS는 **실시간 서비스 계층**을 담당한다.

### AWS 담당 범위

- Front-End 서비스
- Back-End API
- GCP에서 생성된 FAISS 인덱스 다운로드 및 로드
- 실시간 Retrieval/Search
- LLM 호출
- 응답 생성
- 평가 결과 표현
- 서비스 모니터링/관제

### AWS의 역할 정의

AWS는 **Online Serving Layer**로 정의한다.

즉,

- 사용자 요청을 받고
- 검색을 수행하고
- LLM 응답을 생성하고
- 결과를 보여주는 역할

을 맡는다.

---

## 5. FAISS는 어디에 두는가

이 부분은 다음처럼 구분해서 이해해야 한다.

### 5.1 FAISS Build

- 위치: **GCP**
- 역할: 청킹 및 임베딩 완료 후 FAISS 인덱스 생성
- 실행 주체: **Airflow DAG Task** (`rag-airflow-vm`에서 `dag_collect_index.py`의 `rebuild_index` task 실행)

### 5.2 FAISS Load / Search Serving

- 위치: **AWS**
- 역할: 생성된 `faiss.index`를 로드하여 실시간 검색 수행
- 실행 주체: AWS Back-End
- 메모리: **2Gi**

따라서,

> **FAISS build는 GCP, FAISS 2Gi load/search serving은 AWS**

로 정리한다.

---

## 6. 현재 그림에서 헷갈렸던 부분

기존 그림 일부에서는 아래 두 요소가 모두 GCP 안에 배치되어 있었다.

- `Back-End (Cloud Run, FastAPI & FAISS 2Gi)`
- `Chunker & FAISS Build (Cloud Run Job)`

이렇게 그리면 의미상 아래처럼 읽힌다.

- GCP에서 인덱스를 만들고
- GCP에서 인덱스를 로드하고
- GCP에서 검색 및 서빙까지 수행한다

즉, **A안이 아니라 GCP 단일클라우드형처럼 보이게 된다.**

### A안으로 수정할 때의 원칙

- `Chunker & FAISS Build`는 **GCP**에 둔다
- `Back-End (FastAPI & FAISS Load/Search)`는 **AWS**에 둔다
- `Index Load` 화살표는 **GCP Cloud Storage → AWS Back-End**로 향해야 한다

---

## 7. 모니터링 서버는 어디에 둘 것인가

모니터링은 **하나로 합치는 것이 좋다.**

이번 논의의 결론은 다음과 같다.

> **운영 관제는 AWS로 단일화한다.**

### 이유

1. **실제 사용자 서비스가 AWS 중심**  
   Front-End / Back-End / 검색 / LLM 응답이 AWS에서 수행되므로, 서비스 기준 관제도 AWS에 두는 것이 자연스럽다.

2. **팀원들이 가장 자주 확인할 대상이 AWS 서비스 상태**  
   API 응답 속도, 검색 성공 여부, LLM 에러율, UI 동작 등은 모두 AWS 기준으로 확인하게 된다.

3. **GCP는 파이프라인 성격의 모니터링이 중심**  
   GCP에서는 crawler 성공/실패, index build 완료 여부, 마지막 적재 시각 같은 백오피스 지표가 핵심이다.

### 최종 방향

- **AWS**: 통합 운영 관제 대시보드
- **GCP**: 데이터 파이프라인 메트릭 수집 및 제공

즉,

- 운영 관제 화면은 AWS에 하나로 두고
- GCP는 ingestion/indexing 상태를 제공하는 역할

로 정리한다.

---

## 8. 팀 역할 기준으로 본 아키텍처 해석

현재 팀 역할은 다음과 같다.

- 데이터 엔지니어링
- 프롬프트 엔지니어링
- RAG 파이프라인
- 신뢰성 평가
- Frontend

이 구조에서 사용자 본인은 **데이터 엔지니어링 담당**이다.

### 데이터 엔지니어링 담당 범위 (본인)

- 시나리오 테스트용 데이터 수집/구축
- 원본 및 정제 데이터 스키마 설계
- Retrieval 품질을 고려한 데이터 형식 설계
- 질문-정답 쌍 준비
- 메타데이터 구조 설계
- chunk-ready 문서 포맷 제공
- index 생성에 필요한 입력 품질 관리
- **GCP 데이터 파이프라인 구축 및 운영** (수집 → 청킹 → 임베딩 → FAISS 빌드)
- **AWS 인프라 세팅** (ECS, ECR, CI/CD, 네트워크 등 뼈대만 구축)

### 캡스톤 팀원 담당 범위

- `src/api/main.py` 및 API 라우트 개발
- Streamlit UI 개발
- 프롬프트 엔지니어링
- RAG 파이프라인 서빙 로직
- 평가 파이프라인 (RAGAS, LLM Judge, DeepEval)
- AWS 서빙 애플리케이션 코드 전체

즉, 본인은

> **GCP 데이터 파이프라인 + AWS 인프라 뼈대**를 담당하고,  
> **AWS 서빙 애플리케이션 코드**는 캡스톤 팀원들이 개발한다.

---

## 9. 최종 멀티클라우드 역할 분리

### GCP = Offline Pipeline

- Data crawling
- Raw / processed storage
- Metadata DB
- Chunking
- Embedding
- FAISS build
- Index publish

### AWS = Online Serving

- FE
- BE
- FAISS index load
- Retrieval API
- Prompt orchestration
- LLM call
- Response rendering
- Evaluation result exposure
- Monitoring dashboard

---

## 10. 발표/설계 시 사용할 수 있는 한 줄 설명

### 짧은 버전

> GCP에서는 데이터 수집, 청킹, 임베딩 및 FAISS 인덱스 생성을 수행하고, AWS에서는 생성된 인덱스를 로드하여 실시간 검색 및 LLM 응답 생성을 수행한다.

### 조금 더 설명형 버전

> 본 시스템은 멀티클라우드 구조로 설계되었으며, GCP는 데이터 파이프라인과 인덱스 생성 역할을 담당하고, AWS는 해당 인덱스를 활용한 실시간 검색, 응답 생성, 서비스 제공 및 운영 관제를 담당한다.

---

## 11. Repo 분리 전략

### 분리 이유

GCP 데이터 파이프라인, AWS 인프라, AWS 서빙 애플리케이션은 각각 변경 주기와 담당자가 다르다. 역할별로 repo를 분리하면 CI/CD 충돌을 방지하고 책임 경계가 명확해진다.

### Repo 구조 (3-repo)

| Repo | 담당자 | 내용 |
|------|--------|------|
| `RAG-QA-pipeline-GCP` (현재) | 본인 | GCP 데이터 파이프라인 전체 (수집, 청킹, 임베딩, FAISS 빌드, GCS, MongoDB) + GCP BE/FE |
| `RAG-QA-serving-AWS` (신규) | 본인 | AWS 인프라 관리 코드/스크립트 (CI/CD, ECS, ECR, 네트워크 등) |
| 팀원 repo (별도) | 캡스톤 팀원 | LangChain/RAG 기반 서빙 애플리케이션 코드 |

### `RAG-QA-serving-AWS` repo 구성 (본인 담당, 인프라 전용)

- `.github/workflows/deploy-api.yml` — ECR + ECS Fargate BE 자동 배포
- `.github/workflows/deploy-ui.yml` — ECR + ECS Fargate FE 자동 배포
- `infra/task-definition-api.json` — ECS Task Definition (BE, 2Gi)
- `infra/task-definition-ui.json` — ECS Task Definition (FE, 512Mi)
- `Dockerfile`, `Dockerfile.ui` — 빌드 뼈대
- `pyproject.toml` — 의존성 정의 (boto3 포함)
- `.env.example` — 환경변수 문서화
- GitHub Secrets 등록 (AWS 인증, GCS HMAC 키 등)
- 네트워크/보안 설정 스크립트

### 팀원 repo (캡스톤 팀원 담당, 애플리케이션 코드)

- LangChain 기반 RAG 서빙 로직
- FastAPI API 서버
- Streamlit 프론트엔드
- 프롬프트 엔지니어링
- 평가 파이프라인 (RAGAS, LLM Judge, DeepEval)

### FAISS 인덱스 전달 경로

```
GCP (이 repo)                          AWS (인프라 repo + 팀원 repo)
Airflow DAG → FAISS Build             ECS Container 기동
    ↓                                       ↓
GCS 업로드                              GCS S3호환 API (boto3 + HMAC)
(index/faiss.index)                    → /tmp/index/ 다운로드
(index/metadata.pkl)                   → RetrievalPipeline 로드
```

본인이 AWS 인프라 repo에서 배포 파이프라인을 세팅하면, 팀원들은 자기 repo에서 앱 코드를 개발하고 CI/CD를 통해 배포한다.

---

## 12. 최종 결론

이번 논의 기준 최종 결론은 아래와 같다.

1. **A안으로 진행한다**
2. **GCP는 데이터 수집/가공/인덱스 생성 담당**
3. **AWS는 인덱스 로드 후 검색/서빙 담당**
4. **FAISS build는 GCP, FAISS 2Gi load/search serving은 AWS**
5. **모니터링은 AWS로 단일화**
6. **데이터 엔지니어링 담당자는 GCP 파이프라인 + AWS 인프라 뼈대의 owner**
7. **AWS 서빙 애플리케이션 코드는 캡스톤 팀원들이 자체 repo에서 개발**
8. **Repo는 3개로 분리: GCP 파이프라인 / AWS 인프라 / 팀원 앱 코드**

---

## 13. GCP 인프라 상세 — 이 Repo에서 구축하는 것들

이 섹션은 `RAG-QA-pipeline-GCP` repo가 실제로 사용하는 GCP 서비스와, repo 내 어떤 코드/파일이 각 인프라에 대응하는지를 정리한다.

### 13.1 Cloud Storage (GCS)

GCS는 이 시스템의 **실제 데이터 저장소**다. 정책 원본, 정제 데이터, FAISS 인덱스를 모두 여기에 보관한다.

| 항목 | 값 |
|------|-----|
| 버킷 | `rag-qna-eval-data` |
| 리전 | `asia-northeast3` (서울) |

**저장 경로 구조**:

```
gs://rag-qna-eval-data/
├── policies/
│   ├── raw/                  ← 정책 원본 JSON
│   └── processed/            ← 정제 데이터
└── index/
    ├── faiss.index            ← FAISS 벡터 인덱스
    └── metadata.pkl           ← 인덱스 메타데이터 (chunk→정책 매핑)
```

**repo 코드 매핑**:

- `src/ingestion/gcs_client.py` — `GCSClient` 클래스. upload_json, download_json, upload_file, download_file, list_blobs, exists, delete 메서드 제공.
- `scripts/collect_policies.py` — 수집 완료 후 원본 데이터를 GCS에 업로드
- `src/ingestion/pipeline.py` — FAISS 인덱스 빌드 후 GCS에 업로드 (`--gcs` 플래그)

**AWS와의 공유 계약**:

`index/faiss.index`와 `index/metadata.pkl`이 GCP↔AWS 간 유일한 공유 아티팩트다. AWS 측에서는 GCS의 S3 호환 API (boto3 + HMAC 키)를 통해 이 파일들을 다운로드한다.

### 13.2 Compute Engine (VM 2대)

GCP VM 2대를 운영한다.

#### VM #1: MongoDB + Grafana (`rag-mongodb-vm`, e2-small)

| 항목 | 값 |
|------|-----|
| 인스턴스 타입 | e2-small |
| 고정 IP | `34.47.80.98` |
| 역할 | MongoDB (메타데이터 DB) + Grafana (모니터링 대시보드) |

**MongoDB** (`rag_youth_policy` DB):

| 컬렉션 | 용도 | 주요 필드 |
|--------|------|----------|
| `policies` | 정책 메타데이터 | policy_id, title, category, gcs_path, status |
| `ingestion_logs` | 수집 이력 | source, collected_count, valid_count, status, gcs_paths |
| `api_usage_logs` | LLM API 호출 이력 | model, tokens, cost, latency |

repo 코드: `src/ingestion/mongo_client.py` — `PolicyMetadataStore` 클래스. upsert_policy, upsert_policies_batch, find_by_id, find_by_category, log_ingestion 등.

접속: `MONGODB_URI=mongodb://34.47.80.98:27017` (`config/settings.py`의 Settings 클래스에서 관리)

**Grafana**: 포트 3000에서 운영. Cloud Monitoring을 데이터소스로 연결하여 대시보드 구성.

#### VM #2: Airflow (`rag-airflow-vm`, e2-standard-2)

| 항목 | 값 |
|------|-----|
| 인스턴스 타입 | e2-standard-2 |
| 고정 IP | `34.47.107.145` |
| 역할 | Apache Airflow 2.9.3 (오케스트레이션) |
| Web UI | `http://34.47.107.145:8080` |

**Airflow DAGs** (3개):

| DAG | 파일 | 스케줄 | 용도 |
|-----|------|--------|------|
| `dag_collect_index` | `dags/dag_collect_index.py` | 매일 02:00 KST | 정책 수집 → FAISS 인덱스 리빌드 |
| `dag_qa_generation` | `dags/dag_qa_generation.py` | 수동 트리거 | QA 데이터셋 생성 |
| `dag_evaluation` | `dags/dag_evaluation.py` | 수동 트리거 | 평가 파이프라인 실행 |

> **Cloud Run Jobs → Airflow 전환 배경**: Cloud Run Jobs에서는 태스크 간 의존성 관리가 어렵고 (수집→인덱싱 체이닝 불가), 실행 상태 모니터링이 불편하며, 비용이 높았다 (월 ~₩38,000 → Airflow VM ~₩68,000이지만 3개 DAG 통합 운영으로 실효 비용 82% 절감). 자세한 비교는 `docs/plan.md`의 "Cloud Run Jobs → Airflow 전환 배경" 섹션 참조.

repo 코드:
- `dags/` — Airflow DAG 정의 3개 + `dags/utils/cloud_run.py` 유틸리티
- `airflow/setup-vm.sh` — VM 초기 설정 스크립트 (Airflow + mecab 설치)
- `.github/workflows/deploy-airflow.yml` — Airflow VM 코드 동기화 CI/CD

### 13.3 Cloud Run — 서비스 (scale-to-zero)

실시간 서빙을 담당하는 상시 서비스 2개를 Cloud Run으로 운영한다.

#### Cloud Run #1: BE (FastAPI)

| 항목 | 값 |
|------|-----|
| 서비스명 | `rag-youth-policy-api` |
| 메모리 | 2Gi (FAISS 인메모리 + Cross-Encoder 로드) |
| Dockerfile | `Dockerfile` |
| CMD | `uvicorn src.api.main:app --host 0.0.0.0 --port $PORT` |
| 포트 | 8080 |

repo 코드:

- `src/api/main.py` — FastAPI 앱 엔트리 (lifespan: FAISS 인덱스 로드 + MongoDB 연결)
- `src/api/routes/` — 6개 라우트 구현 완료: search.py, generate.py, policies.py, models.py, evaluate.py
- `src/api/deps.py` — FastAPI Depends: `get_rag_pipeline()`, `get_mongo()`
- `src/api/schemas.py` — Pydantic 요청/응답 모델
- `src/api/errors.py` — 글로벌 예외 핸들러 (`LLMError` → HTTP 코드 매핑)
- `src/api/middleware.py` — 요청 로깅 미들웨어
- `src/retrieval/` — 4가지 검색 전략 (vector_only, bm25_only, hybrid, hybrid_rerank)
- `src/generation/` — LiteLLM 멀티 프로바이더 + RAG 오케스트레이션

CI/CD: `.github/workflows/deploy-api.yml` (push to main 시 자동 배포)

환경변수: `GCS_BUCKET`, `MONGODB_URI`, `OPENAI_API_KEY`, `VERTEXAI_PROJECT`, `VERTEXAI_LOCATION`

#### Cloud Run #2: FE (Streamlit)

| 항목 | 값 |
|------|-----|
| 서비스명 | `rag-youth-policy-ui` |
| 메모리 | 512Mi |
| Dockerfile | `Dockerfile.ui` |
| CMD | `streamlit run src/ui/app.py --server.port=8501` |
| 포트 | 8501 |

repo 코드: `src/ui/` — Streamlit 4페이지 구현 완료 (챗봇, 정책 탐색, 맞춤 추천, 평가 대시보드). httpx로 BE API 호출.

CI/CD: `.github/workflows/deploy-ui.yml` (push to main 시 자동 배포)

### 13.4 Cloud Run Jobs — 배치 작업 (Airflow로 전환됨)

> **현재 상태**: Cloud Run Jobs 인프라 코드(Dockerfile, CI/CD)는 보존하지만, 실제 운영은 **Airflow DAG**에서 수행한다. Cloud Run Jobs → Airflow 전환 배경은 §13.2 VM #2 참조.

트리거 기반으로 실행되는 배치 작업 2개의 인프라 정의가 남아있다.

#### Collector Job

| 항목 | 값 |
|------|-----|
| Job명 | `rag-collector` |
| 메모리 | 512Mi |
| Dockerfile | `Dockerfile.collector` |
| CMD | `python scripts/collect_policies.py --all` |

repo 코드:

- `scripts/collect_policies.py` — 수집 CLI 엔트리포인트
- `src/ingestion/collectors/base.py` — Policy frozen dataclass (정규화 스키마)
- `src/ingestion/collectors/data_portal.py` — 공공데이터포털 수집기
- `src/ingestion/gcs_client.py` — 수집 결과 GCS 업로드
- `src/ingestion/mongo_client.py` — 메타데이터 MongoDB 저장

환경변수: `DATA_PORTAL_API_KEY`, `GCS_BUCKET`, `MONGODB_URI`

#### Indexer Job

| 항목 | 값 |
|------|-----|
| Job명 | `rag-indexer` |
| 메모리 | 2Gi |
| Dockerfile | `Dockerfile.indexer` |
| CMD | `python -m src.ingestion.pipeline --gcs` |

repo 코드:

- `src/ingestion/pipeline.py` — 인덱싱 오케스트레이션 (GCS에서 원본 로드 → 청킹 → 임베딩 → FAISS 빌드 → GCS 업로드)
- `src/ingestion/loader.py` — PDF/TXT/JSON 로더
- `src/ingestion/chunker.py` — 시맨틱 청킹 (정책 구조 인식, kss + mecab C++ 백엔드 한국어 문장 분리)
- `src/ingestion/embedder.py` — OpenAI text-embedding-3-small (1536차원)

환경변수: `OPENAI_API_KEY`, `GCS_BUCKET`

CI/CD: `.github/workflows/deploy-jobs.yml` (collector + indexer 동시 배포)

### 13.5 Artifact Registry

| 항목 | 값 |
|------|-----|
| 레지스트리 | `asia-northeast3-docker.pkg.dev/rag-qna-eval/repo` |
| 역할 | Docker 이미지 저장소 |
| 이미지 4종 | `api`, `ui`, `collector`, `indexer` |

GitHub Actions 워크플로에서 `docker build` + `docker push` 후 Cloud Run에 deploy한다.

### 13.6 Cloud Scheduler → Airflow 대체

| 항목 | 값 |
|------|-----|
| ~~역할~~ | ~~매일 1회 Collector Job 트리거~~ |
| 현재 상태 | **Airflow로 대체됨**. `dag_collect_index.py`가 매일 02:00 KST에 수집+인덱싱을 실행. Cloud Scheduler는 더 이상 사용하지 않음 |

### 13.7 Eventarc → Airflow 대체

| 항목 | 값 |
|------|-----|
| ~~역할~~ | ~~GCS 이벤트 → Indexer Job 자동 체이닝~~ |
| 현재 상태 | **Airflow task chaining으로 대체됨**. `dag_collect_index.py`에서 `collect_policies >> rebuild_index`로 직접 체이닝. Eventarc는 더 이상 사용하지 않음 |

수집 → 인덱싱 자동화 체인 (변경 후): `Airflow DAG → collect_policies task → rebuild_index task → GCS 인덱스 업로드`

### 13.8 Cloud Monitoring + Cloud Logging

- **Cloud Monitoring**: Cloud Run 기본 메트릭 (요청 수, 레이턴시, 에러율) + FastAPI 커스텀 메트릭 수집
- **Cloud Logging**: 구조화 JSON 로그 (RAG 요청별 레이턴시/토큰/비용 추적)
- **Grafana 연동**: Compute Engine VM의 Grafana (포트 3000)에서 Cloud Monitoring 데이터소스를 연결하여 통합 대시보드 구성

### 13.9 CI/CD (GitHub Actions)

이 repo에는 5개의 GitHub Actions 워크플로가 있다.

| 워크플로 | 파일 | 트리거 | 대상 |
|---------|------|--------|------|
| CI (Lint + Test) | `.github/workflows/ci.yml` | PR → main | ruff + pytest |
| Deploy BE | `.github/workflows/deploy-api.yml` | push main (`src/api/**`, `Dockerfile` 등) | Cloud Run `rag-youth-policy-api` |
| Deploy FE | `.github/workflows/deploy-ui.yml` | push main (`src/ui/**`, `Dockerfile.ui`) | Cloud Run `rag-youth-policy-ui` |
| Deploy Jobs | `.github/workflows/deploy-jobs.yml` | push main (`src/ingestion/**` 등) | Cloud Run Jobs `rag-collector`, `rag-indexer` |
| Deploy Airflow | `.github/workflows/deploy-airflow.yml` | push main (`dags/**`, `airflow/**`) | Airflow VM (`rag-airflow-vm`) 코드 동기화 |

인증: `secrets.GCP_SA_KEY` (서비스 계정 JSON 키)

### 13.10 Dockerfiles (4종)

| Dockerfile | 용도 | 핵심 의존성 (extras) | 포트 |
|-----------|------|---------------------|------|
| `Dockerfile` | BE (FastAPI) | `.[api,ko]` | 8080 |
| `Dockerfile.ui` | FE (Streamlit) | `.[ui,viz]` | 8501 |
| `Dockerfile.collector` | 수집 Job | `.[crawl]` | — |
| `Dockerfile.indexer` | 인덱싱 Job | `.[ko]` | — |

모두 `python:3.11-slim` 베이스 이미지를 사용한다.

### 13.11 설정 관리

| 파일 | 역할 |
|------|------|
| `config/settings.py` | pydantic-settings 기반 Settings 클래스. `.env` 자동 로드. GCP 프로젝트/버킷, MongoDB URI, LLM API 키, 임베딩/청킹/검색 파라미터 |
| `config/policy_sources.py` | 데이터 소스별 URL/API 설정 (온통청년, 공공데이터포털, 한국장학재단, PDF) |
| `config/models.py` | LLM 모델 목록 (GPT-4o, Claude, Gemini, Llama3) |

### 13.12 Secret Manager

| 항목 | 값 |
|------|-----|
| 역할 | Cloud Run 런타임 환경변수 주입 (API 키, DB 접속 정보 등) |
| 주요 시크릿 | `OPENAI_API_KEY`, `MONGODB_URI`, `DATA_PORTAL_API_KEY`, `API_KEY` |

로컬 개발은 `.env` 파일, GCP 배포 런타임은 Secret Manager를 사용한다. Cloud Run 서비스/잡 배포 시 `--update-secrets` 플래그로 주입.

### 13.13 IAP (Identity-Aware Proxy)

| 항목 | 값 |
|------|-----|
| 역할 | Cloud Run 서비스 접근 제어 |
| 구현 상태 | 설정 완료 |

### 13.14 VPC Networking

| 항목 | 값 |
|------|-----|
| 역할 | MongoDB VM만 VPC 내부 배치, 나머지 관리형 서비스는 VPC 외부 |
| 구성 | Compute Engine VM에 static IP + 방화벽 규칙 (27017, 8080, 3000 포트) |

### 13.15 Repo 디렉토리 ↔ GCP 서비스 매핑 요약

| repo 경로 | GCP 서비스 | 역할 |
|----------|-----------|------|
| `src/api/` | Cloud Run #1 (BE, 2Gi) | FastAPI 백엔드 — 6개 엔드포인트 (Health, Search, Generate, Policies, Models, Evaluate) |
| `src/ui/` | Cloud Run #2 (FE, 512Mi) | Streamlit 4페이지 (챗봇, 정책 탐색, 맞춤 추천, 평가 대시보드) |
| `src/ingestion/collectors/` | **Airflow DAG** (`dag_collect_index`) | 정부 사이트 크롤러 |
| `src/ingestion/pipeline.py` | **Airflow DAG** (`dag_collect_index`) | 청킹 → 임베딩 → FAISS 빌드 |
| `src/ingestion/gcs_client.py` | Cloud Storage (GCS) | 데이터/인덱스 업로드·다운로드 |
| `src/ingestion/mongo_client.py` | Compute Engine VM #1 (MongoDB) | 메타데이터 CRUD |
| `src/retrieval/` | Cloud Run #1 (BE) | 벡터/BM25/하이브리드 검색 |
| `src/generation/` | Cloud Run #1 (BE) | LiteLLM 멀티 프로바이더 + RAG 오케스트레이션 |
| `src/evaluation/` | Cloud Run #1 (BE) | RAGAS v0.4 + LLM Judge + DeepEval 3단계 평가 |
| `config/` | 전체 | 환경변수, 모델 목록, 소스 설정 |
| `scripts/collect_policies.py` | Airflow DAG / Cloud Run Job | 수집 CLI 엔트리포인트 |
| `dags/` | Compute Engine VM #2 (Airflow) | Airflow DAG 3개 (수집+인덱싱, QA 생성, 평가) |
| `airflow/` | Compute Engine VM #2 (Airflow) | Airflow VM 설정 스크립트 |
| `Dockerfile` | Artifact Registry → Cloud Run BE | BE 컨테이너 이미지 |
| `Dockerfile.ui` | Artifact Registry → Cloud Run FE | FE 컨테이너 이미지 |
| `Dockerfile.collector` | Artifact Registry (보존) | 수집 Job 이미지 (Airflow 전환 후 백업) |
| `Dockerfile.indexer` | Artifact Registry (보존) | 인덱싱 Job 이미지 (Airflow 전환 후 백업) |
| `.github/workflows/` | GitHub Actions → GCP 배포 | CI/CD 파이프라인 **5종** |
| `data/index/` | GCS `index/` | FAISS 인덱스 로컬 빌드 산출물 |
| `data/eval/` | — | 평가 QA 데이터셋 (GCP 의존 없음) |
