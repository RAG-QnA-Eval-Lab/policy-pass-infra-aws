# AWS 콘솔 인프라 구축 가이드

> **관련 문서**: [AWS 인프라 구축 계획서](./aws-infrastructure-plan.md)  
> **최종 수정일**: 2026-05-16  
> **담당자**: Daehyun Kim

이 문서는 AWS 콘솔(웹 UI)에서 직접 인프라를 구축하는 **스텝바이스텝 가이드**이다.  
각 Phase는 [계획서](./aws-infrastructure-plan.md)의 구현 순서를 따른다.

> **사전 준비**  
>
> - AWS 계정 로그인 (IAM 관리자 권한 또는 루트 계정)  
> - 리전: **서울 (ap-northeast-2)** — 콘솔 우측 상단에서 리전 확인  
> - AWS Account ID 확인: 콘솔 우측 상단 계정 드롭다운에서 12자리 숫자 복사

---

## Phase A: Foundation (IAM + ECR + S3)

### A-1. IAM 역할 생성

#### 역할 1: EC2InstanceRole

1. **IAM** 콘솔 접속: `console.aws.amazon.com/iam`
2. 좌측 메뉴 → **역할(Roles)** → **역할 생성(Create role)**
3. 신뢰할 수 있는 엔터티 유형: **AWS 서비스** 선택
4. 사용 사례: **EC2** 선택 → **다음(Next)**
5. 권한 정책 검색: `AmazonEC2ContainerRegistryReadOnly` 체크 → **다음(Next)**
6. 역할 이름: `EC2InstanceRole` → **역할 생성**
7. 생성된 역할 클릭 → **권한(Permissions)** 탭 → **인라인 정책 생성(Create inline policy)**
8. **JSON** 탭 선택 후 아래 입력 (`{ACCOUNT_ID}`를 본인 계정 ID로 교체):
  ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "S3ReadIndex",
         "Effect": "Allow",
         "Action": [
           "s3:GetObject",
           "s3:ListBucket"
         ],
         "Resource": [
           "arn:aws:s3:::rag-qa-index-{ACCOUNT_ID}",
           "arn:aws:s3:::rag-qa-index-{ACCOUNT_ID}/*"
         ]
       },
       {
         "Sid": "SSMReadParams",
         "Effect": "Allow",
         "Action": [
           "ssm:GetParameter",
           "ssm:GetParametersByPath"
         ],
         "Resource": "arn:aws:ssm:ap-northeast-2:{ACCOUNT_ID}:parameter/rag-qa/*"
       }
     ]
   }
  ```
9. 정책 이름: `EC2InstancePolicy` → **정책 생성**

#### 역할 2: DataSyncS3Role

1. **역할(Roles)** → **역할 생성(Create role)**
2. 신뢰할 수 있는 엔터티 유형: **사용자 지정 신뢰 정책** 선택
3. 아래 JSON 입력:
  ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Service": "datasync.amazonaws.com"
         },
         "Action": "sts:AssumeRole"
       }
     ]
   }
  ```
4. **다음(Next)** → 권한 정책 건너뛰기 → 역할 이름: `DataSyncS3Role` → **역할 생성**
5. 생성된 역할 클릭 → **인라인 정책 생성** → JSON:
  ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "S3DataSync",
         "Effect": "Allow",
         "Action": [
           "s3:GetObject",
           "s3:PutObject",
           "s3:DeleteObject",
           "s3:ListBucket",
           "s3:GetBucketLocation"
         ],
         "Resource": [
           "arn:aws:s3:::rag-qa-index-{ACCOUNT_ID}",
           "arn:aws:s3:::rag-qa-index-{ACCOUNT_ID}/*"
         ]
       }
     ]
   }
  ```
6. 정책 이름: `DataSyncS3Policy` → **정책 생성**

#### 검증

- **역할(Roles)** 목록에서 2개 역할 확인:
  - `EC2InstanceRole`
  - `DataSyncS3Role`

---

### A-2. ECR 레포지토리 생성

1. **ECR** 콘솔 접속: `console.aws.amazon.com/ecr`
2. 좌측 메뉴 → **Private registry** → **Repositories** → **리포지토리 생성(Create repository)**

#### 레포지토리: rag-api

1. 가시성: **Private**
2. 리포지토리 이름: `rag-api`
3. 나머지 기본값 유지 → **리포지토리 생성**
4. 생성된 `rag-api` 클릭 → 좌측 **Lifecycle Policy** → **규칙 생성(Create rule)**
5. 규칙 설정:
  - 규칙 우선순위: `1`
  - 이미지 태그 상태: **태그가 지정되지 않음(Untagged)**
  - 매치 범위: **이미지 개수(Image count)** 선택 (목록 마지막 항목)
  - 이미지 개수: `5`
  - 작업: **만료(Expire)**
6. **저장**

> **참고**: 프론트엔드는 S3 + CloudFront로 서빙하므로 `rag-ui` ECR 레포는 불필요하다.

#### 검증

- Repositories 목록에 `rag-api` 표시

---

### A-3. S3 버킷 생성

1. **S3** 콘솔 접속: `console.aws.amazon.com/s3`
2. **버킷 만들기(Create bucket)** 클릭
3. 버킷 이름: `rag-qa-index-{ACCOUNT_ID}` (예: `rag-qa-index-123456789012`)
4. 리전: **아시아 태평양(서울) ap-northeast-2**
5. 객체 소유권: **ACL 비활성화됨** (기본값)
6. 퍼블릭 액세스 차단: **모든 퍼블릭 액세스 차단** (기본값 유지)
7. 버킷 버전 관리: **활성화(Enable)**
8. 나머지 기본값 → **버킷 만들기**

#### 수명주기 규칙 추가

1. 생성된 버킷 클릭 → **관리(Management)** 탭 → **수명주기 규칙 생성**
2. 규칙 이름: `delete-old-versions`
3. 범위: **버킷의 모든 객체에 적용**
4. 수명주기 규칙 작업: **비현재 버전의 객체를 영구적으로 삭제** 체크
5. 비현재 버전 유지 일 수: `30`
6. **규칙 생성**

#### 폴더 구조 생성

1. 버킷 내에서 **폴더 만들기** → 이름: `index` → **폴더 만들기**

#### 검증

- 버킷 목록에서 `rag-qa-index-{ACCOUNT_ID}` 확인
- 속성 탭에서 버전 관리 "활성화됨" 확인

---

## Phase B: Data Sync + Secrets

### B-1. DataSync 태스크 생성

> **사전 준비**: GCS에서 HMAC 키를 미리 생성해야 한다.  
> GCP 콘솔 → Cloud Storage → 설정 → 상호 운용성(Interoperability) → 서비스 계정 HMAC 키 생성

1. **DataSync** 콘솔 접속: `console.aws.amazon.com/datasync`
2. **태스크 생성(Create task)** 클릭

#### 소스 위치 설정

1. **새 위치 생성(Create a new location)** 선택
2. 위치 유형: **Object storage**
3. 서버:
  - 에이전트: **없음(No agent)** — 클라우드 간 직접 전송
  - 서버 호스트네임: `storage.googleapis.com`
  - 버킷 이름: `{GCS_BUCKET_NAME}` (GCP 프로젝트의 FAISS 인덱스 버킷명)
  - 폴더: `/index/`
4. 인증:
  - 접근 키: GCS HMAC Access Key
  - 비밀 키: GCS HMAC Secret Key
5. **다음(Next)**

#### 대상 위치 설정

1. **새 위치 생성** 선택
2. 위치 유형: **Amazon S3**
3. S3 버킷: 드롭다운에서 `rag-qa-index-{ACCOUNT_ID}` 선택
4. 폴더: `/index/`
5. IAM 역할: 드롭다운에서 `DataSyncS3Role` 선택
6. **다음(Next)**

#### 태스크 설정

1. 태스크 이름: `gcs-to-s3-faiss-index`
2. 전송 설정:
  - 전송 모드: **변경된 데이터만 전송(Transfer only data that has changed)**
    - 검증: **전송된 데이터만 확인(Verify only the data transferred)**
    - 대상에서 삭제된 파일: **유지(Keep deleted files)**
    - 덮어쓰기 모드: **항상(Always)**
3. 스케줄: **실행하지 않음(Not scheduled)** — Airflow에서 수동으로 트리거
4. 로깅: **CloudWatch Log 그룹 자동 생성** (선택)
5. **다음(Next)** → **태스크 생성**

#### 검증

- 태스크 목록에서 `gcs-to-s3-faiss-index` 확인
- 상태: `Available`
- **시작(Start)** 클릭하여 테스트 실행 → S3 버킷의 `index/` 폴더에 파일 도착 확인

---

### B-2. SSM Parameter Store 설정

1. **Systems Manager** 콘솔 접속: `console.aws.amazon.com/systems-manager`
2. 좌측 메뉴 → **파라미터 스토어(Parameter Store)** → **파라미터 생성(Create parameter)**

#### 파라미터 1: OpenAI API Key

1. 이름: `/rag-qa/openai-api-key`
2. 설명: `OpenAI API Key for RAG QA`
3. 계층: **표준(Standard)**
4. 유형: **SecureString**
5. KMS 키 소스: **현재 계정** (기본 aws/ssm 키 사용)
6. 값: OpenAI API 키 입력
7. **파라미터 생성**

#### 파라미터 2: MongoDB URI

1. 이름: `/rag-qa/mongodb-uri`
2. 유형: **SecureString**
3. 값: MongoDB 연결 문자열 입력
4. **파라미터 생성**

#### 파라미터 3: S3 Bucket

1. 이름: `/rag-qa/s3-bucket`
2. 유형: **String**
3. 값: `rag-qa-index-{ACCOUNT_ID}`
4. **파라미터 생성**

#### 파라미터 4: Index S3 Prefix

1. 이름: `/rag-qa/index-s3-prefix`
2. 유형: **String**
3. 값: `index/`
4. **파라미터 생성**

#### 검증

- 파라미터 목록에서 `/rag-qa/` 경로 아래 4개 파라미터 확인
- SecureString 파라미터는 값이 `**`**로 마스킹되어 표시

---

## Phase C: 애플리케이션 준비

> Phase C는 콘솔 작업이 아니라 **코드 작업**이다.  
> Dockerfile, requirements.txt 등을 작성하고 GitHub에 push한 뒤,  
> ECR에 초기 이미지를 push해야 Phase D(EC2)를 진행할 수 있다.

### ECR에 초기 이미지 Push (로컬 터미널)

Phase D 전에 ECR에 최소 1개의 이미지가 있어야 EC2에서 컨테이너를 실행할 수 있다.

```bash
# 1. ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin {ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com

# 2. API 이미지 빌드 & 푸시
docker build -f services/api/Dockerfile -t rag-api services/api
docker tag rag-api:latest {ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/rag-api:initial
docker push {ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/rag-api:initial
```

#### 검증

- ECR 콘솔에서 `rag-api` 레포지토리에 `initial` 태그 이미지 존재 확인

---

## Phase D: Compute + Frontend

> **변경사항**: UI는 EC2 컨테이너 대신 **S3 + CloudFront** 정적 호스팅으로 서빙한다.  
> EC2 인스턴스는 API(t3.medium)와 Monitor(t3.small) 2대만 생성한다.

### D-0. 키 페어 생성

1. **EC2** 콘솔 접속: `console.aws.amazon.com/ec2`
2. 좌측 메뉴 → **네트워크 및 보안** → **키 페어(Key Pairs)** → **키 페어 생성**
3. 이름: `policy-pass-key`
4. 키 페어 유형: **RSA**
5. 프라이빗 키 파일 형식: **.pem**
6. **키 페어 생성** → `.pem` 파일 자동 다운로드 (안전한 곳에 보관)

```bash
# 다운로드된 키 파일 권한 설정 (로컬 터미널)
chmod 400 ~/Downloads/policy-pass-key.pem
```

### D-1. 보안 그룹 생성

1. EC2 콘솔 → 좌측 메뉴 → **네트워크 및 보안** → **보안 그룹(Security Groups)** → **보안 그룹 생성**

#### 보안 그룹 1: API 서버용

1. 보안 그룹 이름: `policy-pass-api-sg`
2. 설명: `Policy Pass API server`
3. VPC: 기본 VPC
4. 인바운드 규칙 추가:


| 유형         | 포트 범위 | 소스        | 설명     |
| ---------- | ----- | --------- | ------ |
| SSH        | 22    | 내 IP      | SSH 접속 |
| 사용자 지정 TCP | 8080  | 0.0.0.0/0 | API 포트 |


1. 아웃바운드 규칙: 기본값 유지 (모든 트래픽 허용)
2. **보안 그룹 생성**

#### 보안 그룹 2: 모니터링 서버용

1. 보안 그룹 이름: `policy-pass-monitor-sg`
2. 설명: `Policy Pass monitoring server`
3. 인바운드 규칙 추가:


| 유형         | 포트 범위 | 소스   | 설명                   |
| ---------- | ----- | ---- | -------------------- |
| SSH        | 22    | 내 IP | SSH 접속               |
| 사용자 지정 TCP | 3000  | 내 IP | Grafana 대시보드 (관리자만)  |
| 사용자 지정 TCP | 9090  | 내 IP | Prometheus UI (관리자만) |


1. **보안 그룹 생성**

> **참고**: UI 전용 보안 그룹(`policy-pass-ui-sg`)은 더 이상 필요하지 않다. 프론트엔드는 S3 + CloudFront로 서빙된다.

### D-2. API 인스턴스 생성

1. EC2 콘솔 → **인스턴스 시작(Launch instances)**
2. 설정:


| 항목            | 값                                  |
| ------------- | ---------------------------------- |
| 이름            | `policy-pass-api`                  |
| AMI           | **Amazon Linux 2023**              |
| 인스턴스 유형       | **t3.medium** (2 vCPU, 4 GB)       |
| 키 페어          | `policy-pass-key`                  |
| 보안 그룹         | `policy-pass-api-sg` (기존 보안 그룹 선택) |
| IAM 인스턴스 프로파일 | `EC2InstanceRole`                  |
| 스토리지          | 20 GiB gp3                         |


1. **고급 세부 정보** 펼치기 → **IAM 인스턴스 프로파일**: `EC2InstanceRole` 선택
2. **사용자 데이터(User data)** 에 아래 스크립트 입력:

```bash
#!/bin/bash
yum update -y
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# ECR 로그인 & 컨테이너 실행을 위한 헬퍼 스크립트
cat > /home/ec2-user/deploy.sh << 'DEPLOY'
#!/bin/bash
REGION=ap-northeast-2
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
IMAGE=$ECR_REGISTRY/rag-api:latest

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
docker pull $IMAGE
docker stop rag-api 2>/dev/null
docker rm rag-api 2>/dev/null
docker run -d --name rag-api -p 8080:8080 \
  -e DOWNLOAD_INDEX_FROM_S3=true \
  -e S3_BUCKET=rag-qa-index-$ACCOUNT_ID \
  -e INDEX_S3_PREFIX=index/ \
  -e ENVIRONMENT=production \
  --restart unless-stopped \
  $IMAGE
DEPLOY
chmod +x /home/ec2-user/deploy.sh
chown ec2-user:ec2-user /home/ec2-user/deploy.sh
```

1. **인스턴스 시작**

> 인스턴스가 Running 상태가 되면 퍼블릭 IP를 확인한다.

#### 첫 배포

```bash
# SSH 접속
ssh -i ~/Downloads/policy-pass-key.pem ec2-user@{API_PUBLIC_IP}

# 배포 스크립트 실행
./deploy.sh

# 헬스체크
curl http://localhost:8080/health
# {"status":"ok"}
```

#### 검증

- 로컬 브라우저에서 `http://{API_PUBLIC_IP}:8080/health` → `{"status":"ok"}`

---

### D-3. S3 + CloudFront 프론트엔드 설정

React + Vite + TypeScript SPA는 빌드 결과물(`dist/`)이 정적 파일이므로 S3 + CloudFront로 서빙한다.  
EC2 Docker 컨테이너 대비 월 ~$14.5 절감, 서버 관리 불필요, CDN 엣지 캐싱으로 성능 향상.

#### S3 버킷 생성

1. **S3** 콘솔 접속 → **버킷 만들기**
2. 버킷 이름: `policy-pass-ui-{ACCOUNT_ID}`
3. 리전: **아시아 태평양(서울) ap-northeast-2**
4. 퍼블릭 액세스 차단: **모든 퍼블릭 액세스 차단** (기본값 유지)
5. 버킷 버전 관리: **비활성화** (빌드 결과물은 덮어쓰기)
6. 나머지 기본값 → **버킷 만들기**

> **주의**: 정적 웹 호스팅을 활성화하지 않는다. CloudFront OAC를 통해 직접 서빙한다.

#### CloudFront Origin Access Control (OAC) 생성

1. **CloudFront** 콘솔 접속: `console.aws.amazon.com/cloudfront`
2. 좌측 메뉴 → **원본 액세스(Origin access)** → **컨트롤 설정(Control settings)** 탭 → **컨트롤 설정 생성**
3. 이름: `policy-pass-ui-oac`
4. 설명: `OAC for Policy Pass UI S3 bucket`
5. 서명 프로토콜: **SigV4**
6. 서명 동작: **항상 서명(Always sign)**
7. 원본 유형: **S3**
8. **생성**

#### CloudFront Distribution 생성

1. CloudFront 콘솔 → **배포(Distributions)** → **배포 생성(Create distribution)**
2. 원본(Origin) 설정:


| 항목        | 값                                                             |
| --------- | ------------------------------------------------------------- |
| 원본 도메인    | `policy-pass-ui-{ACCOUNT_ID}.s3.ap-northeast-2.amazonaws.com` |
| 원본 ID     | `policy-pass-ui-origin`                                       |
| 원본 액세스    | **원본 액세스 제어 설정(OAC)** 선택                                      |
| 원본 액세스 제어 | `policy-pass-ui-oac` 선택                                       |


1. 기본 캐시 동작(Default cache behavior):


| 항목          | 값                                                           |
| ----------- | ----------------------------------------------------------- |
| 뷰어 프로토콜 정책  | **Redirect HTTP to HTTPS**                                  |
| 허용된 HTTP 방법 | **GET, HEAD**                                               |
| 캐시 정책       | **CachingOptimized** (658327ea-f89d-4fab-a63d-7e88639e58f6) |
| 압축          | **Gzip, Brotli 활성화**                                        |


1. 설정(Settings):


| 항목       | 값                                   |
| -------- | ----------------------------------- |
| 기본 루트 객체 | `index.html`                        |
| 가격 등급    | **Price Class 200** (아시아 + 미주 + 유럽) |
| SSL 인증서  | **기본 CloudFront 인증서**               |
| 최소 TLS   | **TLSv1.2_2021**                    |


1. **배포 생성**

> CloudFront가 S3 버킷 정책 업데이트를 안내하는 배너가 표시된다. **정책 복사(Copy policy)** 를 클릭한다.

#### SPA 라우팅을 위한 커스텀 에러 응답 설정

React Router 클라이언트 사이드 라우팅을 지원하려면 403/404 에러를 `index.html`로 리다이렉트해야 한다.

1. 생성된 배포 클릭 → **오류 페이지(Error pages)** 탭 → **사용자 지정 오류 응답 생성**
2. 에러 응답 1:


| 항목           | 값                  |
| ------------ | ------------------ |
| HTTP 오류 코드   | **403: Forbidden** |
| 오류 응답 사용자 정의 | **예**              |
| 응답 페이지 경로    | `/index.html`      |
| HTTP 응답 코드   | **200: OK**        |
| 오류 캐싱 최소 TTL | `0`                |


1. 에러 응답 2: HTTP 오류 코드 **404: Not Found** 로 동일하게 설정

#### S3 버킷 정책 설정

1. **S3** 콘솔 → `policy-pass-ui-{ACCOUNT_ID}` 버킷 → **권한(Permissions)** 탭
2. **버킷 정책(Bucket policy)** → **편집** → CloudFront에서 복사한 정책 붙여넣기:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowCloudFrontOAC",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudfront.amazonaws.com"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::policy-pass-ui-{ACCOUNT_ID}/*",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "arn:aws:cloudfront::{ACCOUNT_ID}:distribution/{DISTRIBUTION_ID}"
                }
            }
        }
    ]
}
```

1. **변경 사항 저장**

#### 초기 배포 테스트

```bash
# 로컬에서 UI 빌드
cd services/ui
npm ci
VITE_API_BASE_URL=http://{API_PUBLIC_IP}:8080 npm run build

# S3에 업로드
aws s3 sync dist/ s3://policy-pass-ui-{ACCOUNT_ID}/ --delete

# 캐시 무효화
aws cloudfront create-invalidation \
  --distribution-id {DISTRIBUTION_ID} \
  --paths "/*"
```

#### 검증

- 브라우저에서 `https://{DISTRIBUTION_DOMAIN}.cloudfront.net` 접속 → React UI 표시
- 임의 경로 `https://{DISTRIBUTION_DOMAIN}.cloudfront.net/any/route` → SPA 라우팅 동작 (index.html 반환)
- 브라우저 개발자 도구 → Network 탭에서 CORS 에러 없이 API 호출 확인

> **중요**: UI와 API가 별도 도메인이므로 FastAPI에 CORS 설정이 필요하다:
>
> ```python
> app.add_middleware(
>     CORSMiddleware,
>     allow_origins=["https://{DISTRIBUTION_DOMAIN}.cloudfront.net"],
>     allow_methods=["*"],
>     allow_headers=["*"],
> )
> ```

---

### D-4. 모니터링 인스턴스 생성

1. EC2 콘솔 → **인스턴스 시작**
2. 설정:


| 항목      | 값                           |
| ------- | --------------------------- |
| 이름      | `policy-pass-monitor`       |
| AMI     | **Amazon Linux 2023**       |
| 인스턴스 유형 | **t3.small** (2 vCPU, 2 GB) |
| 키 페어    | `policy-pass-key`           |
| 보안 그룹   | `policy-pass-monitor-sg`    |
| 스토리지    | 15 GiB gp3                  |


1. **사용자 데이터**:

```bash
#!/bin/bash
yum update -y
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# Docker Compose 설치
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# 모니터링 설정 디렉토리
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
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-policypass2026}
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - grafana_data:/var/lib/grafana
    depends_on:
      - prometheus
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
```

1. **인스턴스 시작**

#### 첫 실행

```bash
ssh -i ~/Downloads/policy-pass-key.pem ec2-user@{MONITOR_PUBLIC_IP}
cd monitoring
docker-compose up -d
```

#### 검증

- Grafana: `http://{MONITOR_PUBLIC_IP}:3000` → 로그인 (admin / policypass2026)
- Prometheus: `http://{MONITOR_PUBLIC_IP}:9090` → Prometheus UI

> API 서버의 메트릭을 수집하려면 `prometheus.yml`의 `scrape_configs`에 타겟을 추가한다.  
> 예: `targets: ['{API_PUBLIC_IP}:8080']`

---

### D-5. 탄력적 IP 할당 (선택 권장)

EC2 인스턴스를 중지/시작하면 퍼블릭 IP가 변경된다. 고정 IP가 필요하면:

1. EC2 콘솔 → 좌측 **네트워크 및 보안** → **탄력적 IP(Elastic IPs)**
2. **탄력적 IP 주소 할당** → **할당**
3. 할당된 IP 선택 → **작업** → **탄력적 IP 주소 연결**
4. 인스턴스: `policy-pass-api` 선택 → **연결**
5. 모니터링 인스턴스도 동일하게 반복 (총 2개 탄력적 IP)

> **주의**: 탄력적 IP는 인스턴스에 연결되어 있으면 무료, 연결 안 하면 과금.  
> 인스턴스 삭제 시 탄력적 IP도 반드시 릴리스해야 한다.

---

## Phase E: CloudWatch 모니터링

### E-1. CloudWatch 알람 설정

1. **CloudWatch** 콘솔 접속: `console.aws.amazon.com/cloudwatch`
2. 좌측 메뉴 → **알람(Alarms)** → **모든 알람** → **알람 생성(Create alarm)**

#### 알람 1: API 서버 CPU 사용률

1. **지표 선택(Select metric)** 클릭
2. **EC2** → **인스턴스별 지표** → `policy-pass-api` 인스턴스의 `CPUUtilization` 선택
3. 통계: **평균(Average)**
4. 기간: **5분**
5. 조건:
  - 임계값 유형: **정적**
  - 조건: **보다 큼(Greater than)**
  - 임계값: `80`
6. **다음(Next)**
7. 알림: (선택) SNS 토픽 연결하여 이메일 알림. 불필요하면 **알림 제거**
8. 알람 이름: `policy-pass-api-cpu-high`
9. **알람 생성**

#### 알람 2: EC2 상태 체크 실패

1. 동일하게 `policy-pass-api` 인스턴스의 `StatusCheckFailed` 지표 선택
2. 임계값: `1` (보다 크거나 같음)
3. 알람 이름: `policy-pass-api-status-check`
4. **알람 생성**

#### 검증

- 알람 목록에서 2개 알람 확인
- 상태: `OK` (정상 시)

---

## Phase F: CI/CD (GitHub Actions)

> Phase F는 콘솔 작업이 아니라 **GitHub 설정**이다.  
> 인프라 담당(Daehyun)이 설정 완료함. 팀원은 신경 쓸 필요 없음.

### GitHub 시크릿 (설정 필요)

레포지토리(`policy-pass-infra-aws`)에 아래 시크릿을 등록한다:


| Name                         | 설명                                         |
| ---------------------------- | ------------------------------------------ |
| `AWS_ACCESS_KEY_ID`          | IAM 사용자 Access Key                         |
| `AWS_SECRET_ACCESS_KEY`      | IAM 사용자 Secret Key                         |
| `EC2_API_HOST`               | API EC2 퍼블릭 IP (탄력적 IP)                    |
| `EC2_SSH_KEY`                | SSH 프라이빗 키 (policy-pass-key.pem 내용)        |
| `UI_S3_BUCKET`               | UI S3 버킷명 (`policy-pass-ui-{ACCOUNT_ID}`)  |
| `CLOUDFRONT_DISTRIBUTION_ID` | CloudFront Distribution ID                 |
| `API_BASE_URL`               | API 엔드포인트 (`http://{API_ELASTIC_IP}:8080`) |


### 배포 흐름

#### API 배포

```
main 브랜치에 push (services/api/** 변경)
    ↓
GitHub Actions 실행
    ↓
Docker 이미지 빌드 → ECR push (태그: ${GITHUB_SHA} + latest)
    ↓
SSH로 EC2 접속 → deploy.sh 실행
    ↓
최신 이미지 pull → 컨테이너 재시작
```

#### UI 배포

```
main 브랜치에 push (services/ui/** 변경)
    ↓
GitHub Actions 실행
    ↓
Node.js 20 setup → npm ci → vite build (VITE_API_BASE_URL 주입)
    ↓
aws s3 sync dist/ → S3 버킷
  - JS/CSS/이미지 (해시 포함): Cache-Control max-age=31536000, immutable
  - index.html, *.json: Cache-Control no-cache, must-revalidate
    ↓
aws cloudfront create-invalidation --paths "/*"
```

---

## 운영 가이드

### 비용 절감 (인스턴스 중지)

사용하지 않을 때 EC2 인스턴스를 중지하면 컴퓨팅 비용이 발생하지 않는다 (EBS 스토리지 비용만 발생).  
S3 + CloudFront는 중지할 필요 없이 저비용으로 항상 운영된다.

1. EC2 콘솔 → 인스턴스 선택 → **인스턴스 상태** → **인스턴스 중지**
2. 다시 필요하면 **인스턴스 시작**

> **주의**: 탄력적 IP 없이 인스턴스를 중지/시작하면 퍼블릭 IP가 변경된다.  
> 탄력적 IP를 할당해두면 IP가 유지된다.

### 수동 배포

#### API (SSH)

```bash
ssh -i ~/Downloads/policy-pass-key.pem ec2-user@{API_PUBLIC_IP}
./deploy.sh
```

#### UI (S3 + CloudFront)

```bash
cd services/ui
VITE_API_BASE_URL=http://{API_PUBLIC_IP}:8080 npm run build
aws s3 sync dist/ s3://policy-pass-ui-{ACCOUNT_ID}/ --delete
aws cloudfront create-invalidation --distribution-id {DISTRIBUTION_ID} --paths "/*"
```

### 비용 예상 (월 기준)


| 서비스                    | 예상 비용        | 비고                     |
| ---------------------- | ------------ | ---------------------- |
| EC2 API (t3.medium)    | ~$30         | On-demand, 미사용 시 중지    |
| EC2 Monitor (t3.small) | ~$15         | On-demand, 미사용 시 중지    |
| S3 (UI 정적 파일)          | ~$0.02       | 빌드 결과물 저장              |
| CloudFront             | ~$0.5-1      | CDN 배포, 트래픽 소량         |
| ECR                    | ~$1          | API 이미지 스토리지           |
| S3 (FAISS 인덱스)         | < $1         | 인덱스 파일 저장              |
| DataSync               | ~$0.04/GB    | 전송량 기준                 |
| SSM Parameter Store    | 무료           | Standard tier          |
| CloudWatch             | ~$1-3        | 알람 + 로그                |
| **합계 (always on)**     | **~$48.5/월** |                        |
| **합계 (dev, stopped)**  | **~$5-10/월** | EBS + S3 + CloudFront만 |


### 리소스 정리 (teardown)

AWS 비용이 더 이상 필요 없을 때 역순으로 삭제한다:

1. **EC2**: 인스턴스 2개 종료 (`policy-pass-monitor` → `policy-pass-api`)
2. **탄력적 IP**: 연결 해제 → 릴리스 (2개)
3. **CloudFront**: Distribution 비활성화 → 삭제 → OAC 삭제
4. **S3 (UI)**: `policy-pass-ui-{ACCOUNT_ID}` 비우기 → 삭제
5. **보안 그룹**: 2개 삭제
6. **키 페어**: 삭제
7. **CloudWatch**: 알람 삭제
8. **DataSync**: 태스크 → 위치 삭제
9. **SSM**: 파라미터 삭제
10. **S3 (Index)**: `rag-qa-index-{ACCOUNT_ID}` 비우기 → 삭제
11. **ECR**: 이미지 삭제 → 레포지토리 삭제
12. **IAM**: 인라인 정책 삭제 → 역할 삭제

---

## 트러블슈팅

### EC2에서 docker 명령어가 안 됨

```bash
# ec2-user를 docker 그룹에 추가 후 재접속
sudo usermod -aG docker ec2-user
exit
# 다시 SSH 접속
```

### deploy.sh 실행 시 ECR 로그인 실패

- EC2 인스턴스에 `EC2InstanceRole`이 연결되어 있는지 확인
- 역할에 `AmazonEC2ContainerRegistryReadOnly` 정책이 있는지 확인

### 컨테이너가 시작되지만 외부에서 접속 불가

- 보안 그룹에 8080 포트가 열려 있는지 확인
- `docker ps`로 컨테이너가 정상 실행 중인지 확인
- `docker logs rag-api`로 에러 확인

### CloudFront에서 403 Forbidden

- S3 버킷 정책에 CloudFront OAC 허용이 설정되어 있는지 확인
- `{DISTRIBUTION_ID}`가 실제 Distribution ID와 일치하는지 확인
- S3 버킷에 `index.html` 파일이 존재하는지 확인

### UI에서 API 연결 실패 (CORS 에러)

- FastAPI에 CORS 미들웨어가 CloudFront 도메인을 `allow_origins`에 포함하는지 확인
- `VITE_API_BASE_URL` 환경변수가 빌드 시 올바르게 주입되었는지 확인
- API 인스턴스의 보안 그룹에서 8080 포트가 열려 있는지 확인
- API 컨테이너가 정상 실행 중인지 확인: `curl http://{API_IP}:8080/health`

### SPA 라우팅이 동작하지 않음 (새로고침 시 404)

- CloudFront Distribution의 **오류 페이지(Error pages)** 에 403/404 → `/index.html` (200) 매핑이 있는지 확인
- 오류 캐싱 최소 TTL이 `0`으로 설정되어 있는지 확인

### DataSync 전송 실패

- GCS HMAC 키가 유효한지 확인
- GCS 버킷에 `index/` 폴더와 파일이 존재하는지 확인
- `DataSyncS3Role`이 S3 버킷에 쓰기 권한이 있는지 확인

