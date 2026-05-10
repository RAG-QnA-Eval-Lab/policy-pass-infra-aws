# RAG QnA 시스템 구현 계획 (개인 프로젝트)

> **학생/청년 대상 정부 정책 QnA 시스템** — Hybrid RAG 기반 멀티 모델 응답 신뢰성 비교 파이프라인을 혼자 구축한다.
> 인프라는 GCP (크레딧 ₩786,544, 2026-06-19 만료). 개발은 별도 레포에서 진행.
> 목적: 졸업논문 초안 + PyCon Korea CFP 제출.

---

## 1. 목표

- **도메인**: 학생/청년 대상 정부 정책 QnA (주거, 취업, 창업, 교육, 복지, 금융)
- **LLMOps 파이프라인**: 수집 → 인덱싱 → 서빙 → 평가 → 모니터링 전체 운영 사이클 자동화
- Hybrid RAG (Vector + BM25 + Reranker) 파이프라인 구축
- 멀티 LLM 비교 (GPT-4o, Claude, Gemini, Llama3)
- 3단계 신뢰성 평가 (RAGAS + LLM Judge + DeepEval) 자동화
- GCP Cloud Run 배포 + Grafana/Cloud Monitoring 모니터링
- **제품 수준 Streamlit 프론트엔드** — 정책 탐색, QnA 챗봇, 맞춤 추천, 정책 비교, 평가 대시보드

---

## 2. 타임라인

```
중간고사 전 (2~3주)           중간고사 후 (6주)                          6/19 크레딧 만료
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Phase 0                     P1         P2       P3       P4        P5         P6
학습/환경 준비               데이터수집  검색     생성     평가      제품 UI    GCP배포
도메인 확정                  +파이프라인 시스템   파이프라인 파이프라인 6페이지    +실험/리포트
중간발표 준비                 collectors                           Streamlit
                            ──────── QA 데이터셋 병행 작성 (50~100쌍) ────────
```

**현재 진행 상황** (2026-04-26):
- Phase 0: 완료 (예산 알림 ₩200,000 잔여). Airflow VM 세팅 완료 (e2-standard-2, Airflow 2.9.3 + PostgreSQL 16 + 3 DAGs 배포)
- Phase 1: 코드 구현 완료. 정책 2,235건 수집 (data_portal 2,185 + youthgo 50). FAISS 인덱스 빌드 완료 (16.5MB + metadata 3MB). GCS raw/processed 구조 및 prompt 저장 경로 정리 완료
- Phase 2: 코드 구현 + 코드리뷰 + 버그 수정 완료
- Phase 3: 코드 구현 완료. Vertex AI Model Garden + HuggingFace 전환 완료. Claude Sonnet은 Vertex AI Model Garden (`vertex_ai/claude-sonnet-4-5`, us-east5)으로 전환. Gemini 2.5 Pro는 `us-central1` 리전 오버라이드 적용. GPT-4o/4o-mini, Gemini Flash 실호출 검증 완료. `LLMError(RuntimeError)` 커스텀 예외 도입 — status_code 기반 HTTP 매핑, LiteLLM 예외 계층별 분리 처리 (NotFoundError/AuthenticationError 즉시 raise, RateLimitError/ConnectionError 재시도)
- QA 데이터셋: 100쌍 생성 완료 (`scripts/generate_qa.py` → `data/eval/qa_pairs.json`). QA 생성 프롬프트는 GCS `prompts/qa_generation_system.txt`를 source of truth로 사용
- GCP 배포: Dockerfile 4종 + GitHub Actions 워크플로 5종 작성 완료 (ci, deploy-api, deploy-ui, deploy-jobs, deploy-airflow). Cloud Run API는 `MONGODB_URI`를 Secret Manager에서 주입하며, Airflow VM도 Secret Manager 기반으로 운영. deploy-airflow.yml 추가 — IAP SSH로 VM 코드 자동 동기화. Cloud Run Jobs에 `sa-airflow-pipeline` 서비스 계정 지정 (GCS 403 수정). Dockerfile.ui ModuleNotFoundError 수정 (`src/__init__.py` COPY 추가)
- Phase 4: 코드 구현 완료. 3단계 평가 파이프라인 (RAGAS v0.4 + LLM Judge + DeepEval) + 통합 오케스트레이터 + 리포트(JSON/HTML) 구현. 평가 DAG 연결 및 prompt hash 기록 완료
- IAM/운영보안: Cloud Run API / Airflow VM / Mongo VM 서비스 계정 분리, GCS versioning + UBLA + public access prevention 적용 완료
- FastAPI API: 전체 구현 완료. Health, Search, Generate, Policies, Models, Evaluate 6개 엔드포인트 + Pydantic 스키마 + CORS + 미들웨어 + 에러 핸들링. python-reviewer 코드리뷰 반영 (CRITICAL 2 + HIGH 6 + MEDIUM 7 전부 수정). generate 엔드포인트에서 `LLMError` 타입 기반 에러 핸들링으로 교체 (문자열 스니핑 제거), 기본 검색 전략 hybrid로 변경 (CrossEncoder 로드 문제 방지), 모델 가용성 필터 (`_is_available()`) 적용
- Phase 5 (UI): Streamlit 4페이지 구현 완료 (챗봇, 정책 탐색, 맞춤 추천, 평가 대시보드). 인프라 (API 클라이언트, 세션 상태, CSS) + 컴포넌트 3종 + 테스트 포함. 정책 상세 정보 14개 필드 표시 (description, eligibility, benefits, how_to_apply 등), 지역 코드→지역명 변환 (`_format_region`), XSS 방지 (`html.escape` + URL 스킴 검증), 빈 상세 정보 안내 메시지 추가
- Phase 6 (배포): FastAPI 백엔드 API 구현 완료 (Cloud Run 배포 대상). Dockerfile 4종 + GitHub Actions 5종 작성 완료. python-reviewer 코드리뷰 CRITICAL 2 + HIGH 7 + MEDIUM 5 + LOW 1 전부 수정 완료 — structured logging 개선 (JSON 직렬화 + traceback 필드), GCS health check 반환값 명확화 (`None`/`True`/`False` 3상태), 평가 스키마 타입 강화 (`RagasScores`/`JudgeScores`/`SafetyScores` Pydantic 모델), deploy-ui.yml API_KEY Secret Manager 연결, Phase 6 유틸리티 테스트 20개 추가 (costs/cloud_run/monitoring)
- 테스트: 전체 253 passed (API 테스트 26개 + UI 테스트 + Phase 6 유틸리티 테스트 20개 포함)

---

## 3. Phase 0: 중간고사 전 — 준비 (2~3주)

### 3.1 도메인 확정: 학생/청년 대상 정부 정책 QnA

**도메인**: 대한민국 정부가 제공하는 청년 정책 정보 (주거, 취업, 창업, 교육, 복지, 금융)

**선정 이유**:
- 실제 사용자 니즈가 큼 (청년 정책이 매년 수백 개이나 정보 접근성이 낮음)
- 정량 평가에 적합 (정답이 명확한 사실 기반 질문이 많음)
- 데이터가 공개적으로 풍부 (정부 공공데이터 포털, 각 부처 사이트)
- 졸업논문 + PyCon Korea CFP 제출 시 사회적 임팩트 어필 가능

**데이터 소스**:

| 소스 | URL | 데이터 유형 | 우선순위 |
|------|-----|------------|---------|
| 온통청년 | youth.go.kr | 정책 목록 + 상세 (API/크롤링) | ★★★★★ |
| 공공데이터포털 | data.go.kr | 청년정책 API (구조화 JSON) | ★★★★★ |
| 한국장학재단 | kosaf.go.kr | 장학금/학자금 정보 (크롤링) | ★★★★ |
| 고용노동부 | moel.go.kr | 취업/고용 정책 (PDF + 크롤링) | ★★★★ |
| 정책브리핑 | korea.kr | 정부 정책 FAQ/설명 | ★★★ |
| 국토교통부 | molit.go.kr | 청년 주거정책 (PDF) | ★★★ |

- [x] 도메인 확정 — 학생/청년 정부 정책 QnA
- [x] 온통청년 API 또는 크롤링 가능 여부 확인
  - 내부 검색 API 확인: `POST /pubot/search/portalPolicySearch` → JSON 1,608건 (세션 쿠키 + CSRF 토큰 필요)
  - Open API 별도 존재: `/opi/youthPlcyList.do` (회원가입 + API 키 승인 필요, XML 응답)
  - `.do` 패턴 URL은 HTTP:8080 리다이렉트 (외부 접근 불가), `/youthPolicy/*` 패턴은 HTTPS 정상
- [x] 공공데이터포털 청년정책 API 목록 조사
  - API 자체는 존재하나, 테스트 시점에 500 에러 반환 (서버 측 이슈)
  - API 키 발급 후 재검증 필요
- [x] 한국장학재단 접근성 확인
  - 서버사이드 렌더링 HTML → BeautifulSoup 파싱 적합
  - robots.txt: `User-agent: * Allow:/` (전면 허용)
  - URL 패턴: `/ko/scholar.do?pg=scholarship05_XX_XX` (15+ 페이지)
  - NomaDamas/k-skill `korean-scholarship-search` 스키마 참고 (정규화 스키마 + source-patterns 활용, 수집기는 직접 구현)
- [x] 수집 대상 카테고리 확정 (주거/취업/창업/교육/복지/금융)
- [x] 초기 데이터 50건 이상 수집 테스트 — 온통청년 내부 API로 50건 수집 완료 (2,181건 중 샘플)
- [x] `data/policies/raw/`에 수집 데이터 배치 — `youthgo_sample.json` (298KB)

### 3.2 기술 학습

| 순위 | 주제 | 이유 |
|------|------|------|
| 1 | RAGAS v0.4 | 온라인 예시 대부분 v0.3. v0.4는 `experiment()` 데코레이터 기반 전면 재설계 |
| 2 | LiteLLM | 멀티 LLM 전환 핵심 |
| 3 | FAISS | 벡터 저장/검색 |
| 3.5 | MongoDB | 메타데이터 관리 (정책 목록, 수집 이력) + Compass GUI |
| 4 | DeepEval | HallucinationMetric |
| 5 | Cross-Encoder | 검색 정밀도 |

**LLM 오케스트레이션 프레임워크 선택 근거**:

LangChain, LlamaIndex, LiteLLM을 비교 검토 후 LiteLLM 선택.

| | LangChain | LlamaIndex | LiteLLM (선택) |
|--|-----------|------------|----------------|
| 역할 | RAG 앱 프레임워크 | 문서 인덱싱+질의응답 | LLM 호출 래퍼 |
| 강점 | 빠른 RAG 앱 개발 | 문서 QA 특화 | 모델 전환 (문자열 1개) |
| 약점 | 의존성 과다, 추상화 깊음 | 같은 문제 | RAG 연결 직접 구현 필요 |
| 이 프로젝트 적합도 | X | X | **O** |

**선택 이유**: 이 프로젝트는 단일 RAG 챗봇이 아니라 **멀티 모델(4종) × 검색 전략(4종) 비교 실험**이 핵심.
- LangChain/LlamaIndex는 체인/엔진 내부에서 검색→생성을 감싸버려서 중간 contexts를 꺼내기 번거롭고, 모델/전략 교체 시 체인을 매번 재구성해야 함.
- LiteLLM은 LLM 호출만 감싸고 나머지(검색, 평가)는 직접 제어 → 실험 루프에서 자유롭게 조합 가능.
- 논문에서 LangChain(기존 구현 경험 있음), LlamaIndex와의 비교 근거로 활용.

**RAGAS v0.4 주의**:
```python
# v0.3 (온라인에 많음) — 쓰지 말 것
from ragas import evaluate
result = evaluate(dataset, metrics=[faithfulness])

# v0.4 (사용할 버전)
from ragas.metrics.collections import Faithfulness, AnswerRelevancy
# metric.ascore(**kwargs) → MetricResult (.value + .reason)
```

### 3.3 개발 환경 세팅

**레포 초기 구조**:
```
rag-youth-policy/                   # 개발 전용 레포 (별도)
├── pyproject.toml
├── .env.example
├── .gitignore
├── ruff.toml
├── config/
│   ├── __init__.py
│   ├── settings.py                # pydantic-settings
│   ├── models.py                  # LLM 모델 목록
│   └── policy_sources.py          # 데이터 소스별 URL/API 설정
├── src/
│   ├── __init__.py
│   ├── api/                       # FastAPI 백엔드 (Cloud Run #1)
│   │   ├── __init__.py
│   │   ├── main.py                # FastAPI 앱 엔트리
│   │   └── routes/
│   │       ├── __init__.py
│   │       ├── search.py          # /search — 검색 API
│   │       ├── generate.py        # /generate — RAG 답변 생성 API
│   │       ├── policies.py        # /policies — 정책 메타데이터 조회 API
│   │       └── evaluate.py        # /evaluate — 평가 API
│   ├── ingestion/
│   │   ├── __init__.py
│   │   ├── loader.py              # PDF/TXT/JSON 로더
│   │   ├── chunker.py             # 시맨틱 청킹 (정책 구조 인식)
│   │   ├── embedder.py            # 임베딩 생성
│   │   ├── mongo_client.py        # MongoDB 메타데이터 CRUD + GCS 연동
│   │   ├── pipeline.py            # 수집 통합 CLI
│   │   └── collectors/            # 정부 정책 데이터 수집기
│   │       ├── __init__.py
│   │       ├── base.py            # PolicyCollector 추상 클래스 + Policy 스키마
│   │       ├── youthgo.py         # 온통청년 수집기
│   │       ├── data_portal.py     # 공공데이터포털 API 클라이언트
│   │       ├── kosaf.py           # 한국장학재단 수집기
│   │       └── pdf_reports.py     # 정부 발행 PDF 보고서 수집
│   ├── retrieval/
│   │   ├── __init__.py
│   │   ├── vector_store.py        # FAISS 래퍼
│   │   ├── bm25_store.py          # BM25 키워드 검색
│   │   ├── hybrid.py              # RRF 하이브리드
│   │   ├── reranker.py            # Cross-Encoder
│   │   └── pipeline.py            # 검색 통합 CLI
│   ├── generation/
│   │   ├── __init__.py
│   │   ├── llm_client.py          # LiteLLM 래퍼
│   │   ├── prompt.py              # 프롬프트 템플릿 (정책 도메인)
│   │   └── pipeline.py            # RAG 오케스트레이션
│   ├── evaluation/
│   │   ├── __init__.py
│   │   ├── dataset.py             # QA 데이터셋 로더
│   │   ├── ragas_metrics.py       # RAGAS v0.4
│   │   ├── llm_judge.py           # LLM-as-a-Judge
│   │   ├── safety_metrics.py      # DeepEval
│   │   ├── evaluator.py           # 3단계 통합
│   │   └── report.py              # 비교 리포트
│   └── ui/                        # Streamlit 프론트엔드 (Cloud Run #2)
│       ├── app.py                 # 메인 엔트리 + 사이드바 네비게이션
│       ├── pages/
│       │   ├── 1_policy_explore.py    # 정책 탐색/검색
│       │   ├── 2_chatbot.py           # RAG QnA 챗봇
│       │   ├── 3_policy_compare.py    # 정책 비교
│       │   ├── 4_recommend.py         # 맞춤 정책 추천
│       │   ├── 5_dashboard.py         # 평가 대시보드
│       │   └── 6_about.py             # 프로젝트 소개
│       ├── components/
│       │   ├── __init__.py
│       │   ├── policy_card.py         # 정책 카드 컴포넌트
│       │   ├── filter_sidebar.py      # 필터 사이드바
│       │   ├── chat_message.py        # 채팅 메시지 컴포넌트
│       │   └── metrics_display.py     # 평가 메트릭 표시
│       └── utils/
│           ├── __init__.py
│           ├── session_state.py       # 세션 상태 관리
│           └── style.py              # 커스텀 CSS
├── data/
│   ├── documents/                 # 로컬 원본 PDF (정부 보고서, 개발용 캐시)
│   ├── policies/                  # 로컬 정책 데이터 캐시 (실제 데이터는 GCS)
│   │   ├── raw/                   # 원본 수집 데이터 (→ GCS 업로드)
│   │   └── processed/             # 정규화된 정책 JSON (→ GCS 업로드)
│   ├── index/                     # FAISS 인덱스 + 메타데이터
│   │   ├── faiss.index            # FAISS 벡터 인덱스
│   │   └── metadata.pkl           # 청크 메타데이터 dict
│   ├── eval/
│   │   └── qa_pairs.json          # 평가 데이터셋 (청년 정책)
│   └── results/                   # 평가 결과
├── scripts/
│   └── collect_policies.py        # 정책 데이터 일괄 수집 스크립트
├── tests/
│   ├── __init__.py
│   ├── test_ingestion.py
│   ├── test_collectors.py         # 데이터 수집기 테스트
│   ├── test_retrieval.py
│   ├── test_generation.py
│   └── test_evaluation.py
├── Dockerfile
└── plan.md
```

- [x] pyproject.toml 생성
- [x] .env.example 생성
- [x] 디렉토리 스켈레톤 + `__init__.py`
- [x] `pip install -e ".[dev]"` 동작 확인

### 3.4 GCP 준비

**크레딧 현황** (일회성, 연장 불가):
- CREDIT_TYPE_ANNUAL: ₩715,040
- CREDIT_TYPE_GEMINI: ₩71,504
- **합계: ~₩786,544 (2026-06-19 만료)**

- [x] GCP 계정 — Google Developer Program Premium
- [x] 프로젝트 생성 — `rag-qna-eval`
- [x] API 활성화: Compute Engine, Cloud Run, Cloud Storage, Artifact Registry, Cloud Build, Cloud Scheduler, Cloud Monitoring, Cloud Logging, Vertex AI (Gemini), Eventarc
- [x] `gcloud` CLI 설치 + 인증
- [x] Compute Engine VM 생성 — `rag-mongo-vm` (e2-small, asia-northeast3-a, 20GB, 중지 상태)
- [x] MongoDB 7.0 설치 완료 (Ubuntu 22.04, admin/1129 인증, bindIp: 0.0.0.0)
- [x] 방화벽 규칙 설정 완료 (allow-mongodb, tcp:27017, 0.0.0.0/0, 네트워크 태그: mongodb-server)
- [x] MongoDB Compass 원격 연결 확인 완료 (34.47.80.98:27017, static IP)
- [x] QA 데이터셋 MongoDB 업로드 완료 (`scripts/upload_qa_to_mongo.py` → `rag_youth_policy.qa_pairs` 컬렉션, 메타데이터 1건 + QA 100건)
- [x] GCS 버킷 생성 — `gs://rag-qna-eval-data` (asia-northeast3, STANDARD)
- [x] Compute Engine VM 생성 — `rag-airflow-vm` (e2-standard-2, Ubuntu 24.04 LTS, asia-northeast3-a, 30GB) — Airflow 2.9.3 + PostgreSQL 16 + LocalExecutor + 3 DAGs 배포 완료
- [ ] 예산 알림 ₩200,000 설정
- [ ] Gemini API 키 발급 (₩71,504 크레딧 활용)

### 3.5 API 키

> **방향 전환 (최종, 2026-04-26)**: 프로바이더별 분산 라우팅. OpenAI는 직접 호출, Claude/Gemini는 Vertex AI Model Garden, Llama는 HuggingFace.
> 임베딩은 OpenAI `text-embedding-3-small` (1536차원)을 LiteLLM 경유로 호출.

| API | 필수 | 용도 | 비용 | 라우팅 |
|-----|------|------|------|--------|
| OpenAI | 필수 | GPT-4o-mini/4o (LLM) | 유료 (OPENAI_API_KEY) | LiteLLM `openai/` prefix |
| Google Gemini | 필수 | Gemini 2.5 Flash/Pro + 임베딩 | GCP 크레딧 | Vertex AI Model Garden |
| Anthropic (Claude) | 선택 | Claude Sonnet 4.5 비교 평가 | GCP 크레딧 | Vertex AI Model Garden |
| HuggingFace | 선택 | Llama 3.3 70B | 무료 티어 | LiteLLM `huggingface/` prefix |
| 공공데이터포털 | 필수 | 청년정책 API 데이터 수집 | 무료 | 변경 없음 |

### 3.6 중간 발표 (5분 + Q&A 3분)

1. 문제 정의: LLM hallucination (1분)
2. 솔루션: Hybrid RAG + 3단계 평가 (2분)
3. 아키텍처 다이어그램 (1분)
4. 기대 효과: 모델별 비교, RAG vs No-RAG (1분)

### Phase 0 체크리스트

- [x] 도메인 확정 — 학생/청년 정부 정책 QnA
- [x] 데이터 소스 접근성 검증
  - [x] 온통청년: 내부 검색 API (1,608건 JSON) + Open API 확인
  - [x] 공공데이터포털: `한국고용정보원_온통청년_청년정책API` (15143273) 활용 신청 완료 (승인, .env에 등록 완료.)
  - [x] 한국장학재단: SSR HTML, BeautifulSoup 파싱 가능, k-skill 스키마 참고
  - [x] 온통청년 Open API 별도 발급 불필요 (공공데이터포털 경유 = 동일 데이터, JSON 응답)
- [x] 레포 스켈레톤 세팅 — pyproject.toml, config/, src/, data/, tests/, Dockerfile, CI/CD
- [x] GCP 인프라 준비
  - [x] 프로젝트: `rag-qna-eval`
  - [x] API 활성화: Compute Engine, Cloud Run, Artifact Registry, Cloud Build, Cloud Scheduler, Monitoring, Logging, Vertex AI, Eventarc
  - [x] GCS 버킷: `gs://rag-qna-eval-data` (asia-northeast3)
  - [x] VM: `rag-mongo-vm` (e2-small, 중지 상태 — Phase 1에서 시작)
  - [x] VM: `rag-airflow-vm` (e2-standard-2, Ubuntu 24.04 LTS) — Airflow 2.9.3 + PostgreSQL 16 + 3 DAGs (collect_and_index, evaluation_pipeline, qa_generation)
  - [ ] 예산 알림 ₩200,000 설정
- [x] 멀티클라우드 전략 문서화 — `docs/multi-cloud.md` (캡스톤 팀 AWS 연동)
- [x] 초기 데이터 50건 수집 테스트 — 온통청년 내부 API, 50건 수집, 주요 필드 채움률 100%
- [x] RAGAS v0.4 검증 — v0.4.3 설치, 메트릭 임포트/SingleTurnSample/ascore 메서드 전부 PASS (`scripts/verify_ragas_v04.py`)
- [x] API 키: 공공데이터포털 승인 완료 (.env 등록) / Gemini API 키 — Vertex AI 전환으로 불필요
- [x] Vertex AI Model Garden 전환 완료 — `config/models.py` vertex_ai/ prefix, SA 인증 통일
- [ ] GCP 예산 알림 ₩200,000 설정 (GCP 콘솔에서 직접)
- [ ] 중간 발표 슬라이드
- [ ] 4/15 보고서 제출

---

## 4. Phase 1: 데이터 수집 + 문서 파이프라인 (Week 1)

### 4.1 pyproject.toml

```toml
[project]
name = "rag-youth-policy"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = [
    "litellm>=1.50",
    "faiss-cpu>=1.8",
    "pymongo>=4.8",
    "pymupdf>=1.24",
    "rank-bm25>=0.2",
    "sentence-transformers>=3.0",
    "ragas>=0.4,<0.5",
    "deepeval>=1.0",
    "python-dotenv>=1.0",
    "pydantic>=2.0",
    "pydantic-settings>=2.0",
]

[project.optional-dependencies]
dev = ["pytest>=8.0", "ruff>=0.6"]
viz = ["matplotlib>=3.8", "plotly>=5.0", "pandas>=2.0"]
ko = ["kss>=6.0", "mecab-python3>=1.0"]
api = ["fastapi>=0.115", "uvicorn>=0.30"]
ui = ["streamlit>=1.38", "httpx>=0.27"]
crawl = [
    "httpx>=0.27",
    "beautifulsoup4>=4.12",
]
```

### 4.2 config/settings.py

```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    openai_api_key: str = ""
    anthropic_api_key: str = ""
    google_api_key: str = ""
    data_portal_api_key: str = ""          # 공공데이터포털
    mongodb_uri: str = "mongodb://MONGO_VM_IP:27017"  # GCP Compute Engine VM
    mongodb_db: str = "rag_youth_policy"
    embedding_model: str = "text-embedding-3-small"
    embedding_dim: int = 1536
    chunk_size: int = 512
    chunk_overlap: int = 50
    top_k: int = 10
    rerank_top_k: int = 5
    default_model: str = "openai/gpt-4o-mini"

    model_config = {"env_file": ".env"}
```

### 4.3 config/models.py

> **방향 전환 (2026-04-22)**: 개별 API 키(OpenAI, Anthropic) 대신 **Vertex AI Model Garden** 경유로 전환 예정.
> LiteLLM의 `vertex_ai/` prefix를 사용하면 코드 변경 최소화 + GCP SA 인증 하나로 통일 + 비용이 GCP 크레딧에서 통합 관리됨.
> 사전 확인 필요: asia-northeast3 리전 파트너 모델(Claude, Llama) 가용성 + Model Garden 활성화 절차.

```python
# 현재 (멀티 프로바이더 — 수정 2026-04-26)
MODELS = {
    "gpt-4o-mini": {"id": "openai/gpt-4o-mini", "temperature": 0.0, "max_tokens": 2048},
    "gpt-4o":      {"id": "openai/gpt-4o", "temperature": 0.0, "max_tokens": 2048},
    "claude-sonnet": {"id": "vertex_ai/claude-sonnet-4-5", "temperature": 0.0, "max_tokens": 2048},
    "gemini-flash": {"id": "vertex_ai/gemini-2.5-flash", "temperature": 0.0, "max_tokens": 2048},
    "gemini-pro":  {"id": "vertex_ai/gemini-2.5-pro", "temperature": 0.0, "max_tokens": 2048},
    "llama3":      {"id": "huggingface/meta-llama/Llama-3.3-70B-Instruct", "temperature": 0.0, "max_tokens": 2048},
}
# GPT-4o/GPT-4o-mini → OpenAI API 직접 호출 (OPENAI_API_KEY)
# Claude/Gemini → Vertex AI Model Garden (GCP 크레딧 통합 과금)
# Llama 3.3 → HuggingFace Inference API
```

### 4.4 src/ingestion/collectors/ — 정책 데이터 수집기

**아키텍처**:
```
데이터 소스               수집기                    정규화              저장
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
온통청년 (HTML)    →  YouthGoCollector      →                  ┬→ GCS (원본 JSON)
공공데이터포털 (API) →  DataPortalCollector   →  PolicyNormalizer ┤  gs://bucket/policies/raw/<source>/latest.json
한국장학재단 (HTML) →  KosafCollector        →                  ┤  gs://bucket/policies/raw/<source>/snapshots/<timestamp>.json
정부 PDF 보고서    →  PdfReportCollector    →                  ┘
                                                              ├→ gs://bucket/policies/processed/all_policies.json
                                                              ├→ gs://bucket/policies/processed/by_source/*.json
                                                              ├→ gs://bucket/policies/processed/by_category/*.json
                                                              └→ MongoDB (메타데이터만)
                                                                 policy_id, title, category,
                                                                 gcs_path, status, last_updated

GCS (정규화 정책 JSON)  →  chunker  →  embedder  →  FAISS index + metadata.pkl  →  GCS 업로드
                                                     gs://bucket/index/
                                                         ↓
Cloud Run (앱 기동 시 GCS에서 FAISS index 다운로드 → 인메모리 검색)
```

**저장소 역할 분리**:
- **GCS (실제 데이터)**: 정책 원본 `raw/<source>/latest.json`, 시점별 `snapshots/`, 정규화 문서 `processed/`, QA 프롬프트 `prompts/`, FAISS 인덱스
- **MongoDB (메타데이터만)**: 정책 목록, 수집 이력, 상태 관리 (gcs_path로 실제 데이터 참조)

**현재 GCS 버킷 구조**:

```text
gs://rag-qna-eval-data/
├── prompts/
│   └── qa_generation_system.txt
├── policies/
│   ├── raw/
│   │   └── <source>/
│   │       ├── latest.json
│   │       └── snapshots/<timestamp>.json
│   └── processed/
│       ├── all_policies.json
│       ├── manifest.json
│       ├── by_source/*.json
│       └── by_category/*.json
└── index/
    ├── faiss.index
    └── metadata.pkl
```

**지속적 데이터 수집 흐름 (Airflow 오케스트레이션)**:

> **방향 전환 (2026-04-25)**: Cloud Scheduler + Eventarc 이벤트 드리븐 → **Apache Airflow (self-hosted VM)** 기반 DAG 오케스트레이션으로 전환.
> Cloud Composer는 ~₩367K/월로 크레딧 대비 과도 → e2-standard-2 VM에 직접 설치 (~₩67K/월).

```
Airflow VM (e2-standard-2, rag-airflow-vm)
  │
  ├── DAG 1: 데이터 수집 + 인덱싱 (매일 1회)
  │     Task 1: 수집기 실행 → GCS (원본 저장) + MongoDB (메타데이터 upsert)
  │     Task 2: FAISS 인덱스 재빌드 → GCS 업로드
  │     Task 3: Cloud Run BE 서비스 재시작 (최신 인덱스 로드)
  │
  ├── DAG 2: 평가 파이프라인 (수동/주간)
  │     Task 1: QA 데이터셋 로드
  │     Task 2: 모델별 × 전략별 RAG 실행
  │     Task 3: RAGAS + LLM Judge + DeepEval 평가
  │     Task 4: 결과 리포트 저장 (JSON + HTML)
  │
  └── DAG 3: QA 데이터셋 생성 (수동)
        Task 1: 신규 정책 데이터 로드
        Task 2: LLM으로 QA 쌍 자동 생성
        Task 3: 검수 결과 저장
```

Airflow의 태스크 의존성 관리로 수집→인덱싱→서빙 체이닝이 명시적이고,
실패 시 개별 태스크 재시도 + Airflow UI에서 실행 이력/로그 모니터링이 가능합니다.

#### Cloud Run Jobs → Airflow 전환 배경

초기 설계에서는 Cloud Run Jobs + Cloud Scheduler + Eventarc 조합으로 이벤트 드리븐 오케스트레이션을 계획했다 (`Dockerfile.collector`, `Dockerfile.indexer`, `deploy-jobs.yml` 등 CI/CD 정의까지 완료). 그러나 실제 구현 과정에서 다음 문제가 드러나 Apache Airflow(self-hosted VM)로 전환했다.

| 문제 | Cloud Run Jobs 한계 | Airflow 해결 |
|------|---------------------|-------------|
| **태스크 체이닝** | 수집→인덱싱→BE 재시작 3단계를 Eventarc로 연결하면 이벤트 설계가 복잡하고, 중간 실패 시 체인 전체 재시도가 어렵다 | DAG에서 `>>` 연산자로 의존성 명시. 실패 태스크만 개별 재시도 |
| **데이터 전달** | Job 간 데이터 전달에 GCS 중간 파일 또는 별도 메시지 큐가 필요 | XCom으로 태스크 간 결과 dict 자동 전달 |
| **모니터링** | Cloud Logging에서 Job별 로그를 수동 필터링해야 한다 | Airflow Web UI에서 DAG 실행 이력, 태스크별 로그, Gantt 차트 즉시 확인 |
| **스케줄 유연성** | Cloud Scheduler cron만 지원. 수동 실행 시 별도 트리거 설정 필요 | cron + 수동 트리거 + `params` 기반 동적 인자 전달 기본 제공 |
| **비용** | Cloud Run Jobs 자체는 저렴하나 Cloud Composer(관리형 Airflow)는 ~₩367K/월 | e2-standard-2 VM 직접 설치 ~₩67K/월 (Cloud Composer 대비 82% 절감) |
| **개발 속도** | 이벤트 드리븐 설계는 디버깅 사이클이 길다 (배포→트리거→로그 확인) | 로컬 airflow CLI로 즉시 테스트 가능 (`airflow tasks test`) |

**전환 결과**: Cloud Run Jobs의 CI/CD 정의(`deploy-jobs.yml`, `Dockerfile.collector`, `Dockerfile.indexer`)는 인프라 코드로 보존하되, 실제 데이터 파이프라인은 Airflow VM에서 직접 Python 태스크로 실행한다. DAG 3개 (수집+인덱싱/평가/QA 생성)가 운영 중이며, 5분마다 git pull로 DAG 코드를 자동 동기화한다.

#### 운영 이슈: pecab → mecab 전환 (청킹 성능 개선)

Airflow VM에서 `rebuild_index` task 실행 시, kss 문장 분리기가 pecab (순수 Python) 백엔드로 폴백되어 SIGTERM 타임아웃 위험이 발생했다.

| 항목 | 내용 |
|------|------|
| **증상** | `WARNING - Kss will take pecab as a backend` + 청킹 단계 극도로 느림 |
| **원인** | `python-mecab-kor` 패키지가 빌드 스크립트에서 `sudo apt-get` 실행 → airflow 사용자(비-root)로 pip install 불가 |
| **해결** | ① `pyproject.toml` `[ko]` extra: `python-mecab-kor` → `mecab-python3` (pre-built wheel, sudo 불필요) ② `chunker.py`: pecab 건너뛰고 `mecab → punct → regex` 폴백 체인으로 변경 ③ Airflow VM에 `mecab-python3` 설치 + 스케줄러 재시작 |
| **결과** | kss mecab 백엔드 (C++ 기반) 정상 동작, 청킹 성능 대폭 개선, pecab 경고 제거 |

**MongoDB 컬렉션 구조** (메타데이터 전용):
- `policies`: 정책 메타데이터 (policy_id, title, category, gcs_path, status, last_updated, source_name)
- `ingestion_logs`: 수집 이력 (소스, 시간, 건수, 상태, gcs_paths, 인덱스 동기화 정보)
- `api_usage_logs`: LLM API 호출 이력 (모델, 토큰, 비용, 레이턴시)

**MongoDB GUI**: 로컬 Mac의 Compass로 GCP VM(MongoDB)에 연결하여 메타데이터 현황 모니터링.
실제 문서 데이터는 GCS에 저장되며, MongoDB에는 gcs_path 참조만 보관.

**Policy 표준 스키마** (`collectors/base.py`):
```python
@dataclass(frozen=True)
class Policy:
    policy_id: str                    # 고유 ID
    title: str                        # 정책명
    category: str                     # housing/employment/startup/education/welfare/finance
    summary: str                      # 한줄 요약
    description: str                  # 상세 설명
    eligibility: str                  # 신청 자격
    benefits: str                     # 지원 내용/금액
    how_to_apply: str                 # 신청 방법
    application_period: str           # 신청 기간
    managing_department: str          # 주관 부처/기관
    target_age: tuple[int, int]       # 대상 연령 범위 (예: (19, 34))
    region: str                       # 지역 (전국/서울/경기 등)
    source_url: str                   # 원본 URL
    source_name: str                  # 출처명
    last_updated: str                 # 최종 업데이트일
    raw_content: str                  # 전체 원문 텍스트 (청킹용)
```

**수집기별 구현**:

| 수집기 | 방법 | 우선순위 | 리스크 |
|--------|------|---------|--------|
| `youthgo.py` | httpx + BeautifulSoup 크롤링 | 1차 | JS 렌더링 필요 시 playwright |
| `data_portal.py` | REST API (data.go.kr) | 1차 | 가장 안정적 |
| `kosaf.py` | httpx + BeautifulSoup 크롤링 | 2차 | 구조 변경 가능 |
| `pdf_reports.py` | 직접 다운로드 + PyMuPDF | 3차 | 수동 수집 |

크롤링 규칙: robots.txt 준수, 요청 간격 2~3초, User-Agent 설정.

**수집 실행**:
```bash
# 정책 수집 → GCS 원본 저장 + MongoDB 메타데이터 기록
python scripts/collect_policies.py --all
python scripts/collect_policies.py --source youthgo

# GCS 원본 → 청킹 → 임베딩 → FAISS 인덱스 빌드
python -m src.ingestion.pipeline --output data/index/

# FAISS 인덱스를 GCS에 업로드 (Cloud Run 배포용)
gsutil cp data/index/faiss.index gs://rag-qna-eval-data/index/
gsutil cp data/index/metadata.pkl gs://rag-qna-eval-data/index/
```

### 4.5 src/ingestion/loader.py

- `Document` dataclass: content, metadata (source, url, category, policy_id, last_updated)
- `load_pdf(path) -> list[Document]`: PyMuPDF 페이지별 추출 (정부 보고서)
- `load_txt(path) -> Document`
- `load_json(path) -> list[Document]`: 정규화된 정책 JSON 로드
- `load_directory(dir_path) -> list[Document]`
- 입력 검증: 파일 존재, 빈 파일 처리, 인코딩 검증 (EUC-KR/UTF-8)

정부 사이트는 텍스트 PDF + HTML 혼합 → loader는 PDF/TXT/JSON 모두 지원.
수집기 결과는 GCS에 원본 저장 + MongoDB에 메타데이터 기록. 인덱싱 시 GCS에서 문서를 읽어서 처리.

### 4.6 src/ingestion/chunker.py

- `Chunk` dataclass: content, metadata (source, page, chunk_index, start_char, end_char, category, policy_id)
- 정책 구조 인식 청킹: 제목/신청자격/지원내용/신청방법 등 섹션별 구분 가능 시 섹션 단위 우선
- 일반 분할: 문장 경계 기반 (한국어 `kss` + mecab 백엔드, 영어 기본 분리)
- 폴백 체인: `mecab → punct → regex` (pecab은 순수 Python으로 배치 처리에 너무 느려서 제외)
- 기본 512 토큰, 오버랩 50 토큰
- `chunk_documents(documents, chunk_size, chunk_overlap) -> list[Chunk]`
- 엣지 케이스: 빈 문서, 짧은 문서, 긴 단일 문장
- 한국어 토큰 카운트: `tiktoken`으로 정확 계산
- 메타데이터에 category, policy_id 포함 → 필터링 검색 가능

### 4.7 src/ingestion/embedder.py

- LiteLLM embedding API 래퍼
- `embed_texts(texts: list[str]) -> list[list[float]]`
- 배치 처리 + rate limit 재시도
- 차원 검증 (1536)

### 4.8 src/ingestion/pipeline.py

```bash
python -m src.ingestion.pipeline --output data/index/
```

GCS에서 정책 문서 로드 → 청킹 → 임베딩 → FAISS 인덱스 빌드 + metadata.pkl 저장.

### 4.9 tests/test_ingestion.py + test_collectors.py

| 테스트 | 검증 |
|--------|------|
| 청크 크기 | 토큰 제한 준수 |
| 오버랩 | 인접 청크 중복 영역 |
| 빈 문서 | 빈 리스트 반환 |
| 짧은 문서 | 청크 1개로 처리 |
| 메타데이터 | source, category, policy_id 보존 |
| 임베딩 차원 | 1536 |
| JSON 로더 | 정책 JSON 로드/파싱 |
| Policy 스키마 | 필수 필드 검증 |
| 수집기 | 각 소스별 수집 + 정규화 (mock HTTP) |

OpenAI API는 mock 처리 (비용 절약). 수집기는 httpx mock으로 테스트.

### Phase 1 완료 기준

- [x] `pytest tests/test_ingestion.py tests/test_collectors.py` 통과 — 62 passed
- [x] 수집기로 정책 50건 이상 수집 — data_portal 2,185건 + youthgo 50건 (로컬 저장 완료, GCS 업로드/MongoDB 기록은 실연결 시 검증 필요)
- [x] 로컬 청킹 → 임베딩 → FAISS 인덱스 빌드 동작 — faiss.index (16.5MB) + metadata.pkl (3MB) 생성 완료
- [x] Compass에서 MongoDB 메타데이터 확인 가능 (Compass 연결 + qa_pairs 컬렉션 확인 완료)
- [x] 저장된 청크 수 확인 가능 — metadata.pkl에 청크 메타데이터 포함
- [x] GCS 업로드 검증 — `index/faiss.index`, `index/metadata.pkl`, `policies/raw/` 모두 업로드 완료
- [x] MongoDB 실연결 검증 완료 (pymongo + Compass, QA 데이터셋 업로드 성공)

---

## 5. Phase 2: 검색 시스템 (Week 2)

### 5.1 src/retrieval/vector_store.py

- FAISS 래퍼 클래스
- `SearchResult` dataclass: content, metadata, score
- `load_index(index_path, metadata_path)`: FAISS 인덱스 + 메타데이터 dict 로드
- `build_index(chunks, embeddings)`: 인덱스 빌드 + pickle 저장
- `search(query_embedding, top_k) -> list[SearchResult]`: L2/코사인 유사도
- 메타데이터 필터링: category별 사후 필터 (dict comprehension)

### 5.2 src/retrieval/bm25_store.py

- `rank_bm25` 기반 키워드 검색
- 한국어: 공백 분리 → 시간 여유 시 konlpy/mecab 추가
- `add_documents(chunks)` / `search(query, top_k)`

### 5.3 src/retrieval/hybrid.py — RRF

```
Score(doc) = Σ 1/(k + rank_i)    (k=60)
```

- Vector Search → top_k×2 후보
- BM25 Search → top_k×2 후보
- RRF 점수 병합 → 상위 top_k 반환
- `vector_weight`, `bm25_weight` 조정 가능

### 5.4 src/retrieval/reranker.py

| 모델 | 크기 | 한국어 | 우선순위 |
|------|------|--------|---------|
| `cross-encoder/ms-marco-MiniLM-L-6-v2` | 23MB | 보통 | 1차 시도 |
| `BAAI/bge-reranker-v2-m3` | 570MB | 우수 | 한국어 미달 시 전환 |

후보 20개 → Cross-Encoder 점수 → 상위 5개.

### 5.5 src/retrieval/pipeline.py

```bash
python -m src.retrieval.pipeline --query "질문" --strategy hybrid_rerank
```

| 전략 | 파이프라인 |
|------|----------|
| `vector_only` | Vector Search → Top-K |
| `bm25_only` | BM25 → Top-K |
| `hybrid` | Vector+BM25 → RRF → Top-K |
| `hybrid_rerank` | Vector+BM25 → RRF → Reranker → Top-K |

### 5.6 tests/test_retrieval.py

벡터 검색, BM25 매칭, RRF 계산 정확성, 리랭킹 순서 변경, 4전략 통합 동작.

### Phase 2 완료 기준

- [x] Query → Top-5 관련 문서 반환
- [x] 4가지 검색 전략 모두 동작 (vector_only, bm25_only, hybrid, hybrid_rerank)
- [x] `pytest tests/test_retrieval.py` 통과 — 20 passed, 코드리뷰 완료

---

## 6. Phase 3: 답변 생성 (Week 3)

### 6.1 src/generation/llm_client.py

- LiteLLM 통합 클라이언트
- `LLMResponse` dataclass: content, model, usage (tokens), latency
- `generate(model, messages, temperature, max_tokens) -> LLMResponse`
- rate limit 재시도 (exponential backoff), timeout, API 키 누락 처리
- 스트리밍 응답 지원

### 6.2 src/generation/prompt.py

**프롬프트 구조**:
```
[System]  "당신은 대한민국 청년 정책 전문 상담사입니다."
         규칙: 제공된 정책 문서에 있는 정보만 답변. 정책명과 출처 명시.
         인용 형식: [출처: 정책명, 관할부처]
[Context] [1] 청년 월세 지원 요약 (출처: 온통청년) / [2] 신청 자격 상세 ...
[Query]   사용자 질문
```

- `build_rag_prompt(query, contexts) -> list[Message]`
- `build_no_rag_prompt(query) -> list[Message]` (비교 실험용)
- 한국어 전용 (정부 정책 도메인)

### 6.3 src/generation/pipeline.py

```bash
python -m src.generation.pipeline \
  --query "청년 월세 지원 신청 자격이 뭐야?" \
  --model openai/gpt-4o-mini \
  --strategy hybrid_rerank
```

- `RAGPipeline.run(query, model, strategy) -> RAGResponse`
- `RAGResponse`: answer, sources, model, latency
- 흐름: Query → Retrieve → Build Prompt → Generate → Parse

### 6.4 tests/test_generation.py

파이프라인 통합 (mock LLM), 모델 전환, 출처 인용 포함, No-RAG 모드, 빈 검색 결과.

### Phase 3 완료 기준

- [x] 정책 질문 → 검색 → 답변 + 출처 인용(정책명, 관할부처) 동작
- [x] 4개 모델 전환 가능 (GPT-4o-mini, GPT-4o, Gemini Flash, Ollama)
- [x] `pytest tests/test_generation.py` 통과 — 21 passed (전체 151 passed)

---

## 7. Phase 4: 평가 파이프라인 (Week 4) ★ 핵심

> 이 Phase가 프로젝트 차별화 포인트다.
> 3단계 평가가 제대로 동작해야 발표에서 강한 인상을 줄 수 있다.

### 7.1 QA 데이터셋 ★ Phase 3부터 병행 작성

**파일**: `data/eval/qa_pairs.json`

```json
{
  "version": "1.0",
  "domain": "youth_policy",
  "categories": ["housing", "employment", "startup", "education", "welfare", "finance"],
  "samples": [
    {
      "id": "q001",
      "question": "청년 월세 한시 특별지원 신청 자격은?",
      "ground_truth": "만 19~34세 독립거주 무주택 청년으로, 청년가구 소득이 기준 중위소득 60% 이하이고 원가구 소득이 기준 중위소득 100% 이하인 경우 신청 가능하다.",
      "reference_doc": "youth_monthly_rent_support.json",
      "reference_source": "온통청년",
      "difficulty": "easy",
      "category": "housing"
    },
    {
      "id": "q002",
      "question": "국가장학금 1유형과 2유형의 차이는?",
      "ground_truth": "1유형은 소득연계형으로 경제적 여건이 어려운 학생에게 지원하고, 2유형은 대학연계형으로 대학 자체 지원과 연계하여 지원한다.",
      "reference_doc": "kosaf_scholarship.json",
      "reference_source": "한국장학재단",
      "difficulty": "medium",
      "category": "education"
    },
    {
      "id": "q003",
      "question": "청년내일저축계좌에 가입한 사람이 청년도약계좌에도 동시 가입할 수 있는가?",
      "ground_truth": "청년내일저축계좌와 청년도약계좌는 동시 가입이 불가능하다. 하나를 해지한 후 다른 계좌에 가입해야 한다.",
      "reference_doc": "youth_savings_accounts.json",
      "reference_source": "복지로",
      "difficulty": "hard",
      "category": "finance"
    }
  ]
}
```

| 항목 | 목표 |
|------|------|
| 총 QA 쌍 | 최소 50개, 목표 100개 |
| 난이도 | easy 40%, medium 40%, hard 20% |
| 카테고리 | housing, employment, startup, education, welfare, finance |
| QA 유형 | factual (자격/조건), reasoning (비교/판단), comparison (정책 간 비교) |

**카테고리별 QA 예시** (각 카테고리 최소 8개):

| 카테고리 | 예시 질문 | 난이도 |
|----------|---------|--------|
| housing | "청년 전세자금 대출 금리는?" | easy |
| housing | "청년 월세 지원과 주거급여를 동시에 받을 수 있나?" | hard |
| employment | "국민취업지원제도 1유형 참여 조건은?" | easy |
| employment | "일경험 프로그램과 인턴십의 차이는?" | medium |
| startup | "청년창업사관학교 지원 자격은?" | easy |
| education | "국가장학금 소득분위별 지원금액은?" | medium |
| welfare | "청년 건강검진 무료 대상은?" | easy |
| finance | "청년도약계좌 정부기여금 매칭 비율은?" | medium |

**QA 데이터셋 생성 전략: LLM 자동 생성 + 수동 검수**

수동 작성 대신 수집된 정책 원본 데이터를 LLM에 입력하여 QA 쌍을 자동 생성한다.

**생성 파이프라인**:

```
정책 원본 (수집 완료)                    LLM 자동 생성                     수동 검수
━━━━━━━━━━━━━━━━━━━━    →    ━━━━━━━━━━━━━━━━━━━━━━━    →    ━━━━━━━━━━━━━━━
data/policies/processed/          scripts/generate_qa.py              사람이 검수
all_policies.json                 GCS prompt 기반 생성               - 사실 확인
(정책 텍스트 2,185건)              - 정책 1건 → QA 2~3쌍              - 난이도 조정
                                  - 난이도/카테고리 지정               - 중복 제거
                                  - ground_truth 포함                 → data/eval/qa_pairs.json
```

**프롬프트 설계**:

```
역할: 한국 학생·청년 대상 정책 정보 플랫폼의 평가 데이터셋 생성 전문가
입력: 정책 원본 텍스트 (제목, 요약, 지원내용, 신청자격 등)
출력: QA 쌍 (question, ground_truth, difficulty, category, qa_type)

생성 규칙:
1. 정책 텍스트에 근거한 답변만 생성 (환각 방지)
2. 지역/연도/회차 공고성 질문은 최소화
3. 난이도 분배: easy 40%, medium 40%, hard 20%
4. 질문은 실제 학생/청년이 챗봇에 물을 법한 자연스러운 한국어
5. ground_truth는 정책 텍스트에서 직접 발췌/요약
```

- 운영 source of truth: `gs://rag-qna-eval-data/prompts/qa_generation_system.txt`
- QA 결과 JSON에 `prompt.gcs_uri`, `prompt.sha256` 기록

**검수 기준**:
- ground_truth가 원본 정책 텍스트에 근거하는가?
- 질문이 모호하거나 중복되지 않는가?
- 답변이 충분히 구체적인가?
- 카테고리/난이도 라벨이 적절한가?

**비용 추정** (GPT-4o-mini 기준):
- 정책 50건 × QA 2쌍 = 100쌍 생성
- 입력 ~500토큰/정책 + 출력 ~300토큰/QA쌍 ≈ 총 ~80K 토큰
- 예상 비용: ~$0.01 (무시 가능)

**✅ QA 데이터셋 생성 완료** (2026-04-22):
- `scripts/generate_qa.py`로 100쌍 자동 생성 → `data/eval/qa_pairs.json`
- 4개 카테고리 (housing, employment, education, welfare) × 난이도 3단계
- `tests/test_generate_qa.py` 테스트 포함 (32 passed)

### 7.2 Stage 1: RAGAS v0.4 정량 평가

**파일**: `src/evaluation/ragas_metrics.py`

| 메트릭 | 측정 | 동작 | Target |
|--------|------|------|--------|
| Faithfulness | 생성 | 답변→claim 분해→컨텍스트 NLI | ≥ 0.85 |
| AnswerRelevancy | 생성 | 답변→역질문→원래 질문 유사도 | ≥ 0.80 |
| ContextPrecision | 검색 | 검색 문서별 관련성→AP | ≥ 0.75 |
| ContextRecall | 검색 | 정답→statement→컨텍스트 확인 | ≥ 0.80 |

- `evaluate_ragas(question, context, answer, ground_truth) -> dict`
- NaN 처리: try/except → None + 로깅
- **pyproject.toml에 `ragas>=0.4,<0.5` pinning 필수**

### 7.3 Stage 2: LLM-as-a-Judge 정성 평가

**파일**: `src/evaluation/llm_judge.py`

G-Eval 방식 커스텀 판정:

| 평가 항목 | 점수 |
|----------|------|
| 인용 정확성 — 답변 인용이 컨텍스트와 일치하는가 | 1-5 |
| 답변 완결성 — 질문에 빠짐없이 답했는가 | 1-5 |
| 가독성 — 읽기 쉽고 구조적인가 | 1-5 |

편향 완화:
- Position Bias → 순서 바꿔 2회 평가 평균
- Verbosity Bias → "길이가 아닌 정확성 기준" 명시
- Self-Enhancement → 생성 모델 ≠ judge 모델

- `judge_response(question, context, answer, judge_model) -> JudgeResult`
- Judge 모델: GPT-4o-mini, temperature=0, JSON 출력

### 7.4 Stage 3: DeepEval 안전성 평가

**파일**: `src/evaluation/safety_metrics.py`

RAGAS와 다른 관점:
```
RAGAS Faithfulness:     "증거 없음" = 불충실
DeepEval Hallucination: "명시적 모순" = hallucination

예시: Context "청년 월세 지원금 월 20만원" / 답변 "월 20만원, 최대 12개월, 전세도 가능"
  Faithfulness:  0.33 ("최대 12개월", "전세도 가능" 증거 없음)
  Hallucination: 0.00 (명시적 모순은 아님)
  → 둘 다 써야 정확
```

- `evaluate_safety(question, context, answer) -> SafetyResult`

### 7.5 src/evaluation/evaluator.py — 3단계 통합

```python
class RAGEvaluator:
    def evaluate_single(self, question, context, answer, ground_truth):
        ragas = evaluate_ragas(...)      # Stage 1
        judge = judge_response(...)      # Stage 2
        safety = evaluate_safety(...)    # Stage 3
        return EvalResult(ragas, judge, safety, latency)

    def evaluate_batch(self, dataset, models, strategies):
        # 모든 모델 × 전략 × QA 쌍
        # tqdm 진행 표시 + 중간 저장 (실패 시 재개)
```

### 7.6 src/evaluation/report.py

출력: JSON (data/results/) + HTML (시각화) + 콘솔 텍스트

시각화: 모델별 heatmap, 전략별 bar chart, RAG vs No-RAG, 실패 케이스 테이블.

### Phase 4 완료 기준

- [x] RAGAS 4대 메트릭 자동 산출
- [x] LLM Judge 동작
- [x] DeepEval Hallucination Score 산출
- [x] 3단계 종합 리포트 자동 생성 (JSON + HTML + 콘솔 요약)
- [x] `pytest tests/test_evaluation.py` 통과 — 26 passed (전체 177 passed)

---

## 8. Phase 5: 제품 수준 UI 구현 (Week 5)

> 단순 QnA 챗봇이 아니라, 청년 정책을 탐색/검색/비교/추천할 수 있는 **제품 수준 앱**을 만든다.
> Streamlit 멀티 페이지 구조 활용.

### 8.1 페이지 구성 (6페이지)

| 페이지 | 파일 | 핵심 기능 | 우선순위 |
|--------|------|----------|---------|
| 정책 탐색 | `1_policy_explore.py` | 카테고리별 검색/필터링/카드 리스트 | ★★★★★ |
| QnA 챗봇 | `2_chatbot.py` | RAG 기반 대화형 정책 질의응답 | ★★★★★ |
| 정책 비교 | `3_policy_compare.py` | 2~3개 정책 나란히 비교 | ★★★ |
| 맞춤 추천 | `4_recommend.py` | 사용자 프로필 기반 정책 추천 | ★★★★ |
| 평가 대시보드 | `5_dashboard.py` | 모델별/전략별 성능 비교 시각화 | ★★★★ |
| 프로젝트 소개 | `6_about.py` | 아키텍처, 기술 스택, 데이터 출처 | ★★ |

### 8.2 Page 1: 정책 탐색 (`1_policy_explore.py`)

- 카테고리 탭 (주거/취업/창업/교육/복지/금융)
- 검색 바 (키워드 검색 — BM25 또는 벡터 검색 활용)
- 필터: 카테고리, 대상 연령, 소득 분위, 지역, 신청 가능 여부
- 정렬: 최신순, 마감일순
- **정책 카드 리스트** (제목, 요약, 카테고리 태그, 신청기간, 지원금액)
- 카드 클릭 → 상세 정보 expander

구현: `st.tabs()` 카테고리 + `st.text_input()` 검색 + `st.columns()` 카드 그리드.
MongoDB에서 메타데이터 조회 (`db.policies.find({"category": "housing"})`) → 상세 내용은 gcs_path로 GCS에서 로드.
FAISS 벡터 검색 활용.

### 8.3 Page 2: QnA 챗봇 (`2_chatbot.py`)

- **채팅 인터페이스** (`st.chat_message` + `st.chat_input`)
- 사이드바: 모델 선택, 검색 전략 선택
- 답변에 **출처 정책 링크** 포함 — [출처: 정책명, 관할부처]
- 사이드바에 검색된 문서 원문 표시
- **신뢰성 점수 실시간 표시** (Faithfulness, Relevancy 게이지)
- 답변 하단 "관련 정책 더보기" (정책 탐색 페이지 연결)
- 대화 히스토리 유지 (`st.session_state.messages`)
- **예시 질문 버튼** ("이런 질문을 해보세요")
- 스트리밍 응답 (LiteLLM streaming + `st.write_stream`)

### 8.4 Page 3: 정책 비교 (`3_policy_compare.py`)

- 2~3개 정책 나란히 비교 테이블
- 비교 항목: 지원 대상, 지원 내용, 신청 방법, 지원 금액, 신청 기간, 주관 부처
- `st.selectbox()`로 비교할 정책 선택
- 차이점 하이라이트
- 시간 여유 시 구현 (MVP: `st.columns()` + `st.dataframe()`)

### 8.5 Page 4: 맞춤 추천 (`4_recommend.py`)

- 사용자 프로필 입력 폼: 나이, 소득 분위, 거주 지역, 취업 상태, 관심 분야
- `st.form()` + `st.slider()` + `st.selectbox()` + `st.multiselect()`
- 입력 기반 메타데이터 필터링 (MongoDB 메타데이터 query) → 해당 자격 정책 추천 → 상세는 GCS에서 로드
- 추천 결과를 카드 형태로 표시
- 선택적: LLM에게 추천 이유 생성 (시간 여유 시)

### 8.6 Page 5: 평가 대시보드 (`5_dashboard.py`)

- 모델별 성능 비교 차트 (bar chart, heatmap) — `st.plotly_chart()`
- 검색 전략별 비교 차트
- RAG vs No-RAG 비교
- 개별 QA 쌍 평가 결과 테이블 (검색/필터 가능) — `st.dataframe()`
- 실패 케이스 분석
- `data/results/` JSON 파일 로드

### 8.7 공통 컴포넌트

| 컴포넌트 | 파일 | 역할 |
|----------|------|------|
| PolicyCard | `policy_card.py` | 정책 카드 렌더링 (제목, 요약, 태그, 신청기간) |
| FilterSidebar | `filter_sidebar.py` | 카테고리/연령/소득/지역 필터 위젯 |
| ChatMessage | `chat_message.py` | 답변 + 출처 + 신뢰성 점수 포맷 |
| MetricsDisplay | `metrics_display.py` | 평가 점수 시각적 표시 (게이지/미터) |

### 8.8 커스텀 스타일 (`utils/style.py`)

- Streamlit 기본 테마를 넘는 커스텀 CSS
- 정책 카드 그리드 레이아웃
- 카테고리별 컬러 태그
- 모바일 반응형 고려

### Phase 5 완료 기준

- [x] 6개 페이지 모두 동작 (최소 챗봇 + 정책 탐색 + 추천 + 대시보드 4개 필수) — 4페이지 구현 완료
- [x] 정책 카드에서 상세 정보 확인 가능 — 14개 필드 표시, 지역 코드→지역명 변환, XSS 방지
- [x] 챗봇에서 출처 인용 + 신뢰성 점수 표시 — 출처 expander + 토큰/레이턴시 표시
- [x] 필터링/검색으로 원하는 정책 탐색 가능 — 카테고리 탭 필터 + 페이지네이션
- [x] 로컬에서 전체 앱 동작 확인

---

## 9. Phase 6: GCP 배포 + 실험 및 최종 리포트 (Week 6)

### 9.0 GCP Cloud Run 배포

#### GCP 인프라 구성

```
┌──────────────────────────────────────────────────────────────────────────┐
│ GCP (asia-northeast3, 서울)                                              │
│                                                                          │
│  Cloud Run #1 (BE)                Cloud Run #2 (FE)                     │
│  ┌──────────────────┐            ┌──────────────────┐                   │
│  │  FastAPI          │ ←─ HTTP ─ │  Streamlit        │                   │
│  │  FAISS 인메모리    │   API     │  httpx → BE 호출   │                   │
│  │  Memory: 2Gi      │           │  Memory: 512Mi    │                   │
│  └────────┬─────────┘            └──────────────────┘                   │
│           │                                                              │
│  Compute Engine #1 (e2-small)     Compute Engine #2 (e2-standard-2)     │
│  ┌──────────────────┐            ┌──────────────────┐                   │
│  │  MongoDB   :27017 │            │  Airflow    :8080 │                   │
│  │  Grafana   :3000  │            │  (DAG 오케스트레이션) │                   │
│  │  (메타데이터+모니터링)│            │  - 수집+인덱싱 DAG  │                   │
│  └──────────────────┘            │  - 평가 DAG        │                   │
│        ↑                         │  - QA 생성 DAG     │                   │
│   Compass + Grafana (로컬 Mac)    └────────┬─────────┘                   │
│                                           │                              │
│  GCS (실제 데이터 저장소)                    │ DAG 태스크 실행               │
│  ┌──────────────────────┐                 ↓                              │
│  │ prompts/              │   QA 생성 prompt source of truth               │
│  │ policies/raw/         │   수집 → GCS + MongoDB                         │
│  │ policies/processed/   │   인덱싱/QA 생성용 정규화 뷰                    │
│  │ index/faiss.index     │   인덱싱 → FAISS 빌드 → GCS 업로드              │
│  │ index/metadata.pkl    │   평가 → JSON/HTML 결과 저장                    │
│  └──────────────────────┘                                               │
└──────────────────────────────────────────────────────────────────────────┘
```

**운영 서비스 계정 분리**:
- `sa-rag-api@...`: Cloud Run API 전용. `roles/aiplatform.user` + 버킷 `roles/storage.objectViewer`
- `sa-airflow-pipeline@...`: Airflow VM 전용. `roles/aiplatform.user`, `roles/run.admin` + 버킷 `roles/storage.objectAdmin`
- `sa-mongo-vm@...`: Mongo/Grafana VM 전용. `roles/logging.logWriter`, `roles/monitoring.metricWriter`, `roles/cloudtrace.agent`
- 버킷 보안: `versioning_enabled=true`, `public_access_prevention=enforced`, `uniform_bucket_level_access=true`

#### Dockerfile (BE — FastAPI)

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY pyproject.toml .
RUN pip install --no-cache-dir ".[api,ko]"
COPY config/ config/
COPY src/ src/
COPY data/eval/ data/eval/
COPY data/results/ data/results/
EXPOSE 8000
# 기동 시 GCS에서 FAISS 인덱스 다운로드 → 인메모리 로드
CMD ["uvicorn", "src.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

#### Dockerfile.ui (FE — Streamlit)

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY pyproject.toml .
RUN pip install --no-cache-dir ".[ui,viz]"
COPY src/ui/ src/ui/
EXPOSE 8501
CMD ["streamlit", "run", "src/ui/app.py", \
     "--server.port=8501", "--server.address=0.0.0.0"]
```

#### MongoDB VM 세팅

```bash
# Compute Engine VM 생성 (e2-small, 서울)
gcloud compute instances create mongodb-vm \
  --zone=asia-northeast3-a \
  --machine-type=e2-small \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=20GB \
  --tags=mongodb

# 방화벽 규칙 (Compass 연결용)
gcloud compute firewall-rules create allow-mongodb \
  --allow=tcp:27017 \
  --target-tags=mongodb \
  --source-ranges=YOUR_IP/32

# VM 내부에서 MongoDB 설치
sudo apt-get install -y gnupg curl
# MongoDB Community Edition 설치 (공식 문서 참조)
```

#### Cloud Run 배포

```bash
# BE (FastAPI) — 무거운 ML 의존성
gcloud builds submit \
  --tag asia-northeast3-docker.pkg.dev/rag-qna-eval/repo/api:latest

gcloud run deploy rag-youth-policy-api \
  --image asia-northeast3-docker.pkg.dev/rag-qna-eval/repo/api:latest \
  --region asia-northeast3 \
  --memory 2Gi \
  --min-instances 0 \
  --max-instances 1 \
  --service-account sa-rag-api@rag-qna-eval.iam.gserviceaccount.com \
  --set-env-vars "GCS_BUCKET=rag-qna-eval-data,VERTEXAI_PROJECT=rag-qna-eval,VERTEXAI_LOCATION=asia-northeast3" \
  --update-secrets "MONGODB_URI=mongodb-uri:latest" \
  --allow-unauthenticated

# FE (Streamlit) — 가벼운 UI 전용
gcloud builds submit \
  --tag asia-northeast3-docker.pkg.dev/rag-qna-eval/repo/ui:latest \
  -f Dockerfile.ui

gcloud run deploy rag-youth-policy-ui \
  --image asia-northeast3-docker.pkg.dev/rag-qna-eval/repo/ui:latest \
  --region asia-northeast3 \
  --memory 512Mi \
  --min-instances 0 \
  --max-instances 1 \
  --set-env-vars "API_BASE_URL=https://rag-youth-policy-api-xxxxx.run.app" \
  --allow-unauthenticated
```

| 설정 | BE (FastAPI) | FE (Streamlit) |
|------|-------------|----------------|
| Region | asia-northeast3 | asia-northeast3 |
| Memory | 2Gi (Cross-Encoder) | 512Mi (UI만) |
| Min instances | 0 | 0 |
| Max instances | 1 | 1 |

| 설정 | 값 | 이유 |
|------|------|------|
| MongoDB VM | e2-small (~₩25,000/월) | 메타데이터 관리 + Grafana 모니터링 |
| Airflow VM | e2-standard-2 (~₩67,000/월) | DAG 오케스트레이션 (수집/인덱싱/평가) |
| GCS | 정책 원본 + 인덱스 저장 | 실제 데이터 저장소, BE 기동 시 인덱스 로드 |

Cold start 5-15초 → 발표 전 사전 호출.

Secret Manager 운영 원칙:
- Cloud Run API: `MONGODB_URI`는 Secret Manager secret env로 주입
- Airflow VM: `airflow-db-password`, `airflow-admin-password`, `mongodb-uri`,
  `data-portal-api-key`, `openai-api-key`, `huggingface-api-key`를 startup/setup 시 조회
- 런타임 서비스 계정:
  `sa-rag-api`와 `sa-airflow-pipeline`에만 `roles/secretmanager.secretAccessor` 부여

#### CI/CD (GitHub Actions)

모노레포 구조에서 **경로 필터**로 변경된 서비스만 배포:

```yaml
# .github/workflows/deploy-api.yml
name: Deploy BE (FastAPI)
on:
  push:
    branches: [main]
    paths:
      - "src/api/**"
      - "src/retrieval/**"
      - "src/generation/**"
      - "src/evaluation/**"
      - "src/ingestion/**"
      - "config/**"
      - "Dockerfile"
      - "pyproject.toml"

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: google-github-actions/auth@v2
        with:
          credentials_json: ${{ secrets.GCP_SA_KEY }}
      - uses: google-github-actions/setup-gcloud@v2
      - run: |
          gcloud builds submit \
            --tag asia-northeast3-docker.pkg.dev/rag-qna-eval/repo/api:${{ github.sha }}
          gcloud run deploy rag-youth-policy-api \
            --image asia-northeast3-docker.pkg.dev/rag-qna-eval/repo/api:${{ github.sha }} \
            --region asia-northeast3 \
            --memory 2Gi
```

```yaml
# .github/workflows/deploy-ui.yml
name: Deploy FE (Streamlit)
on:
  push:
    branches: [main]
    paths:
      - "src/ui/**"
      - "Dockerfile.ui"

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: google-github-actions/auth@v2
        with:
          credentials_json: ${{ secrets.GCP_SA_KEY }}
      - uses: google-github-actions/setup-gcloud@v2
      - run: |
          gcloud builds submit \
            --tag asia-northeast3-docker.pkg.dev/rag-qna-eval/repo/ui:${{ github.sha }} \
            -f Dockerfile.ui
          gcloud run deploy rag-youth-policy-ui \
            --image asia-northeast3-docker.pkg.dev/rag-qna-eval/repo/ui:${{ github.sha }} \
            --region asia-northeast3 \
            --memory 512Mi
```

```yaml
# .github/workflows/ci.yml
name: CI (Lint + Test)
on:
  pull_request:
    branches: [main]

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
      - run: pip install -e ".[dev,api]"
      - run: ruff check .
      - run: ruff format --check .
      - run: pytest
```

**GitHub Secrets 설정 필요**: `GCP_SA_KEY` (서비스 계정 JSON 키)

| 워크플로 | 트리거 | 동작 |
|----------|--------|------|
| `ci.yml` | PR → main | ruff lint + pytest |
| `deploy-api.yml` | main push (src/api, retrieval, generation 등) | BE 빌드+배포 |
| `deploy-ui.yml` | main push (src/ui) | FE 빌드+배포 |

대안 (시간 부족 시): HF Spaces 또는 로컬 데모.

#### 인프라 모니터링 (최적화 C — Grafana + GCP Cloud Monitoring)

**설계 판단**: Prometheus 자체 호스팅 대신 GCP Cloud Monitoring(관리형) + Grafana 조합.
- SA 관점: 관리형 서비스 우선 → Prometheus 운영 부담 제거
- 비용 최적화: e2-small 유지 (VM 업그레이드 불필요), 추가 비용 $0
- Grafana만 VM에 추가 설치 (~256MB RAM)

**아키텍처**:
```
FastAPI (Cloud Run)
  │  커스텀 메트릭 전송
  ▼
GCP Cloud Monitoring ◄── Cloud Run 기본 메트릭 (요청수, 레이턴시, 에러율)
  │
  ▼
Grafana (:3000, e2-small VM)
  ├── 데이터소스: GCP Cloud Monitoring 플러그인
  ├── 데이터소스: MongoDB 직접 연결
  └── 대시보드 5개 패널
```

**Grafana 대시보드 구성**:

| 패널 | 데이터 소스 | 메트릭 |
|------|-----------|--------|
| Cloud Run 서비스 | GCP Cloud Monitoring | 요청수, 레이턴시 (p50/p95/p99), 에러율, 인스턴스 수, 메모리 |
| MongoDB 상태 | MongoDB 직접 연결 | 커넥션 수, 문서 수, 쿼리 성능 |
| RAG 파이프라인 | GCP Cloud Monitoring 커스텀 | 검색/생성 레이턴시 분해, 모델별 토큰 사용량 |
| LLM 비용 트래커 | MongoDB api_usage_logs | 모델별 누적 비용, 일별 비용 추이 |
| 데이터 적재 현황 | MongoDB ingestion_logs | 소스별 수집 건수/성공률, 인덱스 동기화 상태 |

**① 애플리케이션 메트릭 (FastAPI 미들웨어)**:

FastAPI에 미들웨어 추가 → GCP Cloud Monitoring API로 커스텀 메트릭 전송:

| 메트릭 | 설명 |
|--------|------|
| `rag/retrieval_latency_ms` | 검색 전략별 소요 시간 |
| `rag/generation_latency_ms` | 모델별 생성 소요 시간 |
| `rag/total_latency_ms` | 전체 응답 시간 |
| `rag/tokens_used` | 모델별 입력/출력 토큰 |
| `rag/estimated_cost_usd` | 요청별 추정 비용 |
| `rag/error_count` | 모델별/엔드포인트별 에러 수 |

**② 데이터 적재 모니터링**:

`ingestion_logs` 확장 스키마:
```python
{
    "source": "youthgo",
    "started_at": "2026-05-15T02:00:00Z",
    "finished_at": "2026-05-15T02:03:22Z",
    "total": 45,
    "new": 3,
    "updated": 2,
    "failed": 0,
    "status": "success",
    "gcs_paths": ["gs://bucket/policies/raw/youthgo/..."],
    "index_doc_count_before": 1200,
    "index_doc_count_after": 1205,
    "index_rebuild_seconds": 45,
    "avg_chunks_per_policy": 4.2
}
```

적재 모니터링 메트릭:

| 메트릭 | 설명 | 알림 조건 |
|--------|------|----------|
| 수집 건수 | 소스별 신규/업데이트/실패 건수 | — |
| 수집 성공률 | 소스별 성공/실패 비율 | < 50% → 크롤링 차단 의심 |
| 데이터 신선도 | 소스별 마지막 수집 시간 | > 48시간 → Scheduler 장애 |
| 인덱스 동기화 | FAISS 문서 수 vs MongoDB 정책 수 | 차이 > 10% → 동기화 깨짐 |
| GCS 용량 | 원본/인덱스 파일 크기 추이 | — |

**③ LLM 비용 트래커**:

`api_usage_logs` 스키마:
```python
{
    "timestamp": "2026-05-15T10:30:00Z",
    "request_id": "abc-123",
    "model": "openai/gpt-4o-mini",
    "tokens_in": 1200,
    "tokens_out": 350,
    "cost_usd": 0.0012,
    "latency_ms": 2300,
    "strategy": "hybrid_rerank",
    "status": "success"
}
```

**④ 헬스체크 엔드포인트**:

```python
# GET /health
{
    "status": "healthy",
    "faiss_loaded": true,
    "faiss_doc_count": 1234,
    "faiss_last_updated": "2026-05-15",
    "mongodb_connected": true,
    "gcs_accessible": true,
    "uptime_seconds": 3600,
    "data_pipeline": {
        "last_ingestion": "2026-05-15T02:03:22Z",
        "total_policies": 234,
        "index_sync_status": "ok",
        "sources": {
            "youthgo": {"last_run": "...", "status": "success", "count": 120},
            "data_portal": {"last_run": "...", "status": "success", "count": 85}
        }
    }
}
```

Cloud Monitoring Uptime Check → `/health` 주기적 호출 → 실패 시 이메일 알림.

**⑤ 구조화 로깅 (Cloud Logging)**:

모든 RAG 요청을 JSON 구조화 로그로 기록 → Cloud Logging에서 쿼리/필터 가능:
```python
{
    "severity": "INFO",
    "request_id": "abc-123",
    "query": "청년 월세 지원 자격은?",
    "model": "openai/gpt-4o-mini",
    "strategy": "hybrid_rerank",
    "retrieval_ms": 120,
    "generation_ms": 2300,
    "total_ms": 2450,
    "tokens_in": 1200,
    "tokens_out": 350,
    "faithfulness": 0.92,
    "status": "success"
}
```

---

### 9.1 실험 매트릭스

```
실험 1: 모델 비교 (검색 고정: Hybrid+Rerank)
  GPT-4o-mini / GPT-4o / Claude Sonnet 4.5 / Gemini 2.5 Flash / Gemini 2.5 Pro / Llama 3.3 70B
  × 100 QA = 600 평가

실험 2: 검색 전략 비교 (모델 고정: GPT-4o-mini)
  Vector Only / BM25 Only / Hybrid / Hybrid+Rerank
  × 100 QA = 400 평가

실험 3: RAG vs No-RAG (모델 고정: GPT-4o-mini)
  컨텍스트 O vs X
  × 100 QA = 200 평가
```

총 ~1,100회 LLM 호출. 예상 비용 ~$5-12 (Gemini는 GCP 크레딧 사용).

### 9.2 기대 결과

**모델 비교**:

| Model | Faith. | Relev. | Halluc. | Latency |
|-------|--------|--------|---------|---------|
| GPT-4o | 0.92 | 0.94 | 0.05 | 3.2s |
| Claude Sonnet 4.5 | 0.90 | 0.91 | 0.07 | 4.1s |
| Gemini 2.5 Pro | 0.89 | 0.91 | 0.06 | 2.0s |
| Gemini 2.5 Flash | 0.88 | 0.90 | 0.08 | 1.5s |
| GPT-4o-mini | 0.87 | 0.89 | 0.10 | 1.8s |
| Llama 3.3 70B | 0.80 | 0.84 | 0.15 | 3.0s |

**검색 전략 비교**:

| Strategy | C.Prec | C.Rec | Faith. |
|----------|--------|-------|--------|
| Vector Only | 0.72 | 0.75 | 0.85 |
| BM25 Only | 0.68 | 0.70 | 0.83 |
| Hybrid | 0.82 | 0.84 | 0.87 |
| **Hybrid+Rerank** | **0.89** | **0.88** | **0.87** |

**RAG vs No-RAG**:

| 조건 | Faithfulness | Hallucination |
|------|-------------|---------------|
| With RAG | 0.87 | 0.10 |
| Without RAG | 0.45 | **0.52** |

### 9.3 최종 발표

- 실험 결과 슬라이드
- 라이브 데모: 정책 탐색 → 챗봇 질문 → 답변 + 출처 → 신뢰성 점수 → 맞춤 추천
- 평가 대시보드 화면 (모델/전략별 비교)
- Q&A 준비

### Phase 6 완료 기준

- [x] FastAPI 백엔드 API 구현 완료 — 6개 엔드포인트 (Health/Search/Generate/Policies/Models/Evaluate) + 26개 테스트
- [x] Cloud Run에서 4페이지 앱 접근 가능 — BE: `rag-youth-policy-api-731835371349.asia-northeast3.run.app` / FE: `rag-youth-policy-ui-731835371349.asia-northeast3.run.app`
- [x] Grafana 대시보드 5개 패널 구성 (Cloud Run, MongoDB, RAG 파이프라인, LLM 비용, 데이터 적재) — `monitoring/grafana/` 프로비저닝 + 대시보드 JSON
- [x] `/health` 헬스체크 + Uptime Check 알림 설정 — `scripts/setup_uptime_check.sh` (gcloud CLI)
- [x] 구조화 로깅 → Cloud Logging에서 RAG 요청 쿼리 가능 — `src/api/logging_config.py` JSON 포매터, `log_structured()` 헬퍼
- [ ] 실험 3종 (모델/전략/RAG vs No-RAG) 완료
- [ ] 최종 리포트 + 시각화 생성
- [ ] 크레딧 만료(6/19) 전 모든 실험 완료

---

## 10. 기술 스택

| 구분 | 기술 | 이유 |
|------|------|------|
| 언어 | Python 3.11+ | RAG 생태계 |
| LLM 통합 | LiteLLM 멀티 프로바이더 (OpenAI 직접 / Vertex AI / HuggingFace) | 1줄로 모델 전환, 프로바이더별 분산 |
| 임베딩 | Vertex AI text-embedding-004 (768차원) | GCP 크레딧, 한국어 성능 우수 |
| 벡터 검색 | FAISS (faiss-cpu) | 경량, Docker 친화적, pickle 직렬화 |
| 데이터 저장 | GCS (Cloud Storage) | 정책 원본 JSON/PDF + FAISS 인덱스 (실제 데이터 저장소) |
| 메타데이터 | MongoDB (GCP VM) | 정책 메타데이터 관리 (gcs_path 참조) + Compass GUI |
| BM25 | rank_bm25 | 키워드 보완 |
| 리랭커 | sentence-transformers | Cross-Encoder |
| 데이터 수집 | httpx + BeautifulSoup | 정부 사이트 크롤링 |
| PDF | PyMuPDF | 정부 보고서 추출 |
| 한국어 | kss + mecab-python3 | 문장 분리 (mecab C++ 백엔드) |
| 평가 (정량) | RAGAS v0.4 | 학술 표준 |
| 평가 (정성) | 커스텀 LLM Judge | G-Eval 방식 |
| 평가 (안전) | DeepEval | Hallucination |
| 시각화 | matplotlib + plotly | 차트 |
| 린터 | ruff | 빠름 |
| 테스트 | pytest | 표준 |
| UI | Streamlit | 빠른 데모 |
| 워크플로 | Apache Airflow (self-hosted VM) | DAG 오케스트레이션 (수집→인덱싱→평가) |
| 배포 | GCP Cloud Run | Scale-to-zero |
| 레지스트리 | GCP Artifact Registry | Cloud Build 연동 |
| 모니터링 | Grafana + GCP Cloud Monitoring | 관리형 메트릭 + 커스텀 대시보드 |
| 로깅 | GCP Cloud Logging | 구조화 JSON 로그 |
| CI/CD | GitHub Actions | 경로 필터 기반 자동 배포 |

---

## 11. 비용

**GCP 크레딧**: ₩786,544 (2026-06-19 만료, 일회성)

| 항목 | 월 비용 (원) | 55일간 (원) | 결제 방식 |
|------|-------------|-------------|----------|
| GCP VM #1 — MongoDB + Grafana (e2-small) | ~₩25,000 | ~₩46,000 | **GCP Annual 크레딧** |
| GCP VM #2 — Airflow (e2-standard-2) | ~₩67,000 | ~₩123,000 | **GCP Annual 크레딧** |
| Cloud Run (BE + FE, scale-to-zero) | ~₩0 | ~₩0 | **GCP Annual 크레딧** |
| GCS (정책 원본 + FAISS 인덱스, 수십 MB) | ~₩0 | ~₩0 | **GCP Annual 크레딧** |
| Artifact Registry + Cloud Build | ~₩5,000 | ~₩10,000 | **GCP Annual 크레딧** |
| Cloud Monitoring + Logging | ~₩5,000 | ~₩10,000 | **GCP Annual 크레딧** |
| **인프라 소계** | **~₩102,000** | **~₩189,000** | |
| 임베딩 (Vertex AI text-embedding-004) | ~$0.50 | - | Vertex AI (GCP 크레딧) |
| GPT-4o-mini (Vertex AI 경유) | ~$1-2 | ~$3-5 | Vertex AI (GCP 크레딧) |
| GPT-4o (Vertex AI 경유) | - | ~$3-5 | Vertex AI (GCP 크레딧) |
| Claude Sonnet 4.5 (Vertex AI 경유) | - | ~$3-5 | Vertex AI (GCP 크레딧) |
| Gemini 2.5 Flash/Pro (Vertex AI 네이티브) | - | ~$0-1 | Vertex AI (GCP 크레딧) |
| Llama 3.3 70B (HuggingFace Inference API) | - | ~$0 (무료 티어) | HuggingFace |
| **LLM 소계** | | **~$10-15 (~₩15,000)** | |
| **총합계** | | **~₩204,000** | |

**크레딧 잔여 계산** (2026-04-25 → 2026-06-19, 55일):
- 총 크레딧: ₩786,544
- 인프라 예상: ~₩189,000
- LLM 호출 예상: ~₩15,000
- **잔여: ~₩582,000** (실험 여유분 충분)
- **6/19 만료 전에 실험 완료 필수.**

---

## 12. 리스크

| Risk | 가능성 | 영향 | 완화 |
|------|--------|------|------|
| RAGAS v0.4 호환성 | High | High | 조기 테스트 + 버전 pinning. v0.3 예시에 속지 않기 |
| QA 데이터셋 품질 | High | High | 50쌍 직접 작성. 1주 뒤 재검토 |
| **정부 사이트 크롤링 차단** | **Medium** | **High** | **공공데이터포털 API를 대안 경로로 확보. 크롤링 결과 JSON 캐시** |
| **정책 데이터 변경/만료** | Medium | Medium | last_updated 메타데이터 관리 + 면책 문구 |
| **데이터 정규화 불일치** | Medium | Medium | 표준 Policy 스키마 + 소스별 파서 |
| **UI 기능 범위 과다 (1인)** | **High** | **Medium** | **챗봇+정책탐색 2개 핵심 우선. 비교/추천은 MVP** |
| 한국어 PDF 파싱 | Medium | Medium | 텍스트 PDF 우선. 스캔이면 Vision OCR |
| 한국어 청킹/BM25 | Medium | Medium | kss + 공백 → 미달 시 konlpy |
| API 비용 | Low | Medium | GPT-4o-mini 기본 + Gemini(GCP 크레딧) + Ollama |
| **GCP 크레딧 만료** | **Low** | **High** | **6/19 전 실험/배포 완료. 5월 말까지 Phase 6 진입 목표** |
| Cold Start | Low | Low | 발표 전 사전 호출 |
| **시간 부족** | **High** | **High** | **Phase 4(평가)가 핵심. 시간 부족 시 GCP 대신 HF Spaces/로컬 데모** |

---

## GCP 서비스 구성

이 프로젝트에서 실제로 사용하는 GCP 서비스 10개와 각 역할이다.

| # | GCP 서비스 | 용도 | 리전 | 비용 특성 |
|---|-----------|------|------|----------|
| 1 | **Cloud Run** (2개 서비스) | BE: FastAPI + FAISS 인메모리 검색 (2Gi) / FE: Streamlit UI (512Mi) | asia-northeast3 | scale-to-zero, 요청 시만 과금 |
| 2 | **Compute Engine** (2개 VM) | VM #1: MongoDB + Grafana (e2-small) / VM #2: Airflow 2.9.3 (e2-standard-2) | asia-northeast3-a | VM #1 ~₩20K/월, VM #2 ~₩67K/월 |
| 3 | **Cloud Storage (GCS)** | 정책 원본 JSON/PDF + FAISS 인덱스 + QA 데이터셋 + 평가 결과 (source of truth) | asia-northeast3 | STANDARD 스토리지, 저용량 |
| 4 | **Artifact Registry** | Docker 이미지 저장소 (BE/FE/Jobs 이미지) | asia-northeast3 | 이미지 크기 기반 과금 |
| 5 | **Vertex AI** (Model Garden) | Gemini 2.5 Flash/Pro + Claude Sonnet 4.5 LLM 호출 (LiteLLM `vertex_ai/` prefix) | us-central1, us-east5 등 | 토큰 기반 과금, GCP 크레딧 활용 |
| 6 | **Cloud Monitoring** | Cloud Run 메트릭 (CPU, 메모리, 요청 수) + FastAPI 커스텀 메트릭 | 글로벌 | 무료 티어 내 |
| 7 | **Cloud Logging** | RAG 요청별 구조화 JSON 로그, Cloud Run stdout/stderr 수집 | 글로벌 | 50GB/월 무료 |
| 8 | **Secret Manager** | Airflow VM 프로비저닝 시 DB/Admin 비밀번호, MongoDB URI, API 키 관리 | 글로벌 | 시크릿 수 기반, 극소량 |
| 9 | **IAP (Identity-Aware Proxy)** | GitHub Actions → Airflow VM SSH 접속 시 인증 (deploy-airflow.yml) | 글로벌 | 무료 |
| 10 | **VPC 네트워킹** | 방화벽 규칙 (MongoDB 27017, Airflow 8080, Grafana 3000 포트 개방) | asia-northeast3 | 무료 |

**사용하지 않는 서비스**: Cloud Build (GitHub Actions가 docker build+push 담당), Cloud Scheduler/Eventarc (Airflow로 대체), Cloud Composer (비용 과다로 self-hosted Airflow 선택), Cloud Run Jobs (정의는 존재하나 Airflow가 직접 실행).

---

## 13. 즉시 해야 할 것 (우선순위)

1. ~~도메인 확정~~ ✅ — 학생/청년 정부 정책 QnA
2. **데이터 소스 접근성 검증** — 온통청년 크롤링 가능 여부, 공공데이터포털 API 테스트
3. **초기 데이터 50건 수집** — 수집 파이프라인 검증
4. **RAGAS v0.4 테스트** — Jupyter에서 v0.4 코드 동작 검증
5. **QA 데이터셋 시작** — 개발과 병행. 미루면 Phase 4에서 병목
6. **레포 스켈레톤 세팅** — pyproject.toml + 디렉토리 구조 (rag-youth-policy)
7. **GCP 프로젝트 + Gemini API 키** — 크레딧 활성화
8. **중간 발표 슬라이드** — README.md 활용

---

## 14. 참고 문서

| 문서 | 핵심 |
|------|------|
| [README.md](README.md) | 아키텍처, 기술 스택 |
| [docs/02-development-plan.md](docs/02-development-plan.md) | Phase별 태스크 |
| [docs/03-requirements.md](docs/03-requirements.md) | pyproject.toml, API, 비용 |
| [docs/04-research.md](docs/04-research.md) | 기술 비교 분석 |
| [docs/04-research-rag-evaluation-deep-dive.md](docs/04-research-rag-evaluation-deep-dive.md) | **RAGAS v0.4** (가장 중요) |
| [docs/05-cloud-deployment.md](docs/05-cloud-deployment.md) | GCP Cloud Run |
| [docs/06-evaluation-methods.md](docs/06-evaluation-methods.md) | 3단계 평가 |
