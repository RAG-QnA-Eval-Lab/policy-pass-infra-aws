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
- Cloud Scheduler 기반 주기 실행
- Data Crawler 실행
- 원본 데이터 저장
- 정제 데이터 저장
- 청킹(Chunking)
- 임베딩(Embedding)
- FAISS 인덱스 생성(Build)
- GCS에 Policies / Chunks / Index 저장
- Eventarc 기반 후속 파이프라인 트리거
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
- 실행 주체: Cloud Run Job

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
Cloud Run Job → FAISS Build            ECS Container 기동
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

