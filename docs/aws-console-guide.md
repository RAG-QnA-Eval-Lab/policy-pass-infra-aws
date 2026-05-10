# AWS 콘솔 인프라 구축 가이드

> **관련 문서**: [AWS 인프라 구축 계획서](./aws-infrastructure-plan.md)  
> **최종 수정일**: 2026-05-10  
> **담당자**: Daehyun Kim

이 문서는 AWS 콘솔(웹 UI)에서 직접 인프라를 구축하는 **스텝바이스텝 가이드**이다.  
각 Phase는 [계획서](./aws-infrastructure-plan.md)의 구현 순서를 따른다.

> **사전 준비**  
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

#### 역할 3: DataSyncS3Role

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

- **역할(Roles)** 목록에서 3개 역할 확인:
  - `EC2InstanceRole`
  - `DataSyncS3Role`

---

### A-2. ECR 레포지토리 생성

1. **ECR** 콘솔 접속: `console.aws.amazon.com/ecr`
2. 좌측 메뉴 → **Private registry** → **Repositories** → **리포지토리 생성(Create repository)**

#### 레포지토리 1: rag-api

3. 가시성: **Private**
4. 리포지토리 이름: `rag-api`
5. 나머지 기본값 유지 → **리포지토리 생성**
6. 생성된 `rag-api` 클릭 → 좌측 **Lifecycle Policy** → **규칙 생성(Create rule)**
7. 규칙 설정:
   - 규칙 우선순위: `1`
   - 이미지 태그 상태: **태그가 지정되지 않음(Untagged)**
   - 매치 범위: **이미지 개수(Image count)** 선택 (목록 마지막 항목)
   - 이미지 개수: `5`
   - 작업: **만료(Expire)**
8. **저장**

#### 레포지토리 2: rag-ui

9. 동일하게 반복: 이름 `rag-ui`, 같은 수명주기 정책 적용

#### 검증

- Repositories 목록에 `rag-api`, `rag-ui` 2개 표시

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

9. 생성된 버킷 클릭 → **관리(Management)** 탭 → **수명주기 규칙 생성**
10. 규칙 이름: `delete-old-versions`
11. 범위: **버킷의 모든 객체에 적용**
12. 수명주기 규칙 작업: **비현재 버전의 객체를 영구적으로 삭제** 체크
13. 비현재 버전 유지 일 수: `30`
14. **규칙 생성**

#### 폴더 구조 생성

15. 버킷 내에서 **폴더 만들기** → 이름: `index` → **폴더 만들기**

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

3. **새 위치 생성(Create a new location)** 선택
4. 위치 유형: **Object storage**
5. 서버:
   - 에이전트: **없음(No agent)** — 클라우드 간 직접 전송
   - 서버 호스트네임: `storage.googleapis.com`
   - 버킷 이름: `{GCS_BUCKET_NAME}` (GCP 프로젝트의 FAISS 인덱스 버킷명)
   - 폴더: `/index/`
6. 인증:
   - 접근 키: GCS HMAC Access Key
   - 비밀 키: GCS HMAC Secret Key
7. **다음(Next)**

#### 대상 위치 설정

8. **새 위치 생성** 선택
9. 위치 유형: **Amazon S3**
10. S3 버킷: 드롭다운에서 `rag-qa-index-{ACCOUNT_ID}` 선택
11. 폴더: `/index/`
12. IAM 역할: 드롭다운에서 `DataSyncS3Role` 선택
13. **다음(Next)**

#### 태스크 설정

14. 태스크 이름: `gcs-to-s3-faiss-index`
15. 전송 설정:
    - 전송 모드: **변경된 데이터만 전송(Transfer only data that has changed)**
    - 검증: **전송된 데이터만 확인(Verify only the data transferred)**
    - 대상에서 삭제된 파일: **유지(Keep deleted files)**
    - 덮어쓰기 모드: **항상(Always)**
16. 스케줄: **실행하지 않음(Not scheduled)** — Airflow에서 수동으로 트리거
17. 로깅: **CloudWatch Log 그룹 자동 생성** (선택)
18. **다음(Next)** → **태스크 생성**

#### 검증

- 태스크 목록에서 `gcs-to-s3-faiss-index` 확인
- 상태: `Available`
- **시작(Start)** 클릭하여 테스트 실행 → S3 버킷의 `index/` 폴더에 파일 도착 확인

---

### B-2. SSM Parameter Store 설정

1. **Systems Manager** 콘솔 접속: `console.aws.amazon.com/systems-manager`
2. 좌측 메뉴 → **파라미터 스토어(Parameter Store)** → **파라미터 생성(Create parameter)**

#### 파라미터 1: OpenAI API Key

3. 이름: `/rag-qa/openai-api-key`
4. 설명: `OpenAI API Key for RAG QA`
5. 계층: **표준(Standard)**
6. 유형: **SecureString**
7. KMS 키 소스: **현재 계정** (기본 aws/ssm 키 사용)
8. 값: OpenAI API 키 입력
9. **파라미터 생성**

#### 파라미터 2: MongoDB URI

10. 이름: `/rag-qa/mongodb-uri`
11. 유형: **SecureString**
12. 값: MongoDB 연결 문자열 입력
13. **파라미터 생성**

#### 파라미터 3: S3 Bucket

14. 이름: `/rag-qa/s3-bucket`
15. 유형: **String**
16. 값: `rag-qa-index-{ACCOUNT_ID}`
17. **파라미터 생성**

#### 파라미터 4: Index S3 Prefix

18. 이름: `/rag-qa/index-s3-prefix`
19. 유형: **String**
20. 값: `index/`
21. **파라미터 생성**

#### 검증

- 파라미터 목록에서 `/rag-qa/` 경로 아래 4개 파라미터 확인
- SecureString 파라미터는 값이 `****`로 마스킹되어 표시

---

## Phase C: 애플리케이션 준비

> Phase C는 콘솔 작업이 아니라 **코드 작업**이다.  
> Dockerfile, Dockerfile.ui, pyproject.toml 등을 작성하고 GitHub에 push한 뒤,  
> ECR에 초기 이미지를 push해야 Phase D(App Runner)를 진행할 수 있다.

### ECR에 초기 이미지 Push (로컬 터미널)

Phase D 전에 ECR에 최소 1개의 이미지가 있어야 App Runner 서비스를 생성할 수 있다.

```bash
# 1. ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin {ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com

# 2. API 이미지 빌드 & 푸시
docker build -t rag-api .
docker tag rag-api:latest {ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/rag-api:initial
docker push {ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/rag-api:initial

# 3. UI 이미지 빌드 & 푸시
docker build -f Dockerfile.ui -t rag-ui .
docker tag rag-ui:latest {ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/rag-ui:initial
docker push {ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/rag-ui:initial
```

#### 검증

- ECR 콘솔에서 `rag-api`, `rag-ui` 레포지토리에 `initial` 태그 이미지 존재 확인

---

## Phase D: EC2 인스턴스 생성

> **비용**: t2.micro 무료 티어 750시간/월. 인스턴스 2개 운영 시 약 $8/월 추가 발생.  
> 크레딧 잔액으로 충분히 커버 가능.

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

2. 보안 그룹 이름: `policy-pass-api-sg`
3. 설명: `Policy Pass API server`
4. VPC: 기본 VPC
5. 인바운드 규칙 추가:

| 유형 | 포트 범위 | 소스 | 설명 |
|------|----------|------|------|
| SSH | 22 | 내 IP | SSH 접속 |
| 사용자 지정 TCP | 8080 | 0.0.0.0/0 | API 포트 |

6. 아웃바운드 규칙: 기본값 유지 (모든 트래픽 허용)
7. **보안 그룹 생성**

#### 보안 그룹 2: UI 서버용

8. 보안 그룹 이름: `policy-pass-ui-sg`
9. 설명: `Policy Pass UI server`
10. 인바운드 규칙 추가:

| 유형 | 포트 범위 | 소스 | 설명 |
|------|----------|------|------|
| SSH | 22 | 내 IP | SSH 접속 |
| 사용자 지정 TCP | 8501 | 0.0.0.0/0 | Streamlit 포트 |

11. **보안 그룹 생성**

### D-2. API 인스턴스 생성

1. EC2 콘솔 → **인스턴스 시작(Launch instances)**
2. 설정:

| 항목 | 값 |
|------|-----|
| 이름 | `policy-pass-api` |
| AMI | **Amazon Linux 2023** (프리 티어 사용 가능) |
| 인스턴스 유형 | **t2.micro** (1 vCPU, 1 GB) |
| 키 페어 | `policy-pass-key` |
| 보안 그룹 | `policy-pass-api-sg` (기존 보안 그룹 선택) |
| IAM 인스턴스 프로파일 | `EC2InstanceRole` |
| 스토리지 | 20 GiB gp3 (프리 티어 30GB 한도 내) |

3. **고급 세부 정보** 펼치기 → **IAM 인스턴스 프로파일**: `EC2InstanceRole` 선택
4. **사용자 데이터(User data)** 에 아래 스크립트 입력:

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
ACCOUNT_ID=355206939988
ECR_REGISTRY=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
IMAGE=$ECR_REGISTRY/rag-api:latest

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
docker pull $IMAGE
docker stop rag-api 2>/dev/null
docker rm rag-api 2>/dev/null
docker run -d --name rag-api -p 8080:8080 \
  -e DOWNLOAD_INDEX_FROM_S3=true \
  -e S3_BUCKET=rag-qa-index-355206939988 \
  -e INDEX_S3_PREFIX=index/ \
  -e ENVIRONMENT=production \
  --restart unless-stopped \
  $IMAGE
DEPLOY
chmod +x /home/ec2-user/deploy.sh
chown ec2-user:ec2-user /home/ec2-user/deploy.sh
```

5. **인스턴스 시작**

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

### D-3. UI 인스턴스 생성

1. EC2 콘솔 → **인스턴스 시작**
2. 설정:

| 항목 | 값 |
|------|-----|
| 이름 | `policy-pass-ui` |
| AMI | **Amazon Linux 2023** |
| 인스턴스 유형 | **t2.micro** |
| 키 페어 | `policy-pass-key` |
| 보안 그룹 | `policy-pass-ui-sg` |
| 스토리지 | 10 GiB gp3 |

3. **사용자 데이터**:

```bash
#!/bin/bash
yum update -y
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

cat > /home/ec2-user/deploy.sh << 'DEPLOY'
#!/bin/bash
REGION=ap-northeast-2
ACCOUNT_ID=355206939988
ECR_REGISTRY=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
IMAGE=$ECR_REGISTRY/rag-ui:latest

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
docker pull $IMAGE
docker stop rag-ui 2>/dev/null
docker rm rag-ui 2>/dev/null
docker run -d --name rag-ui -p 8501:8501 \
  -e API_BASE_URL=http://{API_PUBLIC_IP}:8080 \
  --restart unless-stopped \
  $IMAGE
DEPLOY
chmod +x /home/ec2-user/deploy.sh
chown ec2-user:ec2-user /home/ec2-user/deploy.sh
```

> **주의**: `{API_PUBLIC_IP}`를 D-2에서 생성된 API 인스턴스의 퍼블릭 IP로 교체해야 한다.

4. **인스턴스 시작**

#### 첫 배포

```bash
ssh -i ~/Downloads/policy-pass-key.pem ec2-user@{UI_PUBLIC_IP}
./deploy.sh
```

#### 검증

- 브라우저에서 `http://{UI_PUBLIC_IP}:8501` 접속 → Streamlit UI 표시

---

### D-4. 탄력적 IP 할당 (선택 권장)

EC2 인스턴스를 중지/시작하면 퍼블릭 IP가 변경된다. 고정 IP가 필요하면:

1. EC2 콘솔 → 좌측 **네트워크 및 보안** → **탄력적 IP(Elastic IPs)**
2. **탄력적 IP 주소 할당** → **할당**
3. 할당된 IP 선택 → **작업** → **탄력적 IP 주소 연결**
4. 인스턴스: `policy-pass-api` 선택 → **연결**
5. UI 인스턴스도 동일하게 반복

> **주의**: 탄력적 IP는 인스턴스에 연결되어 있으면 무료, 연결 안 하면 과금.  
> 인스턴스 삭제 시 탄력적 IP도 반드시 릴리스해야 한다.

---

## Phase E: CloudWatch 모니터링

### E-1. CloudWatch 알람 설정

1. **CloudWatch** 콘솔 접속: `console.aws.amazon.com/cloudwatch`
2. 좌측 메뉴 → **알람(Alarms)** → **모든 알람** → **알람 생성(Create alarm)**

#### 알람 1: API 서버 CPU 사용률

3. **지표 선택(Select metric)** 클릭
4. **EC2** → **인스턴스별 지표** → `policy-pass-api` 인스턴스의 `CPUUtilization` 선택
5. 통계: **평균(Average)**
6. 기간: **5분**
7. 조건:
   - 임계값 유형: **정적**
   - 조건: **보다 큼(Greater than)**
   - 임계값: `80`
8. **다음(Next)**
9. 알림: (선택) SNS 토픽 연결하여 이메일 알림. 불필요하면 **알림 제거**
10. 알람 이름: `policy-pass-api-cpu-high`
11. **알람 생성**

#### 알람 2: UI 서버 CPU 사용률

12. 동일하게 `policy-pass-ui` 인스턴스의 `CPUUtilization` 선택
13. 임계값: `80`
14. 알람 이름: `policy-pass-ui-cpu-high`
15. **알람 생성**

#### 검증

- 알람 목록에서 2개 알람 확인
- 상태: `OK` (정상 시)

---

## Phase F: CI/CD (GitHub Actions)

> Phase F는 콘솔 작업이 아니라 **GitHub 설정**이다.  
> 인프라 담당(Daehyun)이 설정 완료함. 팀원은 신경 쓸 필요 없음.

### GitHub 시크릿 (설정 완료)

각 repo(policy-pass-be, policy-pass-fe)에 아래 시크릿이 등록됨:

| Name | 설명 |
|------|------|
| `AWS_ACCESS_KEY_ID` | IAM 사용자 Access Key |
| `AWS_SECRET_ACCESS_KEY` | IAM 사용자 Secret Key |
| `EC2_HOST` | EC2 퍼블릭 IP (탄력적 IP 할당 후 등록) |
| `EC2_SSH_KEY` | SSH 프라이빗 키 (policy-pass-key.pem 내용) |

### 배포 흐름

```
main 브랜치에 push
    ↓
GitHub Actions 실행
    ↓
Docker 이미지 빌드 → ECR push
    ↓
SSH로 EC2 접속 → deploy.sh 실행
    ↓
최신 이미지 pull → 컨테이너 재시작
```

---

## 운영 가이드

### 비용 절감 (인스턴스 중지)

사용하지 않을 때 인스턴스를 중지하면 컴퓨팅 비용이 발생하지 않는다 (EBS 스토리지 비용만 발생).

1. EC2 콘솔 → 인스턴스 선택 → **인스턴스 상태** → **인스턴스 중지**
2. 다시 필요하면 **인스턴스 시작**

> **주의**: 탄력적 IP 없이 인스턴스를 중지/시작하면 퍼블릭 IP가 변경된다.  
> 탄력적 IP를 할당해두면 IP가 유지된다.

### 수동 배포 (SSH)

```bash
ssh -i ~/Downloads/policy-pass-key.pem ec2-user@{PUBLIC_IP}
./deploy.sh
```

### 리소스 정리 (teardown)

AWS 비용이 더 이상 필요 없을 때 역순으로 삭제한다:

1. **EC2**: 인스턴스 2개 종료 (`policy-pass-ui` → `policy-pass-api`)
2. **탄력적 IP**: 연결 해제 → 릴리스
3. **보안 그룹**: 2개 삭제
4. **키 페어**: 삭제
5. **CloudWatch**: 알람 삭제
6. **DataSync**: 태스크 → 위치 삭제
7. **SSM**: 파라미터 삭제
8. **S3**: 버킷 비우기(Empty) → 버킷 삭제
9. **ECR**: 이미지 삭제 → 레포지토리 삭제
10. **IAM**: 인라인 정책 삭제 → 역할 삭제

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

- 보안 그룹에 해당 포트(8080 또는 8501)가 열려 있는지 확인
- `docker ps`로 컨테이너가 정상 실행 중인지 확인
- `docker logs rag-api` 또는 `docker logs rag-ui`로 에러 확인

### UI에서 API 연결 실패

- `API_BASE_URL`이 API 인스턴스의 퍼블릭 IP를 정확히 가리키는지 확인
- API 인스턴스의 보안 그룹에서 8080 포트가 열려 있는지 확인
- API 컨테이너가 정상 실행 중인지 확인: `curl http://{API_IP}:8080/health`

### DataSync 전송 실패

- GCS HMAC 키가 유효한지 확인
- GCS 버킷에 `index/` 폴더와 파일이 존재하는지 확인
- `DataSyncS3Role`이 S3 버킷에 쓰기 권한이 있는지 확인
