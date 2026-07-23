---

# Day 13 - Nginx 백업 S3 자동 업로드 구축

## 1. 실습 목표

이번 실습에서는 기존 Nginx 로컬 백업 스크립트와 AWS CLI를 연결하여 다음 작업을 자동화했다.

- Nginx HTML 데이터 백업 생성
- SHA-256 체크섬 생성
- 최신 백업 파일 자동 탐색
- AWS S3 자동 업로드
- 중복 실행 방지
- 실행 결과 로그 기록
- Cron을 이용한 정기 실행
- S3 업로드 결과 검증

---

## 2. 자동 백업 구조

```text
Nginx HTML
    ↓
backup-nginx.sh
    ↓
로컬 tar.gz 백업 및 SHA-256 생성
    ↓
upload-s3.sh
    ↓
AWS CLI
    ↓
Amazon S3 nginx-backups/
```

사용한 주요 경로는 다음과 같다.

| 구분 | 경로 |
|---|---|
| Nginx 데이터 | `/home/sungwoo/docker-nginx/html` |
| 로컬 백업 디렉터리 | `/home/sungwoo/home-idc-lab/backups` |
| 기존 백업 스크립트 | `/home/sungwoo/home-idc-lab/scripts/backup-nginx.sh` |
| S3 업로드 스크립트 | `/home/sungwoo/home-idc-lab/scripts/upload-s3.sh` |
| S3 업로드 로그 | `/home/sungwoo/home-idc-lab/logs/s3-upload.log` |
| Cron 설정 파일 | `/home/sungwoo/home-idc-lab/cron/home-idc.cron` |
| AWS CLI 프로필 | `home-idc-s3-backup` |
| S3 버킷 | `home-idc-backup-lab-20260723-k7m4` |
| S3 저장 경로 | `nginx-backups/` |

---

## 3. S3 자동 업로드 스크립트 작성

다음 경로에 자동 업로드 스크립트를 작성했다.

```text
/home/sungwoo/home-idc-lab/scripts/upload-s3.sh
```

스크립트 내용:

```bash
#!/bin/bash

set -euo pipefail

export HOME="/home/sungwoo"
export PATH="/usr/local/bin:/usr/bin:/bin"

BACKUP_SCRIPT="/home/sungwoo/home-idc-lab/scripts/backup-nginx.sh"
BACKUP_DIR="/home/sungwoo/home-idc-lab/backups"
BUCKET="s3://home-idc-backup-lab-20260723-k7m4"
S3_PREFIX="nginx-backups"
PROFILE="home-idc-s3-backup"
LOCK_FILE="/tmp/home-idc-s3-upload.lock"

exec 9>"$LOCK_FILE"

if ! flock -n 9; then
  echo "FAIL: Another S3 upload job is already running" >&2
  exit 1
fi

echo "===== Home IDC S3 Backup Upload ====="
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo

"$BACKUP_SCRIPT"

LATEST_BACKUP="$(
  find "$BACKUP_DIR" -maxdepth 1 -type f \
    -name 'nginx-html-*.tar.gz' \
    -printf '%T@ %p\n' |
  sort -nr |
  head -n 1 |
  cut -d' ' -f2-
)"

if [ -z "$LATEST_BACKUP" ] || [ ! -f "$LATEST_BACKUP" ]; then
  echo "FAIL: Backup file was not found" >&2
  exit 1
fi

CHECKSUM_FILE="${LATEST_BACKUP}.sha256"
BACKUP_NAME="$(basename "$LATEST_BACKUP")"

echo "Uploading: $BACKUP_NAME"

/usr/local/bin/aws s3 cp \
  "$LATEST_BACKUP" \
  "$BUCKET/$S3_PREFIX/$BACKUP_NAME" \
  --profile "$PROFILE" \
  --only-show-errors

if [ -f "$CHECKSUM_FILE" ]; then
  /usr/local/bin/aws s3 cp \
    "$CHECKSUM_FILE" \
    "$BUCKET/$S3_PREFIX/$(basename "$CHECKSUM_FILE")" \
    --profile "$PROFILE" \
    --only-show-errors
else
  echo "WARN: Checksum file was not found: $CHECKSUM_FILE" >&2
fi

echo
echo "S3 upload completed: $BUCKET/$S3_PREFIX/$BACKUP_NAME"
```

---

## 4. 스크립트 주요 기능

### 오류 발생 시 즉시 종료

```bash
set -euo pipefail
```

명령 실패, 정의되지 않은 변수 사용 또는 파이프라인 오류가 발생하면 스크립트를 즉시 종료한다.

### Cron 실행 환경 설정

```bash
export HOME="/home/sungwoo"
export PATH="/usr/local/bin:/usr/bin:/bin"
```

Cron은 일반 터미널보다 제한된 환경 변수로 실행되므로 AWS CLI와 사용자 프로필을 정상적으로 찾을 수 있도록 설정했다.

### 중복 실행 방지

```bash
exec 9>"/tmp/home-idc-s3-upload.lock"
flock -n 9
```

이전 백업 작업이 끝나기 전에 새로운 작업이 시작되는 것을 방지했다.

### 최신 백업 자동 탐색

```bash
find "$BACKUP_DIR" -maxdepth 1 -type f \
  -name 'nginx-html-*.tar.gz' \
  -printf '%T@ %p\n' |
sort -nr |
head -n 1
```

백업 디렉터리에서 수정 시간이 가장 최근인 압축 파일을 자동으로 선택한다.

### 백업 파일과 체크섬 업로드

다음 두 파일을 S3에 함께 업로드하도록 구성했다.

```text
nginx-html-YYYYMMDD-HHMMSS.tar.gz
nginx-html-YYYYMMDD-HHMMSS.tar.gz.sha256
```

---

## 5. 실행 권한 설정

스크립트에 실행 권한을 부여했다.

```bash
chmod +x /home/sungwoo/home-idc-lab/scripts/upload-s3.sh
```

---

## 6. 수동 실행 테스트

스크립트를 직접 실행하여 전체 백업 과정을 테스트했다.

```bash
/home/sungwoo/home-idc-lab/scripts/upload-s3.sh
```

정상 실행 결과:

```text
===== Home IDC S3 Backup Upload =====
Time: 2026-07-23 03:55:29

Backup completed: /home/sungwoo/home-idc-lab/backups/nginx-html-20260723-035529.tar.gz
Uploading: nginx-html-20260723-035529.tar.gz

S3 upload completed: s3://home-idc-backup-lab-20260723-k7m4/nginx-backups/nginx-html-20260723-035529.tar.gz
```

---

## 7. AWS 요청 시간 오류 발생

첫 번째 S3 업로드 시 다음 오류가 발생했다.

```text
RequestTimeTooSkewed
The difference between the request time and the current time is too large.
```

Ubuntu VM 시간이 AWS 서버 시간보다 약 1시간 18분 느린 것이 원인이었다.

AWS 요청 서명에는 요청 시간이 포함되기 때문에 시스템 시간이 크게 다르면 인증 요청이 거부된다.

---

## 8. VM 시간과 AWS 시간 비교

Ubuntu VM의 UTC 시간과 AWS S3 서버의 HTTP 응답 시간을 비교했다.

```bash
echo "VM UTC: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" &&
curl -sI https://s3.ap-northeast-2.amazonaws.com/ |
grep -i '^date:'
```

오류 발생 당시 결과:

```text
VM UTC: 2026-07-23 02:35:43 UTC
Date: Thu, 23 Jul 2026 03:53:43 GMT
```

약 1시간 18분의 차이가 있는 것을 확인했다.

---

## 9. Chrony 시간 동기화 복구

Chrony 서비스를 재시작하고 새로운 NTP 측정을 강제로 수행했다.

```bash
sudo systemctl restart chrony &&
sleep 5 &&
sudo chronyc burst 4/4 &&
sleep 10 &&
sudo chronyc makestep
```

시간 동기화 후 다시 비교했다.

```bash
date -u
curl -sI https://s3.ap-northeast-2.amazonaws.com/ |
grep -i '^date:'
```

결과:

```text
Thu Jul 23 03:54:59 AM UTC 2026
Date: Thu, 23 Jul 2026 03:54:59 GMT
```

Ubuntu VM 시간과 AWS 시간이 정확하게 일치하는 것을 확인했다.

시간 동기화 후 S3 업로드 스크립트가 정상 작동했다.

---

## 10. S3 업로드 결과 확인

AWS CLI를 이용하여 업로드된 객체를 확인했다.

```bash
aws s3 ls \
  s3://home-idc-backup-lab-20260723-k7m4/nginx-backups/ \
  --profile home-idc-s3-backup
```

출력 결과:

```text
2026-07-23 03:55:31        197 nginx-html-20260723-035529.tar.gz
2026-07-23 03:55:32        100 nginx-html-20260723-035529.tar.gz.sha256
```

백업 압축 파일과 SHA-256 체크섬 파일이 모두 정상적으로 업로드됐다.

---

## 11. Cron 자동 실행 설정

기존 로컬 백업 Cron 작업을 S3 자동 업로드 스크립트로 교체했다.

최종 Cron 설정:

```cron
*/5 * * * * /home/sungwoo/home-idc-lab/scripts/health-check.sh >> /home/sungwoo/home-idc-lab/logs/cron-health-check.log 2>&1
0 2 * * * /home/sungwoo/home-idc-lab/scripts/upload-s3.sh >> /home/sungwoo/home-idc-lab/logs/s3-upload.log 2>&1
```

현재 서버 시간대가 UTC이므로 S3 백업 작업은 매일 다음 시간에 실행된다.

```text
02:00 UTC
11:00 KST
```

첫 번째 작업은 5분마다 서버 상태를 점검하고, 두 번째 작업은 매일 한 번 로컬 백업 생성과 S3 업로드를 수행한다.

---

## 12. Cron 설정 파일 저장

현재 Crontab을 GitHub에 기록하기 위해 파일로 저장했다.

```bash
mkdir -p /home/sungwoo/home-idc-lab/cron
```

```bash
crontab -l > /home/sungwoo/home-idc-lab/cron/home-idc.cron
```

저장된 파일:

```text
cron/home-idc.cron
```

---

## 13. Cron 방식 로그 테스트

실제 Cron에서 사용하는 것과 동일한 출력 리다이렉션 방식으로 스크립트를 실행했다.

```bash
/home/sungwoo/home-idc-lab/scripts/upload-s3.sh \
  >> /home/sungwoo/home-idc-lab/logs/s3-upload.log \
  2>&1
```

로그 확인:

```bash
tail -n 20 /home/sungwoo/home-idc-lab/logs/s3-upload.log
```

출력 결과:

```text
===== Home IDC S3 Backup Upload =====
Time: 2026-07-23 04:00:21

Backup completed: /home/sungwoo/home-idc-lab/backups/nginx-html-20260723-040021.tar.gz
Uploading: nginx-html-20260723-040021.tar.gz

S3 upload completed: s3://home-idc-backup-lab-20260723-k7m4/nginx-backups/nginx-html-20260723-040021.tar.gz
```

---

## 14. 반복 실행 결과 확인

두 번째 테스트에서 생성된 파일도 S3에 정상적으로 저장됐다.

```text
nginx-html-20260723-040021.tar.gz
nginx-html-20260723-040021.tar.gz.sha256
```

전체 조회 결과:

```text
2026-07-23 03:55:31        197 nginx-html-20260723-035529.tar.gz
2026-07-23 03:55:32        100 nginx-html-20260723-035529.tar.gz.sha256
2026-07-23 04:00:23        197 nginx-html-20260723-040021.tar.gz
2026-07-23 04:00:24        100 nginx-html-20260723-040021.tar.gz.sha256
```

---

## 15. Cron 서비스 상태 확인

Cron 서비스가 실행 중인지 확인했다.

```bash
systemctl is-active cron
```

결과:

```text
active
```

---

## 16. 스크립트 문법 검사

Bash 문법 오류가 없는지 검사했다.

```bash
bash -n /home/sungwoo/home-idc-lab/scripts/upload-s3.sh &&
echo "Syntax OK"
```

결과:

```text
Syntax OK
```

---

## 17. GitHub 업로드 파일

Day 13에서 GitHub에 업로드한 파일은 다음과 같다.

```text
scripts/upload-s3.sh
cron/home-idc.cron
README.md
```

다음 파일은 보안과 저장소 용량 관리를 위해 업로드하지 않았다.

```text
~/.aws/credentials
~/.aws/config
AWS Access Key
AWS Secret Access Key
logs/s3-upload.log
backups/*.tar.gz
backups/*.sha256
```

---

## 18. 최종 검증 결과

| 테스트 | 결과 |
|---|---|
| S3 자동 업로드 스크립트 작성 | 성공 |
| Bash 실행 권한 설정 | 성공 |
| 로컬 백업 자동 생성 | 성공 |
| 최신 백업 파일 탐색 | 성공 |
| S3 압축 파일 업로드 | 성공 |
| SHA-256 파일 업로드 | 성공 |
| 중복 실행 방지 | 적용 |
| VM 시간 오류 분석 | 성공 |
| Chrony 시간 재동기화 | 성공 |
| Cron 작업 등록 | 성공 |
| Cron 로그 기록 | 성공 |
| Cron 서비스 상태 | `active` |
| Bash 문법 검사 | `Syntax OK` |

---

## 19. 이번 실습에서 익힌 내용

- 기존 백업 스크립트와 AWS CLI 연결
- Bash 함수가 아닌 독립 스크립트 간 연동
- `set -euo pipefail`을 이용한 오류 처리
- `flock`을 이용한 중복 작업 방지
- `find`, `sort`, `head`를 이용한 최신 파일 탐색
- AWS CLI 프로필을 이용한 S3 자동 업로드
- Cron의 제한된 실행 환경
- 로그 리다이렉션
- NTP 및 Chrony 시간 동기화
- AWS 요청 서명과 시스템 시간의 관계
- Bash 문법 사전 검사
- 백업 파일과 체크섬 파일을 함께 보관하는 방법

---

## 20. Day 13 완료 결과

Nginx 웹 데이터의 로컬 백업 생성부터 AWS S3 업로드까지 전 과정을 하나의 스크립트로 자동화했다.

백업 파일뿐 아니라 SHA-256 체크섬 파일도 함께 업로드하여 이후 복구 시 무결성을 검증할 수 있도록 구성했다.

또한 Cron을 이용해 정기적으로 실행되도록 설정하고, 로그 기록과 중복 실행 방지를 적용했다.

실습 중 발생한 AWS 요청 시간 오류를 VM과 AWS 서버의 시간을 직접 비교하여 원인을 확인하고 Chrony를 통해 해결했다.

다음 단계에서는 AWS EC2, CloudWatch 및 알림 서비스를 이용해 클라우드 서버 운영과 모니터링 환경을 구성한다.



---

# Day 12 - AWS IAM, S3 및 AWS CLI 백업 실습

## 1. 실습 목표

이번 실습에서는 로컬 Ubuntu 서버의 Nginx 백업 파일을 AWS S3에 안전하게 저장하고 복구하는 환경을 구성했다.

주요 목표는 다음과 같다.

- AWS 루트 사용자 사용 최소화
- IAM 관리자 사용자 생성 및 MFA 적용
- S3 백업 버킷 생성
- 버킷 버전 관리 및 기본 암호화 적용
- S3 전용 IAM 사용자 생성
- 최소 권한 IAM 정책 적용
- AWS CLI v2 설치 및 프로필 구성
- AWS CLI를 이용한 파일 업로드 및 다운로드
- SHA-256 해시를 이용한 파일 무결성 검증
- 허용되지 않은 삭제 작업 차단 확인

---

## 2. 구성 환경

| 구분 | 설정 |
|---|---|
| AWS 리전 | Asia Pacific (Seoul) |
| 리전 코드 | `ap-northeast-2` |
| S3 버킷 | `home-idc-backup-lab-20260723-k7m4` |
| 관리자 IAM 사용자 | `home-idc-admin` |
| S3 전용 IAM 사용자 | `home-idc-s3-backup` |
| AWS CLI 프로필 | `home-idc-s3-backup` |
| 운영체제 | Ubuntu Server 26.04 LTS |
| AWS CLI | AWS CLI v2 |

---

## 3. AWS 계정 보안 강화

AWS 루트 사용자 대신 일상적인 관리 작업에 사용할 IAM 관리자를 생성했다.

### 적용한 보안 설정

- 루트 사용자의 액세스 키 미사용
- 루트 사용자 MFA 확인
- IAM 관리자 사용자 생성
- IAM 관리자 그룹에 `AdministratorAccess` 정책 연결
- IAM 관리자 사용자에 패스키 MFA 등록
- IAM 관리자 로그인 성공 확인 후 루트 사용자 로그아웃
- AWS 비용 보호를 위한 Zero-Spend Budget 확인

관리 작업은 `home-idc-admin` 사용자로 수행하고, 루트 사용자는 루트 전용 작업이 필요한 경우에만 사용하도록 구성했다.

---

## 4. S3 백업 버킷 생성

서울 리전에 백업 전용 S3 버킷을 생성했다.

```text
home-idc-backup-lab-20260723-k7m4
```

### 버킷 보안 설정

- 객체 소유권: ACL 비활성화
- 모든 퍼블릭 액세스 차단
- 버킷 버전 관리 활성화
- 기본 암호화 활성화
- 암호화 방식: SSE-S3
- 리전: `ap-northeast-2`

백업 데이터가 인터넷에 공개되지 않도록 모든 퍼블릭 액세스를 차단했다.

---

## 5. S3 수동 업로드 테스트

Ubuntu 서버에 생성되어 있던 Nginx 백업 파일을 Windows로 복사했다.

### 최근 백업 파일 확인

```bash
ssh -p 2222 sungwoo@127.0.0.1 "ls -1t /home/sungwoo/home-idc-lab/backups/nginx-html-*.tar.gz | head -n 1"
```

확인된 백업 파일:

```text
/home/sungwoo/home-idc-lab/backups/nginx-html-20260720-155519.tar.gz
```

### Ubuntu에서 Windows로 복사

```powershell
scp -P 2222 sungwoo@127.0.0.1:/home/sungwoo/home-idc-lab/backups/nginx-html-20260720-155519.tar.gz .
```

복사한 파일을 AWS Management Console에서 S3 버킷으로 직접 업로드하여 정상 저장되는 것을 확인했다.

---

## 6. S3 전용 IAM 사용자 생성

AWS CLI에서 사용할 별도의 IAM 사용자를 생성했다.

```text
home-idc-s3-backup
```

이 사용자에는 AWS Management Console 로그인 권한을 부여하지 않았으며, S3 백업 작업에 필요한 권한만 부여했다.

관리자 사용자의 액세스 키를 서버에 저장하지 않고, 별도의 최소 권한 사용자를 사용하도록 구성했다.

---

## 7. 최소 권한 IAM 정책

S3 전용 사용자에게 아래 작업만 허용했다.

- 버킷 내부 객체 목록 조회
- 버킷 리전 조회
- 객체 업로드
- 객체 다운로드

객체 삭제 권한은 부여하지 않았다.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BucketAccess",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::home-idc-backup-lab-20260723-k7m4"
    },
    {
      "Sid": "ObjectAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::home-idc-backup-lab-20260723-k7m4/*"
    }
  ]
}
```

정책 이름:

```text
HomeIDCS3BackupPolicy
```

---

## 8. Ubuntu 시간 동기화 문제 해결

AWS CLI 설치 전 `apt update` 실행 시 다음 오류가 발생했다.

```text
Release file is not valid yet
```

Ubuntu VM의 시스템 날짜가 실제 날짜보다 약 3일 느린 것이 원인이었다.

### 시간 상태 확인

```bash
timedatectl status
```

### chrony를 이용한 즉시 시간 보정

```bash
sudo chronyc makestep
```

보정 후 시스템 시간이 정상적인 날짜로 변경됐으며, 패키지 업데이트를 다시 진행할 수 있었다.

---

## 9. AWS CLI v2 설치

필수 패키지를 설치했다.

```bash
sudo apt update
sudo apt install -y curl unzip
```

AWS CLI v2 설치 파일을 다운로드했다.

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
```

압축을 해제했다.

```bash
unzip awscliv2.zip
```

AWS CLI를 설치했다.

```bash
sudo ./aws/install
```

설치된 버전을 확인했다.

```bash
aws --version
```

확인된 버전:

```text
aws-cli/2.36.6
```

설치가 끝난 뒤 임시 설치 파일을 삭제했다.

```bash
rm -rf ~/aws ~/awscliv2.zip
```

---

## 10. AWS CLI 프로필 구성

S3 백업 전용 프로필을 생성했다.

```bash
aws configure --profile home-idc-s3-backup
```

설정값:

```text
Default region name: ap-northeast-2
Default output format: json
```

액세스 키와 비밀 액세스 키는 GitHub 또는 문서에 기록하지 않았다.

---

## 11. IAM 사용자 인증 확인

현재 AWS CLI가 어떤 IAM 사용자로 인증되는지 확인했다.

```bash
aws sts get-caller-identity --profile home-idc-s3-backup
```

확인 결과 AWS CLI가 아래 사용자로 정상 인증됐다.

```text
user/home-idc-s3-backup
```

---

## 12. S3 객체 목록 조회

S3 버킷에 저장된 객체를 AWS CLI에서 조회했다.

```bash
aws s3 ls s3://home-idc-backup-lab-20260723-k7m4 \
  --profile home-idc-s3-backup
```

출력 결과:

```text
nginx-html-20260720-155519.tar.gz
```

이를 통해 `s3:ListBucket` 권한이 정상적으로 작동하는 것을 확인했다.

---

## 13. AWS CLI를 이용한 백업 업로드

Ubuntu 서버의 백업 파일을 `cli-upload/` 경로로 업로드했다.

```bash
aws s3 cp \
  /home/sungwoo/home-idc-lab/backups/nginx-html-20260720-155519.tar.gz \
  s3://home-idc-backup-lab-20260723-k7m4/cli-upload/nginx-html-20260720-155519.tar.gz \
  --profile home-idc-s3-backup
```

업로드 결과:

```text
upload: home-idc-lab/backups/nginx-html-20260720-155519.tar.gz
to s3://home-idc-backup-lab-20260723-k7m4/cli-upload/nginx-html-20260720-155519.tar.gz
```

업로드된 객체를 다시 조회했다.

```bash
aws s3 ls \
  s3://home-idc-backup-lab-20260723-k7m4/cli-upload/ \
  --profile home-idc-s3-backup
```

정상적으로 파일이 조회되는 것을 확인했다.

---

## 14. S3 다운로드 및 복구 테스트

복구 테스트 디렉터리를 생성하고 S3에 저장된 파일을 다시 다운로드했다.

```bash
mkdir -p /home/sungwoo/home-idc-lab/restore-test
```

```bash
aws s3 cp \
  s3://home-idc-backup-lab-20260723-k7m4/cli-upload/nginx-html-20260720-155519.tar.gz \
  /home/sungwoo/home-idc-lab/restore-test/nginx-html-20260720-155519.tar.gz \
  --profile home-idc-s3-backup
```

다운로드가 정상적으로 완료되는 것을 확인했다.

---

## 15. SHA-256 파일 무결성 검증

원본 백업 파일과 S3에서 다운로드한 파일의 SHA-256 해시를 비교했다.

```bash
sha256sum \
  /home/sungwoo/home-idc-lab/backups/nginx-html-20260720-155519.tar.gz \
  /home/sungwoo/home-idc-lab/restore-test/nginx-html-20260720-155519.tar.gz
```

검증 결과:

```text
1e199f73a23e0418ca72f3ba6cc78141b745db25a8807d724f903ce12607c786
1e199f73a23e0418ca72f3ba6cc78141b745db25a8807d724f903ce12607c786
```

두 해시값이 일치하므로 업로드 및 다운로드 과정에서 파일이 변조되거나 손상되지 않았음을 확인했다.

---

## 16. AWS 자격 증명 파일 권한 강화

AWS CLI 자격 증명 파일의 권한을 확인했다.

```bash
ls -ld ~/.aws
ls -l ~/.aws
```

`config`와 `credentials` 파일은 소유자만 읽고 쓸 수 있는 `600` 권한으로 설정되어 있었다.

`.aws` 디렉터리 접근 권한도 소유자만 접근할 수 있도록 변경했다.

```bash
chmod 700 ~/.aws ~/.aws/cli
```

확인 결과:

```text
drwx------ /home/sungwoo/.aws
drwx------ /home/sungwoo/.aws/cli
```

---

## 17. 최소 권한 삭제 차단 테스트

S3 전용 IAM 사용자에게 삭제 권한이 없는지 확인했다.

```bash
aws s3 rm \
  s3://home-idc-backup-lab-20260723-k7m4/cli-upload/nginx-html-20260720-155519.tar.gz \
  --profile home-idc-s3-backup
```

실행 결과:

```text
AccessDenied
```

`home-idc-s3-backup` 사용자에게 `s3:DeleteObject` 권한이 없기 때문에 삭제가 차단됐다.

이를 통해 최소 권한 정책이 의도한 대로 작동하는 것을 확인했다.

---

## 18. 복구 테스트 파일 정리

검증이 끝난 임시 복구 디렉터리를 삭제했다.

```bash
rm -rf /home/sungwoo/home-idc-lab/restore-test
```

S3에 업로드된 백업 객체는 그대로 유지했다.

---

## 19. 보안상 GitHub에 업로드하지 않은 파일

다음 파일과 정보는 보안상 GitHub에 업로드하지 않았다.

```text
AWS 액세스 키 CSV 파일
~/.aws/credentials
AWS Secret Access Key
AWS Access Key ID
AWS 계정 번호
IAM 로그인 URL
임시 비밀번호
MFA 정보
```

AWS CLI 설정이 끝난 뒤 Windows에 다운로드했던 액세스 키 CSV 파일도 삭제했다.

---

## 20. 트러블슈팅

### 문제 1: `Release file is not valid yet`

원인:

```text
Ubuntu VM의 시스템 시간이 실제 시간보다 느림
```

해결:

```bash
sudo chronyc makestep
```

---

### 문제 2: dpkg lock 사용 중

발생 메시지:

```text
Could not get lock /var/lib/dpkg/lock-frontend
It is held by process unattended-upgr
```

원인:

```text
Ubuntu 자동 업데이트가 패키지 관리자를 사용 중
```

해결:

```text
자동 업데이트가 끝날 때까지 기다린 후 설치를 계속 진행
```

잠금 파일을 강제로 삭제하지 않았다.

---

### 문제 3: `SignatureDoesNotMatch`

원인:

```text
Access Key ID와 Secret Access Key 입력 위치가 잘못됨
```

해결:

```bash
aws configure --profile home-idc-s3-backup
```

프로필을 다시 설정한 뒤 정상적으로 인증됐다.

---

### 문제 4: PowerShell SSH 창에서 붙여넣기 불가

해결:

```text
Ctrl+V 대신 터미널 내부에서 마우스 오른쪽 버튼을 클릭하여 붙여넣기
```

---

## 21. 최종 검증 결과

| 테스트 | 결과 |
|---|---|
| IAM 관리자 사용자 로그인 | 성공 |
| 관리자 사용자 MFA 등록 | 성공 |
| S3 버킷 생성 | 성공 |
| 퍼블릭 액세스 차단 | 적용 |
| 버킷 버전 관리 | 활성화 |
| 기본 암호화 | 적용 |
| S3 수동 업로드 | 성공 |
| AWS CLI v2 설치 | 성공 |
| 전용 IAM 사용자 인증 | 성공 |
| S3 객체 목록 조회 | 성공 |
| AWS CLI 업로드 | 성공 |
| AWS CLI 다운로드 | 성공 |
| SHA-256 무결성 검증 | 일치 |
| 삭제 권한 차단 | `AccessDenied` |
| AWS 자격 증명 파일 권한 | `600` |
| AWS 디렉터리 권한 | `700` |

---

## 22. 이번 실습에서 익힌 내용

- AWS 루트 사용자와 IAM 사용자의 역할 차이
- IAM 사용자, 그룹 및 정책 구성
- 패스키 기반 MFA 설정
- 최소 권한 원칙
- S3 버킷 생성 및 보안 설정
- S3 버전 관리와 서버 측 암호화
- AWS CLI v2 설치 및 프로필 관리
- AWS CLI를 이용한 객체 업로드와 다운로드
- SHA-256을 이용한 백업 무결성 검증
- Linux 파일 및 디렉터리 권한 관리
- 의도적인 `AccessDenied` 테스트를 통한 권한 검증
- 시스템 시간 오류와 패키지 잠금 문제 해결

---

## 23. Day 12 완료 결과

로컬 Ubuntu 서버에서 생성된 Nginx 백업 파일을 AWS S3에 안전하게 보관하고 다시 복구할 수 있는 환경을 구축했다.

관리자 자격 증명을 서버에 저장하지 않고, S3 백업에 필요한 권한만 가진 별도의 IAM 사용자를 사용했다.

또한 업로드, 조회, 다운로드는 허용하면서 삭제는 차단하여 최소 권한 원칙이 실제로 적용되는 것을 검증했다.

다음 단계에서는 현재의 수동 AWS CLI 업로드 작업을 백업 스크립트 및 Cron과 연결하여 S3 자동 업로드 환경을 구성할 예정이다.



# Day 11 - Nginx 웹 콘텐츠 백업 및 복원 자동화

## 1. 실습 목표

- Nginx 웹 콘텐츠를 `tar.gz` 파일로 압축 백업
- 백업 파일에 날짜와 시간 추가
- 압축 파일 내부 내용 확인
- SHA-256 체크섬 생성 및 무결성 검증
- 웹 콘텐츠 유실 상황 재현
- 백업 파일을 이용한 복원
- 복원된 파일과 원본 파일 비교
- Bash 백업 스크립트 작성
- 오래된 백업 파일 자동 삭제
- Cron을 이용한 매일 자동 백업
- 백업 스크립트와 Cron 설정을 GitHub에 업로드

---

## 2. 백업 대상 확인

Docker Nginx에서 사용하는 웹 콘텐츠 디렉터리를 확인했다.

```bash
ls -l /home/sungwoo/docker-nginx/html
```

출력:

```text
total 4
-rw-rw-r-- 1 sungwoo sungwoo 35 Jul 20 03:46 index.html
```

백업 대상 파일:

```text
/home/sungwoo/docker-nginx/html/index.html
```

이 디렉터리는 Docker 컨테이너에 다음 위치로 바인드 마운트되어 있다.

```text
Ubuntu 호스트
/home/sungwoo/docker-nginx/html
        ↓
Docker bind mount
        ↓
Nginx 컨테이너
/usr/share/nginx/html
```

---

## 3. 백업 디렉터리 생성

백업 파일을 저장할 디렉터리를 생성했다.

```bash
mkdir -p /home/sungwoo/home-idc-lab/backups
```

백업 저장 경로:

```text
/home/sungwoo/home-idc-lab/backups
```

---

## 4. 웹 콘텐츠 수동 백업

`tar` 명령을 사용해 Nginx 웹 콘텐츠를 `tar.gz` 형식으로 압축했다.

```bash
tar -czf /home/sungwoo/home-idc-lab/backups/nginx-html-$(date +%Y%m%d-%H%M%S).tar.gz \
  -C /home/sungwoo/docker-nginx html
```

생성된 백업 파일:

```text
nginx-html-20260720-154312.tar.gz
```

파일명에 날짜와 시간이 포함되어 여러 백업을 구분할 수 있다.

```text
nginx-html-YYYYMMDD-HHMMSS.tar.gz
```

---

## 5. tar 명령어 옵션

사용한 명령:

```bash
tar -czf 백업파일.tar.gz -C 상위경로 html
```

옵션 의미:

| 옵션 | 의미 |
|---|---|
| `-c` | 새로운 압축 파일 생성 |
| `-z` | gzip 방식으로 압축 |
| `-f` | 생성할 파일 이름 지정 |
| `-C` | 지정한 디렉터리로 이동한 후 작업 |

절대경로 전체를 저장하지 않고 다음과 같은 구조로 압축했다.

```text
html/
└── index.html
```

---

## 6. 백업 파일 생성 확인

```bash
ls -lh /home/sungwoo/home-idc-lab/backups
```

출력:

```text
-rw-rw-r-- 1 sungwoo sungwoo 191 Jul 20 15:43 nginx-html-20260720-154312.tar.gz
```

백업 파일이 정상적으로 생성된 것을 확인했다.

---

## 7. 압축 파일 내부 확인

압축을 해제하지 않고 백업 파일의 내부 목록을 확인했다.

```bash
tar -tzf /home/sungwoo/home-idc-lab/backups/nginx-html-20260720-154312.tar.gz
```

출력:

```text
html/
html/index.html
```

백업 파일 내부에 웹 콘텐츠가 정상적으로 포함된 것을 확인했다.

---

## 8. SHA-256 체크섬 생성

백업 파일의 손상 여부를 확인하기 위해 SHA-256 체크섬 파일을 생성했다.

```bash
cd /home/sungwoo/home-idc-lab/backups
```

```bash
sha256sum nginx-html-20260720-154312.tar.gz \
  > nginx-html-20260720-154312.tar.gz.sha256
```

생성된 파일:

```text
nginx-html-20260720-154312.tar.gz
nginx-html-20260720-154312.tar.gz.sha256
```

체크섬은 파일 내용으로 계산한 고유한 해시값이다.

파일 내용이 조금이라도 변경되거나 손상되면 체크섬 검증에 실패한다.

---

## 9. 백업 파일 무결성 검증

다음 명령으로 백업 파일과 체크섬을 비교했다.

```bash
sha256sum -c nginx-html-20260720-154312.tar.gz.sha256
```

출력:

```text
nginx-html-20260720-154312.tar.gz: OK
```

`OK`가 출력되어 백업 파일이 손상되지 않았음을 확인했다.

---

## 10. 웹 콘텐츠 유실 상황 재현

복원 테스트를 위해 `index.html` 파일을 삭제하지 않고 이름을 변경했다.

```bash
mv /home/sungwoo/docker-nginx/html/index.html \
   /home/sungwoo/docker-nginx/html/index.html.lost
```

원본 파일을 완전히 삭제하지 않고 이름만 변경해 안전하게 장애 상황을 만들었다.

---

## 11. 웹서비스 장애 확인

HTTP 응답 상태를 확인했다.

```bash
curl -I http://127.0.0.1:8080
```

출력:

```text
HTTP/1.1 403 Forbidden
Server: nginx/1.31.3
```

Nginx 컨테이너는 실행 중이지만 기본 웹파일인 `index.html`을 찾을 수 없어 `403 Forbidden`이 발생했다.

이를 통해 다음 두 상태가 다를 수 있음을 확인했다.

```text
Nginx 프로세스 실행 상태: 정상
웹 콘텐츠 제공 상태: 장애
```

---

## 12. 백업 파일을 이용한 복원

생성해 둔 `tar.gz` 백업을 원래 웹 콘텐츠 경로에 복원했다.

```bash
tar -xzf /home/sungwoo/home-idc-lab/backups/nginx-html-20260720-154312.tar.gz \
  -C /home/sungwoo/docker-nginx
```

압축 파일 내부의 `html/index.html`이 다음 위치로 복원됐다.

```text
/home/sungwoo/docker-nginx/html/index.html
```

---

## 13. 복원 후 HTTP 확인

복원 후 웹서비스 상태를 다시 확인했다.

```bash
curl -I http://127.0.0.1:8080
```

출력:

```text
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 35
```

`403 Forbidden`에서 `200 OK`로 변경되어 웹서비스가 정상 복구된 것을 확인했다.

---

## 14. 복원 파일과 원본 비교

복원된 `index.html`과 이름을 변경해 보관한 원본 파일을 비교했다.

```bash
cmp -s \
  /home/sungwoo/docker-nginx/html/index.html \
  /home/sungwoo/docker-nginx/html/index.html.lost \
  && echo MATCH || echo DIFFERENT
```

출력:

```text
MATCH
```

복원된 파일이 유실 전 원본과 완전히 동일함을 확인했다.

---

## 15. 테스트 파일 정리

복원이 정상적으로 완료됐으므로 테스트용 원본 파일을 삭제했다.

```bash
rm /home/sungwoo/docker-nginx/html/index.html.lost
```

최종 웹 콘텐츠:

```text
/home/sungwoo/docker-nginx/html/index.html
```

---

## 16. 자동 백업 스크립트 작성

수동으로 수행한 백업 과정을 자동화하기 위해 다음 스크립트를 작성했다.

파일 위치:

```text
/home/sungwoo/home-idc-lab/scripts/backup-nginx.sh
```

스크립트 내용:

```bash
#!/bin/bash

set -euo pipefail

SOURCE_DIR="/home/sungwoo/docker-nginx/html"
BACKUP_DIR="/home/sungwoo/home-idc-lab/backups"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_FILE="$BACKUP_DIR/nginx-html-$TIMESTAMP.tar.gz"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "FAIL: Source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"

tar -czf "$BACKUP_FILE" \
  -C "$(dirname "$SOURCE_DIR")" \
  "$(basename "$SOURCE_DIR")"

cd "$BACKUP_DIR"

sha256sum "$(basename "$BACKUP_FILE")" \
  > "$(basename "$BACKUP_FILE").sha256"

find "$BACKUP_DIR" -maxdepth 1 -type f \
  \( -name 'nginx-html-*.tar.gz' -o -name 'nginx-html-*.tar.gz.sha256' \) \
  -mtime +7 -delete

echo "Backup completed: $BACKUP_FILE"
```

---

## 17. 안전한 Bash 실행 옵션

스크립트에 다음 설정을 추가했다.

```bash
set -euo pipefail
```

각 옵션의 의미:

| 옵션 | 의미 |
|---|---|
| `-e` | 명령어가 실패하면 스크립트 종료 |
| `-u` | 정의되지 않은 변수를 사용하면 오류 |
| `pipefail` | 파이프라인 중 하나라도 실패하면 전체 실패 |

오류가 발생한 상태에서 백업 작업이 계속 진행되는 것을 방지한다.

---

## 18. 백업 대상 디렉터리 검사

백업 전에 원본 디렉터리가 존재하는지 확인한다.

```bash
if [ ! -d "$SOURCE_DIR" ]; then
  echo "FAIL: Source directory not found: $SOURCE_DIR" >&2
  exit 1
fi
```

디렉터리가 존재하지 않으면 오류 메시지를 출력하고 종료 코드 `1`로 중단한다.

---

## 19. 날짜 기반 백업 파일명

현재 날짜와 시간을 변수에 저장했다.

```bash
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
```

백업 파일 경로:

```bash
BACKUP_FILE="$BACKUP_DIR/nginx-html-$TIMESTAMP.tar.gz"
```

실행할 때마다 서로 다른 이름의 백업 파일이 생성된다.

예시:

```text
nginx-html-20260720-155137.tar.gz
nginx-html-20260720-155424.tar.gz
nginx-html-20260720-155519.tar.gz
```

---

## 20. 자동 체크섬 생성

압축 백업 후 동일한 이름의 SHA-256 파일을 자동 생성한다.

```bash
sha256sum "$(basename "$BACKUP_FILE")" \
  > "$(basename "$BACKUP_FILE").sha256"
```

생성 예시:

```text
nginx-html-20260720-155137.tar.gz
nginx-html-20260720-155137.tar.gz.sha256
```

백업 데이터와 검증 정보를 한 쌍으로 관리할 수 있다.

---

## 21. 오래된 백업 자동 삭제

백업 파일이 계속 누적되어 디스크를 가득 채우지 않도록 오래된 파일을 자동 삭제한다.

```bash
find "$BACKUP_DIR" -maxdepth 1 -type f \
  \( -name 'nginx-html-*.tar.gz' -o -name 'nginx-html-*.tar.gz.sha256' \) \
  -mtime +7 -delete
```

삭제 대상:

```text
nginx-html-*.tar.gz
nginx-html-*.tar.gz.sha256
```

설정된 보관 기간보다 오래된 압축 파일과 체크섬 파일을 함께 삭제한다.

---

## 22. 실행 권한 부여

Windows PowerShell을 통해 스크립트를 작성했기 때문에 Linux 줄바꿈 형식으로 정리했다.

```bash
sed -i 's/\r$//' /home/sungwoo/home-idc-lab/scripts/backup-nginx.sh
```

실행 권한을 부여했다.

```bash
chmod +x /home/sungwoo/home-idc-lab/scripts/backup-nginx.sh
```

---

## 23. 자동 백업 스크립트 실행

작성한 스크립트를 직접 실행했다.

```bash
/home/sungwoo/home-idc-lab/scripts/backup-nginx.sh
```

출력:

```text
Backup completed: /home/sungwoo/home-idc-lab/backups/nginx-html-20260720-155137.tar.gz
```

새 압축 백업과 체크섬 파일이 자동 생성됐다.

---

## 24. 자동 생성 결과 확인

```bash
ls -lh /home/sungwoo/home-idc-lab/backups
```

출력 예시:

```text
nginx-html-20260720-154312.tar.gz
nginx-html-20260720-154312.tar.gz.sha256
nginx-html-20260720-155137.tar.gz
nginx-html-20260720-155137.tar.gz.sha256
```

백업 파일과 체크섬 파일이 각각 생성된 것을 확인했다.

---

## 25. 자동 생성 백업 무결성 검증

```bash
cd /home/sungwoo/home-idc-lab/backups
```

```bash
sha256sum -c nginx-html-20260720-155137.tar.gz.sha256
```

출력:

```text
nginx-html-20260720-155137.tar.gz: OK
```

자동 백업 스크립트가 생성한 파일도 정상임을 확인했다.

---

## 26. 오래된 백업 삭제 테스트

실제 파일을 기다리지 않고 8일 전 파일처럼 보이는 테스트 파일을 생성했다.

```bash
touch \
  /home/sungwoo/home-idc-lab/backups/nginx-html-old-test.tar.gz \
  /home/sungwoo/home-idc-lab/backups/nginx-html-old-test.tar.gz.sha256
```

수정 시각을 8일 전으로 변경했다.

```bash
touch -d '8 days ago' \
  /home/sungwoo/home-idc-lab/backups/nginx-html-old-test.tar.gz \
  /home/sungwoo/home-idc-lab/backups/nginx-html-old-test.tar.gz.sha256
```

백업 스크립트를 다시 실행했다.

```bash
/home/sungwoo/home-idc-lab/scripts/backup-nginx.sh
```

삭제 여부를 확인했다.

```bash
ls -l /home/sungwoo/home-idc-lab/backups/nginx-html-old-test* \
  2>/dev/null || echo OLD_BACKUP_REMOVED
```

출력:

```text
OLD_BACKUP_REMOVED
```

오래된 압축 파일과 체크섬 파일이 자동 삭제되는 것을 확인했다.

---

## 27. 매일 자동 백업 Cron 등록

백업 스크립트를 매일 새벽 2시에 실행하도록 Crontab에 등록했다.

```cron
0 2 * * * /home/sungwoo/home-idc-lab/scripts/backup-nginx.sh >> /home/sungwoo/home-idc-lab/logs/backup.log 2>&1
```

시간 설정 의미:

```text
0 2 * * *
│ │ │ │ │
│ │ │ │ └─ 모든 요일
│ │ │ └─── 모든 월
│ │ └───── 매일
│ └─────── 오전 2시
└───────── 0분
```

즉, 매일 오전 2시 정각에 백업을 실행한다.

---

## 28. 최종 Crontab 확인

```bash
crontab -l
```

출력:

```cron
*/5 * * * * /home/sungwoo/home-idc-lab/scripts/health-check.sh >> /home/sungwoo/home-idc-lab/logs/cron-health-check.log 2>&1
0 2 * * * /home/sungwoo/home-idc-lab/scripts/backup-nginx.sh >> /home/sungwoo/home-idc-lab/logs/backup.log 2>&1
```

최종 자동화 구성:

```text
5분마다
└── 서버 상태 점검

매일 오전 2시
└── Nginx 웹 콘텐츠 백업
```

---

## 29. Cron 설정 파일 저장

현재 Crontab 전체를 프로젝트 파일로 저장했다.

```bash
crontab -l > /home/sungwoo/home-idc-lab/cron/home-idc.cron
```

저장 경로:

```text
/home/sungwoo/home-idc-lab/cron/home-idc.cron
```

파일 내용:

```cron
*/5 * * * * /home/sungwoo/home-idc-lab/scripts/health-check.sh >> /home/sungwoo/home-idc-lab/logs/cron-health-check.log 2>&1
0 2 * * * /home/sungwoo/home-idc-lab/scripts/backup-nginx.sh >> /home/sungwoo/home-idc-lab/logs/backup.log 2>&1
```

---

## 30. Windows로 프로젝트 파일 복사

백업 스크립트를 Windows로 복사했다.

```powershell
scp -P 2222 sungwoo@127.0.0.1:/home/sungwoo/home-idc-lab/scripts/backup-nginx.sh .\scripts\backup-nginx.sh
```

Cron 설정 파일도 복사했다.

```powershell
scp -P 2222 sungwoo@127.0.0.1:/home/sungwoo/home-idc-lab/cron/home-idc.cron .\cron\home-idc.cron
```

---

## 31. GitHub 업로드

GitHub 저장소에 다음 파일을 추가했다.

```text
scripts/backup-nginx.sh
cron/home-idc.cron
```

최종 저장소 구조:

```text
hhome-idc-lab/
├── README.md
├── compose.yaml
├── scripts/
│   ├── health-check.sh
│   └── backup-nginx.sh
└── cron/
    ├── health-check.cron
    └── home-idc.cron
```

파일 업로드 커밋 메시지:

```text
feat: add automated Nginx backup and cron schedule
```

> 실제 `backups` 디렉터리의 `tar.gz` 파일과 운영 로그는 GitHub에 업로드하지 않는다. 저장소에는 백업을 재현할 수 있는 스크립트와 설정 파일만 관리한다.

---

## 32. 장애 및 문제 해결 기록

### 문제 1: 웹 콘텐츠 유실 시 컨테이너는 실행 중

`index.html`을 이동한 후에도 Nginx 컨테이너 자체는 실행 중이었다.

하지만 HTTP 요청 결과는 다음과 같았다.

```text
HTTP/1.1 403 Forbidden
```

따라서 프로세스 상태뿐 아니라 실제 HTTP 응답도 함께 확인해야 한다.

---

### 문제 2: 백업 파일 존재만으로는 정상 여부를 알 수 없음

압축 파일이 생성되었더라도 파일이 손상됐을 가능성이 있다.

해결:

```bash
sha256sum
sha256sum -c
```

를 이용해 백업 파일의 무결성을 검증했다.

---

### 문제 3: 복원 성공 여부 검증 필요

파일이 다시 생성된 것만으로는 원본과 동일하다고 판단할 수 없다.

해결:

```bash
cmp -s 복원파일 원본파일
```

을 사용해 파일 내용을 비교했고 `MATCH` 결과를 확인했다.

---

### 문제 4: 백업 파일 무한 누적

정기 백업을 수행하면 디스크 공간이 계속 감소할 수 있다.

해결:

```bash
find ... -mtime +7 -delete
```

를 사용해 보관 기간을 초과한 백업과 체크섬 파일을 자동 정리했다.

---

### 문제 5: 수동 백업은 실행을 잊을 수 있음

운영자가 매일 직접 실행하면 누락될 가능성이 있다.

해결:

```cron
0 2 * * *
```

Cron 설정을 사용해 매일 새벽 2시에 자동 실행되도록 구성했다.

---

## 33. 오늘 배운 내용

- `tar -czf`로 디렉터리를 gzip 압축 백업할 수 있다.
- `tar -tzf`로 압축 파일의 내부 목록을 확인할 수 있다.
- `tar -xzf`로 압축 파일을 복원할 수 있다.
- 날짜와 시간을 파일명에 포함하면 백업 이력을 구분할 수 있다.
- SHA-256 체크섬으로 파일의 손상 여부를 검증할 수 있다.
- 서비스 프로세스가 실행 중이어도 콘텐츠 문제로 장애가 발생할 수 있다.
- HTTP 상태 코드로 실제 서비스 상태를 확인해야 한다.
- `cmp` 명령으로 복원된 파일과 원본을 비교할 수 있다.
- Bash 스크립트로 백업, 검증 파일 생성, 정리 작업을 자동화할 수 있다.
- `set -euo pipefail`로 스크립트 실행 안정성을 높일 수 있다.
- `find -mtime`을 이용해 오래된 백업을 자동 삭제할 수 있다.
- Cron을 이용해 매일 정해진 시간에 자동 백업할 수 있다.
- 실제 백업 데이터보다 재현 가능한 스크립트와 설정을 GitHub에 저장하는 것이 좋다.

---

## 34. Day 11 결과

- Nginx 웹 콘텐츠 압축 백업 완료
- 날짜 기반 백업 파일 생성 완료
- 압축 내부 파일 확인 완료
- SHA-256 체크섬 생성 및 검증 완료
- `index.html` 유실 장애 재현 완료
- HTTP `403 Forbidden` 확인
- 백업 파일을 이용한 복원 완료
- HTTP `200 OK` 복구 확인
- 복원 파일과 원본 파일 비교 완료
- Bash 자동 백업 스크립트 작성 완료
- 오래된 백업 자동 삭제 기능 구현
- 8일 전 테스트 파일 자동 삭제 확인
- 매일 오전 2시 백업 Cron 등록
- `scripts/backup-nginx.sh` GitHub 업로드
- `cron/home-idc.cron` GitHub 업로드

---

## 35. 다음 실습 계획

- AWS 계정 보안 설정
- IAM 사용자 및 최소 권한 구성
- AWS CLI 설치 및 인증
- S3 백업 버킷 생성
- 로컬 백업 파일을 S3에 업로드
- S3 버전 관리 설정
- 백업 파일 다운로드 및 복구
- AWS 비용 알림과 예산 설정

---



# Day 10 - Cron을 이용한 서버 상태 점검 자동화

## 1. 실습 목표

- Linux Cron 서비스 상태 확인
- 사용자 Crontab 확인
- Bash 상태 점검 스크립트 자동 실행
- 점검 결과를 로그 파일에 누적 저장
- 1분 주기로 자동 실행 테스트
- 컨테이너 장애 자동 감지 확인
- 서비스 복구 상태 자동 기록 확인
- 최종 실행 주기를 5분으로 변경
- 시스템 로그에서 Cron 실행 이력 확인
- Cron 설정 파일을 GitHub에 업로드

---

## 2. Cron이란?

Cron은 Linux에서 명령어나 스크립트를 정해진 시간마다 자동으로 실행하는 작업 스케줄러다.

서버 관리자는 Cron을 이용해 다음과 같은 작업을 자동화할 수 있다.

- 서버 상태 점검
- 로그 파일 정리
- 데이터 백업
- 임시 파일 삭제
- 서비스 상태 확인
- 정기 보고서 생성
- 클라우드 스토리지 업로드

이번 실습에서는 Day 9에서 작성한 상태 점검 스크립트를 Cron에 등록해 자동 실행되도록 구성했다.

자동 실행 대상 스크립트:

```text
/home/sungwoo/home-idc-lab/scripts/health-check.sh
```

로그 저장 위치:

```text
/home/sungwoo/home-idc-lab/logs/cron-health-check.log
```

---

## 3. Cron 서비스 상태 확인

다음 명령으로 Cron 서비스가 실행 중인지 확인했다.

```bash
systemctl is-active cron
```

출력 결과:

```text
active
```

`active`는 Cron 서비스가 현재 정상 실행 중이라는 뜻이다.

Cron 서비스가 중지되어 있으면 Crontab에 작업을 등록해도 자동으로 실행되지 않는다.

---

## 4. 기존 Crontab 확인

현재 사용자에게 등록된 Cron 작업을 확인했다.

```bash
crontab -l
```

기존 작업이 없을 경우 다음과 같은 메시지가 발생할 수 있기 때문에, 오류 출력을 숨기고 별도 문구를 표시했다.

```bash
crontab -l 2>/dev/null || echo NO_CRON_JOBS
```

출력 결과:

```text
NO_CRON_JOBS
```

아직 `sungwoo` 사용자에게 등록된 Cron 작업이 없다는 것을 확인했다.

---

## 5. 1분 주기 테스트 작업 등록

자동 실행 여부를 빠르게 확인하기 위해 처음에는 상태 점검 스크립트를 1분마다 실행하도록 등록했다.

```bash
(crontab -l 2>/dev/null; echo '* * * * * /home/sungwoo/home-idc-lab/scripts/health-check.sh >> /home/sungwoo/home-idc-lab/logs/cron-health-check.log 2>&1') | crontab -
```

등록된 작업:

```cron
* * * * * /home/sungwoo/home-idc-lab/scripts/health-check.sh >> /home/sungwoo/home-idc-lab/logs/cron-health-check.log 2>&1
```

---

## 6. Crontab 시간 형식

Crontab의 기본 형식은 다음과 같다.

```text
분 시 일 월 요일 실행할 명령어
```

각 필드의 의미:

```text
* * * * *
│ │ │ │ │
│ │ │ │ └─ 요일: 0~7, 일요일은 0 또는 7
│ │ │ └─── 월: 1~12
│ │ └───── 일: 1~31
│ └─────── 시: 0~23
└───────── 분: 0~59
```

이번 테스트 설정:

```cron
* * * * *
```

모든 항목에 `*`가 사용되었기 때문에 매분 실행된다.

---

## 7. 로그 저장 설정

Cron 작업 뒤에 다음 리다이렉션을 추가했다.

```bash
>> /home/sungwoo/home-idc-lab/logs/cron-health-check.log 2>&1
```

각 기호의 의미:

### `>>`

명령어의 표준 출력을 파일 마지막에 추가한다.

기존 로그를 덮어쓰지 않고 계속 누적한다.

### `2>&1`

표준 오류를 표준 출력과 같은 위치에 저장한다.

따라서 다음 내용이 모두 하나의 로그 파일에 기록된다.

- 정상 출력
- Docker 상태
- HTTP 상태
- curl 오류
- 장애 메시지

---

## 8. 등록된 Crontab 확인

다음 명령으로 등록된 작업을 확인했다.

```bash
crontab -l
```

출력:

```cron
* * * * * /home/sungwoo/home-idc-lab/scripts/health-check.sh >> /home/sungwoo/home-idc-lab/logs/cron-health-check.log 2>&1
```

Crontab이 정상적으로 등록된 것을 확인했다.

---

## 9. Cron 자동 실행 로그 확인

Cron이 자동으로 생성한 로그의 마지막 부분을 확인했다.

```bash
tail -n 30 /home/sungwoo/home-idc-lab/logs/cron-health-check.log
```

출력 예시:

```text
===== Home IDC Health Check =====
Time: 2026-07-20 14:41:01

[CPU / UPTIME]
14:41:01 up 14:16, 1 user, load average: 0.05, 0.02, 0.00

[MEMORY]
Mem: 3.3Gi 588Mi 980Mi

[DISK]
/dev/mapper/ubuntu--vg-ubuntu--lv 12G 5.5G 5.2G 52% /

[DOCKER]
OK: Docker service is running
OK: home-idc-nginx is running

[HTTP]
OK: http://127.0.0.1:8080 responded

Exit code: 0
```

직접 스크립트를 실행하지 않아도 Cron이 매분 자동으로 점검 결과를 기록하는 것을 확인했다.

---

## 10. 장애 상황 생성

Cron이 장애도 자동으로 감지하는지 테스트하기 위해 Nginx 컨테이너를 중지했다.

```bash
docker stop home-idc-nginx
```

출력:

```text
home-idc-nginx
```

Docker 서비스 자체는 실행 중이지만 Nginx 컨테이너만 중지된 상태를 만들었다.

---

## 11. Cron 장애 자동 감지 확인

약 1분 후 Cron 로그를 다시 확인했다.

```bash
tail -n 25 /home/sungwoo/home-idc-lab/logs/cron-health-check.log
```

장애 상태가 다음과 같이 기록되었다.

```text
===== Home IDC Health Check =====
Time: 2026-07-20 14:43:01

[DOCKER]
OK: Docker service is running
FAIL: home-idc-nginx is not running

[HTTP]
curl: (7) Failed to connect to 127.0.0.1 port 8080
FAIL: http://127.0.0.1:8080 did not respond

Exit code: 1
```

Cron이 자동으로 다음 장애를 감지했다.

- Docker 서비스는 실행 중
- Nginx 컨테이너는 중지 상태
- HTTP 8080 포트 응답 실패
- 종료 코드 1 반환
- 오류 내용까지 로그에 저장

---

## 12. Nginx 서비스 복구

Docker Compose를 이용해 중지된 Nginx 서비스를 다시 시작했다.

```bash
cd /home/sungwoo/docker-nginx
docker compose start nginx
```

출력:

```text
Container home-idc-nginx Starting
Container home-idc-nginx Started
```

---

## 13. 복구 상태 자동 기록 확인

약 1분 후 Cron 로그를 다시 확인했다.

```bash
tail -n 25 /home/sungwoo/home-idc-lab/logs/cron-health-check.log
```

복구 후 결과:

```text
===== Home IDC Health Check =====
Time: 2026-07-20 14:45:01

[DOCKER]
OK: Docker service is running
OK: home-idc-nginx is running

[HTTP]
OK: http://127.0.0.1:8080 responded

Exit code: 0
```

장애 발생 후 서비스를 복구하자 Cron이 다음 실행 시점에 정상 상태를 자동으로 기록했다.

전체 흐름:

```text
정상 상태
    ↓
Cron 자동 점검: Exit code 0
    ↓
Nginx 컨테이너 중지
    ↓
Cron 자동 점검: Exit code 1
    ↓
Docker Compose로 복구
    ↓
Cron 자동 점검: Exit code 0
```

---

## 14. 최종 실행 주기를 5분으로 변경

1분 주기는 테스트에는 편리하지만 로그가 너무 빠르게 증가할 수 있다.

기존 상태 점검 Cron 줄을 제거하고 5분 주기로 다시 등록했다.

```bash
(crontab -l 2>/dev/null | grep -v 'health-check.sh'; echo '*/5 * * * * /home/sungwoo/home-idc-lab/scripts/health-check.sh >> /home/sungwoo/home-idc-lab/logs/cron-health-check.log 2>&1') | crontab -
```

최종 설정:

```cron
*/5 * * * * /home/sungwoo/home-idc-lab/scripts/health-check.sh >> /home/sungwoo/home-idc-lab/logs/cron-health-check.log 2>&1
```

`*/5`는 5분 간격으로 실행한다는 뜻이다.

실행 시각 예시:

```text
14:00
14:05
14:10
14:15
14:20
```

---

## 15. 최종 Crontab 확인

다음 명령으로 최종 설정을 확인했다.

```bash
crontab -l
```

출력:

```cron
*/5 * * * * /home/sungwoo/home-idc-lab/scripts/health-check.sh >> /home/sungwoo/home-idc-lab/logs/cron-health-check.log 2>&1
```

상태 점검 스크립트가 5분마다 자동 실행되도록 최종 설정되었다.

---

## 16. 시스템 로그에서 Cron 실행 이력 확인

Cron 작업이 실제 실행되었는지 운영체제의 시스템 로그에서도 확인했다.

```bash
grep CRON /var/log/syslog | tail -n 10
```

상태 점검 스크립트 관련 기록만 확인할 때는 다음 명령을 사용했다.

```bash
grep 'health-check.sh' /var/log/syslog | tail -n 5
```

1분 주기 테스트 실행 기록:

```text
2026-07-20T14:43:01+00:00 home-idc-ubuntu CRON: (sungwoo) CMD (/home/sungwoo/home-idc-lab/scripts/health-check.sh ...)
2026-07-20T14:44:01+00:00 home-idc-ubuntu CRON: (sungwoo) CMD (/home/sungwoo/home-idc-lab/scripts/health-check.sh ...)
2026-07-20T14:45:01+00:00 home-idc-ubuntu CRON: (sungwoo) CMD (/home/sungwoo/home-idc-lab/scripts/health-check.sh ...)
2026-07-20T14:46:01+00:00 home-idc-ubuntu CRON: (sungwoo) CMD (/home/sungwoo/home-idc-lab/scripts/health-check.sh ...)
```

5분 주기로 변경한 후 실행 기록:

```text
2026-07-20T14:50:01+00:00 home-idc-ubuntu CRON: (sungwoo) CMD (/home/sungwoo/home-idc-lab/scripts/health-check.sh ...)
```

최신 실행 시간이 `14:50:01`로 기록되어 5분 주기 설정이 실제 적용된 것을 확인했다.

---

## 17. Crontab 로그와 애플리케이션 로그의 차이

이번 실습에서는 두 종류의 로그를 확인했다.

### 시스템 Cron 로그

```text
/var/log/syslog
```

Cron이 어떤 명령을 언제 실행했는지 확인할 수 있다.

예시:

```text
CRON: (sungwoo) CMD (/home/sungwoo/home-idc-lab/scripts/health-check.sh ...)
```

### 상태 점검 결과 로그

```text
/home/sungwoo/home-idc-lab/logs/cron-health-check.log
```

실제 점검 결과를 확인할 수 있다.

예시:

```text
OK: Docker service is running
FAIL: home-idc-nginx is not running
Exit code: 1
```

두 로그를 함께 확인하면 다음을 구분할 수 있다.

```text
Cron이 명령을 실행했는가?
        ↓
/var/log/syslog 확인

실행된 점검 결과는 무엇인가?
        ↓
cron-health-check.log 확인
```

---

## 18. Cron 설정 파일 저장

현재 사용자에게 등록된 Crontab을 프로젝트 파일로 저장했다.

```bash
mkdir -p /home/sungwoo/home-idc-lab/cron
```

```bash
crontab -l > /home/sungwoo/home-idc-lab/cron/health-check.cron
```

저장된 파일 위치:

```text
/home/sungwoo/home-idc-lab/cron/health-check.cron
```

파일 내용:

```cron
*/5 * * * * /home/sungwoo/home-idc-lab/scripts/health-check.sh >> /home/sungwoo/home-idc-lab/logs/cron-health-check.log 2>&1
```

Crontab은 사용자 계정 설정에 저장되기 때문에 일반 프로젝트 파일처럼 자동으로 GitHub에 포함되지 않는다.

따라서 현재 설정을 별도 파일로 내보내 저장소에 추가했다.

---

## 19. Windows로 Cron 설정 복사

SCP를 이용해 Ubuntu의 Cron 설정 파일을 Windows로 복사했다.

```powershell
New-Item -ItemType Directory -Path .\cron -Force | Out-Null
scp -P 2222 sungwoo@127.0.0.1:/home/sungwoo/home-idc-lab/cron/health-check.cron .\cron\health-check.cron
```

Windows에서 파일을 확인했다.

```powershell
explorer .\cron
```

확인된 파일:

```text
cron/health-check.cron
```

---

## 20. GitHub 업로드

GitHub 저장소에 다음 구조로 Cron 설정 파일을 업로드했다.

```text
hhome-idc-lab/
├── README.md
├── compose.yaml
├── scripts/
│   └── health-check.sh
└── cron/
    └── health-check.cron
```

커밋 메시지:

```text
feat: add cron health check schedule
```

실제 Cron 설정을 저장소에 포함해 다른 서버에서도 동일한 스케줄을 확인하고 재현할 수 있도록 구성했다.

---

## 21. Cron 설정 복원 방법

저장소를 새로운 Ubuntu 서버에 내려받은 경우 다음 명령으로 Cron 설정을 등록할 수 있다.

```bash
crontab cron/health-check.cron
```

등록 결과 확인:

```bash
crontab -l
```

주의할 점:

- 스크립트 경로가 실제 서버와 일치해야 한다.
- 스크립트에 실행 권한이 있어야 한다.
- 로그 디렉터리가 존재해야 한다.
- Docker 명령을 실행할 권한이 필요하다.
- Cron 서비스가 실행 중이어야 한다.

---

## 22. 오늘 발생한 문제와 해결 과정

### 문제 1: 등록된 Cron 작업이 없음

확인 결과:

```text
NO_CRON_JOBS
```

해결:

- Day 9 상태 점검 스크립트를 Crontab에 새로 등록
- 처음에는 테스트를 위해 매분 실행하도록 구성

---

### 문제 2: 자동 실행 여부를 빠르게 확인해야 함

처음부터 5분 또는 1시간 주기로 설정하면 테스트 시간이 오래 걸린다.

해결:

1. 처음에는 `* * * * *`로 매분 실행
2. 정상 동작 확인
3. 장애 및 복구 자동 기록 확인
4. 최종적으로 `*/5 * * * *`로 변경

---

### 문제 3: 표준 오류가 로그에서 누락될 수 있음

일반 출력만 저장하면 `curl` 오류와 같은 장애 메시지가 누락될 수 있다.

해결:

```bash
2>&1
```

을 추가해 표준 오류도 같은 로그 파일에 저장했다.

---

### 문제 4: Cron이 실행되지 않은 것인지 스크립트가 실패한 것인지 구분 필요

로그 파일에 내용이 없을 경우 두 가지 가능성이 있다.

- Cron이 명령을 실행하지 않음
- Cron은 실행했지만 스크립트 내부에서 오류 발생

해결:

- `/var/log/syslog`에서 Cron 실행 여부 확인
- `cron-health-check.log`에서 스크립트 결과 확인

---

## 23. 오늘 배운 내용

- Cron은 Linux의 정기 작업 자동화 도구다.
- `systemctl is-active cron`으로 Cron 서비스 상태를 확인할 수 있다.
- `crontab -l`로 현재 사용자의 작업을 확인할 수 있다.
- `* * * * *`는 매분 실행을 의미한다.
- `*/5 * * * *`는 5분마다 실행을 의미한다.
- `>>`는 기존 파일에 출력을 누적 저장한다.
- `2>&1`은 오류 출력도 같은 로그 파일에 저장한다.
- Cron은 사용자가 로그인하지 않아도 작업을 실행할 수 있다.
- 장애 상태와 복구 상태를 모두 자동으로 기록할 수 있다.
- `/var/log/syslog`에서 Cron 실행 이력을 확인할 수 있다.
- Crontab 설정을 파일로 내보내 GitHub에서 관리할 수 있다.
- 자동화는 정상 상태뿐 아니라 실제 장애 테스트가 필요하다.
- 테스트 주기와 운영 주기를 구분하는 것이 중요하다.

---

## 24. Day 10 결과

- Cron 서비스 정상 상태 확인
- 기존 Crontab 확인
- 상태 점검 스크립트 매분 자동 실행 테스트 완료
- 자동 로그 생성 확인
- 컨테이너 장애 자동 감지 확인
- HTTP 장애 자동 감지 확인
- 오류 메시지 로그 저장 확인
- 서비스 복구 후 정상 상태 자동 기록 확인
- 최종 실행 주기를 5분으로 변경
- 시스템 로그에서 실제 Cron 실행 기록 확인
- `cron/health-check.cron` 파일 생성 완료
- GitHub 업로드 완료

---

## 25. 다음 실습 계획

- 웹 콘텐츠 자동 백업 스크립트 작성
- 날짜가 포함된 백업 파일 생성
- `tar.gz` 압축 백업
- 백업 파일 무결성 확인
- 원본 파일 삭제 후 복원 테스트
- 오래된 백업 자동 삭제
- Cron을 이용한 정기 백업
- AWS S3 백업 연동

---


# Day 9 - Bash 서버 상태 점검 스크립트

## 1. 실습 목표

- Bash 스크립트 작성
- CPU 및 서버 가동 시간 확인
- 메모리와 디스크 사용량 확인
- Docker 서비스 상태 확인
- Nginx 컨테이너 상태 확인
- HTTP 웹서비스 응답 확인
- 정상과 장애 상태를 종료 코드로 구분
- 장애 발생 및 복구 테스트
- 점검 결과를 로그 파일로 저장
- 작성한 스크립트를 GitHub에 업로드

---

## 2. 프로젝트 디렉터리 생성

상태 점검 스크립트를 저장하기 위해 다음 디렉터리를 생성했다.

```bash
mkdir -p ~/home-idc-lab/scripts
```

생성된 경로:

```text
/home/sungwoo/home-idc-lab/scripts
```

최종 파일 위치:

```text
/home/sungwoo/home-idc-lab/scripts/health-check.sh
```

---

## 3. 상태 점검 스크립트 작성

다음 내용으로 `health-check.sh` 파일을 작성했다.

```bash
#!/bin/bash

CONTAINER_NAME="home-idc-nginx"
URL="http://127.0.0.1:8080"
STATUS=0

echo "===== Home IDC Health Check ====="
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo

echo "[CPU / UPTIME]"
uptime
echo

echo "[MEMORY]"
free -h
echo

echo "[DISK]"
df -h /
echo

echo "[DOCKER]"
if systemctl is-active --quiet docker; then
  echo "OK: Docker service is running"
else
  echo "FAIL: Docker service is not running"
  STATUS=1
fi

if docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q true; then
  echo "OK: $CONTAINER_NAME is running"
else
  echo "FAIL: $CONTAINER_NAME is not running"
  STATUS=1
fi

echo
echo "[HTTP]"
if curl -fsS "$URL" >/dev/null; then
  echo "OK: $URL responded"
else
  echo "FAIL: $URL did not respond"
  STATUS=1
fi

echo
echo "Exit code: $STATUS"
exit "$STATUS"
```

---

## 4. PowerShell과 SSH를 이용한 파일 작성

VirtualBox 콘솔에서는 긴 내용을 복사하여 붙여넣기 어려웠다.

따라서 Windows PowerShell에서 SSH를 이용해 Ubuntu 서버에 스크립트 내용을 전송했다.

PowerShell은 Windows에서 사용하는 명령어 터미널이며, `ssh` 명령어를 사용하면 Windows에서 Ubuntu 서버의 명령어를 원격으로 실행할 수 있다.

```text
Windows PowerShell
        ↓ SSH
Ubuntu Server
        ↓
health-check.sh 생성
```

Windows와 Ubuntu 사이의 파일 복사에는 `scp`를 사용했다.

---

## 5. Windows 줄바꿈 문자 제거 및 실행 권한 부여

Windows와 Linux는 텍스트 파일의 줄바꿈 방식이 다를 수 있다.

Windows에서 전송된 파일에 포함될 수 있는 `CR` 문자를 다음 명령어로 제거했다.

```bash
sed -i 's/\r$//' /home/sungwoo/home-idc-lab/scripts/health-check.sh
```

스크립트를 직접 실행할 수 있도록 실행 권한을 부여했다.

```bash
chmod +x /home/sungwoo/home-idc-lab/scripts/health-check.sh
```

### 실행 권한

Linux 파일은 내용이 존재하더라도 실행 권한이 없으면 프로그램처럼 실행할 수 없다.

`chmod +x`는 파일에 실행 권한을 추가한다.

---

## 6. 스크립트 구성

### 점검 대상 변수

```bash
CONTAINER_NAME="home-idc-nginx"
URL="http://127.0.0.1:8080"
STATUS=0
```

- `CONTAINER_NAME`: 확인할 Docker 컨테이너 이름
- `URL`: 확인할 Nginx 웹서비스 주소
- `STATUS`: 전체 점검 결과를 저장하는 변수

처음에는 정상 상태를 의미하는 `0`으로 시작한다.

점검 중 하나라도 문제가 발견되면 다음과 같이 값을 변경한다.

```bash
STATUS=1
```

---

## 7. CPU 및 서버 가동 시간 확인

```bash
uptime
```

`uptime` 명령으로 다음 정보를 확인한다.

- 현재 시각
- 서버가 켜진 후 경과 시간
- 현재 로그인 사용자 수
- 1분, 5분, 15분 평균 부하

예시:

```text
12:03:53 up 11:39, 2 users, load average: 0.00, 0.00, 0.00
```

---

## 8. 메모리 상태 확인

```bash
free -h
```

`free -h` 명령으로 다음 정보를 확인한다.

- 전체 메모리
- 사용 중인 메모리
- 여유 메모리
- 버퍼 및 캐시
- 실제 사용 가능한 메모리
- Swap 사용량

`-h` 옵션은 용량을 사람이 읽기 쉬운 단위로 표시한다.

예시:

```text
Mem:  3.3Gi  592Mi  978Mi  2.0Gi  2.7Gi
Swap: 2.0Gi     0B  2.0Gi
```

---

## 9. 디스크 사용량 확인

```bash
df -h /
```

루트 파일시스템 `/`의 디스크 상태를 확인한다.

확인 항목:

- 전체 용량
- 사용량
- 남은 용량
- 사용률
- 마운트 위치

예시:

```text
Filesystem                         Size  Used Avail Use%
/dev/mapper/ubuntu--vg-ubuntu--lv   12G  5.5G  5.2G  52%
```

---

## 10. Docker 서비스 상태 확인

```bash
systemctl is-active --quiet docker
```

Docker 데몬이 실행 중인지 확인한다.

정상일 경우:

```text
OK: Docker service is running
```

비정상일 경우:

```text
FAIL: Docker service is not running
```

Docker 서비스가 중지되어 있으면 전체 상태 변수에 `1`을 저장한다.

---

## 11. Nginx 컨테이너 상태 확인

다음 명령으로 컨테이너의 실행 상태를 확인한다.

```bash
docker inspect -f '{{.State.Running}}' home-idc-nginx
```

컨테이너가 정상 실행 중이면:

```text
true
```

가 출력된다.

스크립트에서는 `grep -q true`를 이용해 결과를 판별했다.

정상일 경우:

```text
OK: home-idc-nginx is running
```

비정상일 경우:

```text
FAIL: home-idc-nginx is not running
```

---

## 12. HTTP 웹서비스 상태 확인

```bash
curl -fsS http://127.0.0.1:8080
```

Nginx 웹서비스가 실제 HTTP 요청에 응답하는지 확인한다.

### curl 옵션

- `-f`: HTTP 오류 응답을 실패로 처리
- `-s`: 진행 상태를 표시하지 않음
- `-S`: 오류가 발생하면 오류 메시지를 출력

정상일 경우:

```text
OK: http://127.0.0.1:8080 responded
```

비정상일 경우:

```text
FAIL: http://127.0.0.1:8080 did not respond
```

컨테이너 프로세스가 실행 중이더라도 웹서비스가 정상 응답하지 않을 수 있으므로, 컨테이너 상태와 HTTP 상태를 각각 확인하도록 구성했다.

---

## 13. 종료 코드

Linux 명령어와 스크립트는 실행이 끝날 때 종료 코드를 반환한다.

```text
0: 정상
1 이상: 오류 또는 비정상
```

스크립트 마지막 부분:

```bash
echo "Exit code: $STATUS"
exit "$STATUS"
```

모든 점검 항목이 정상이면:

```text
Exit code: 0
```

하나 이상의 장애가 감지되면:

```text
Exit code: 1
```

이 종료 코드는 이후 Cron, 모니터링 프로그램, 자동화 도구에서 성공과 실패를 판단할 때 사용할 수 있다.

---

## 14. 첫 번째 실행 결과

스크립트를 실행했다.

```bash
/home/sungwoo/home-idc-lab/scripts/health-check.sh
```

첫 실행에서는 다음과 같은 결과가 나타났다.

```text
OK: Docker service is running
FAIL: home-idc-nginx is not running
OK: http://127.0.0.1:8080 responded

Exit code: 1
```

HTTP 요청은 정상 응답했지만 컨테이너 상태 확인만 실패했다.

컨테이너가 실제로 중지된 것이 아니라, 현재 사용자가 Docker 소켓에 접근할 권한이 없는 것이 원인이었다.

---

## 15. Docker 권한 문제 확인

현재 사용자가 가입된 그룹을 확인했다.

```bash
groups
```

처음 출력:

```text
sungwoo adm cdrom sudo dip plugdev users lxd
```

출력에 `docker` 그룹이 없었다.

일반 사용자가 `sudo` 없이 Docker 명령을 사용하려면 해당 사용자가 `docker` 그룹에 포함되어 있어야 한다.

---

## 16. 사용자를 Docker 그룹에 추가

다음 명령으로 `sungwoo` 사용자를 Docker 그룹에 추가했다.

```bash
sudo usermod -aG docker sungwoo
```

### 옵션 의미

- `-a`: 기존 그룹을 유지하면서 추가
- `-G`: 보조 그룹 지정
- `docker`: 추가할 그룹
- `sungwoo`: 대상 사용자

SSH에 다시 접속한 후 그룹을 확인했다.

```bash
groups
```

결과:

```text
sungwoo adm cdrom sudo dip plugdev users lxd docker
```

`docker` 그룹이 추가된 것을 확인했다.

> Docker 그룹에 가입한 사용자는 컨테이너와 호스트 시스템에 강한 권한을 가질 수 있으므로, 운영 환경에서는 계정 관리에 주의해야 한다.

---

## 17. 정상 상태 점검

권한 문제를 해결한 후 스크립트를 다시 실행했다.

```bash
/home/sungwoo/home-idc-lab/scripts/health-check.sh
```

결과:

```text
[DOCKER]
OK: Docker service is running
OK: home-idc-nginx is running

[HTTP]
OK: http://127.0.0.1:8080 responded

Exit code: 0
```

Docker 서비스, 컨테이너, HTTP 응답이 모두 정상임을 확인했다.

---

## 18. 장애 상황 생성

상태 점검 스크립트가 실제 장애를 감지하는지 확인하기 위해 Nginx 컨테이너를 중지했다.

```bash
docker stop home-idc-nginx
```

출력:

```text
home-idc-nginx
```

---

## 19. 장애 감지 테스트

컨테이너가 중지된 상태에서 스크립트를 다시 실행했다.

```bash
/home/sungwoo/home-idc-lab/scripts/health-check.sh
```

결과:

```text
[DOCKER]
OK: Docker service is running
FAIL: home-idc-nginx is not running

[HTTP]
curl: (7) Failed to connect to 127.0.0.1 port 8080
FAIL: http://127.0.0.1:8080 did not respond

Exit code: 1
```

점검 결과를 통해 다음 장애를 감지했다.

- Docker 서비스 자체는 정상
- Nginx 컨테이너 중지
- HTTP 포트 8080 접속 실패
- 최종 종료 코드 1 반환

이를 통해 Docker 서비스와 개별 컨테이너 상태는 서로 다를 수 있다는 것을 확인했다.

---

## 20. Nginx 서비스 복구

Docker Compose를 이용해 중지된 Nginx 컨테이너를 다시 시작했다.

```bash
cd /home/sungwoo/docker-nginx
docker compose start nginx
```

출력:

```text
Container home-idc-nginx Starting
Container home-idc-nginx Started
```

---

## 21. 복구 상태 재확인

서비스 복구 후 상태 점검 스크립트를 다시 실행했다.

```bash
/home/sungwoo/home-idc-lab/scripts/health-check.sh
```

결과:

```text
[DOCKER]
OK: Docker service is running
OK: home-idc-nginx is running

[HTTP]
OK: http://127.0.0.1:8080 responded

Exit code: 0
```

장애 발생 후 컨테이너를 복구했고, 상태 점검 결과가 다시 정상으로 변경된 것을 확인했다.

전체 테스트 흐름:

```text
정상 상태
    ↓
컨테이너 중지
    ↓
스크립트가 장애 감지
    ↓
Docker Compose로 서비스 복구
    ↓
스크립트로 정상 상태 재확인
```

---

## 22. 점검 로그 디렉터리 생성

점검 결과를 저장하기 위해 로그 디렉터리를 생성했다.

```bash
mkdir -p /home/sungwoo/home-idc-lab/logs
```

로그 파일 위치:

```text
/home/sungwoo/home-idc-lab/logs/health-check.log
```

---

## 23. 점검 결과 로그 저장

`tee` 명령을 이용해 점검 결과를 화면에 표시하면서 로그 파일에도 저장했다.

```bash
/home/sungwoo/home-idc-lab/scripts/health-check.sh \
  | tee -a /home/sungwoo/home-idc-lab/logs/health-check.log
```

### tee 옵션

- 화면에 명령 결과를 출력
- 같은 결과를 파일에도 저장
- `-a`: 기존 파일을 덮어쓰지 않고 마지막에 추가

저장된 로그를 확인했다.

```bash
cat /home/sungwoo/home-idc-lab/logs/health-check.log
```

결과:

```text
===== Home IDC Health Check =====
Time: 2026-07-20 12:15:48

[DOCKER]
OK: Docker service is running
OK: home-idc-nginx is running

[HTTP]
OK: http://127.0.0.1:8080 responded

Exit code: 0
```

---

## 24. GitHub 업로드

Ubuntu에 저장된 스크립트를 `scp` 명령으로 Windows에 복사했다.

```powershell
scp -P 2222 sungwoo@127.0.0.1:/home/sungwoo/home-idc-lab/scripts/health-check.sh .\health-check.sh
```

Windows에서 `scripts` 디렉터리를 생성하고 파일을 이동했다.

```powershell
New-Item -ItemType Directory -Path .\scripts -Force | Out-Null
Move-Item .\health-check.sh .\scripts\health-check.sh
```

GitHub 저장소에는 다음 구조로 업로드했다.

```text
home-idc-lab/
├── README.md
├── compose.yaml
└── scripts/
    └── health-check.sh
```

커밋 메시지:

```text
feat: add server health check script
```

실제 스크립트 파일을 저장소에 추가하여 README 설명뿐 아니라 실행 가능한 결과물도 확인할 수 있도록 구성했다.

---

## 25. 오늘 발생한 문제와 해결 과정

### 문제 1: VirtualBox 콘솔에서 긴 코드 붙여넣기 어려움

원인:

- VirtualBox Ubuntu 콘솔에서 클립보드 사용이 불편함
- 긴 스크립트를 직접 입력하면 오타가 발생할 가능성이 높음

해결:

- Windows PowerShell 사용
- SSH를 통해 Ubuntu 파일 생성
- SCP를 이용해 Windows와 Ubuntu 사이에서 파일 복사

---

### 문제 2: 컨테이너가 실행 중인데 FAIL로 표시됨

증상:

```text
FAIL: home-idc-nginx is not running
OK: http://127.0.0.1:8080 responded
```

원인:

- `sungwoo` 사용자가 Docker 그룹에 포함되어 있지 않음
- `docker inspect` 명령 실행 권한 부족
- 오류 출력을 숨겼기 때문에 컨테이너 중지로 판단됨

해결:

```bash
sudo usermod -aG docker sungwoo
```

새 SSH 세션에서 Docker 그룹 가입 상태를 확인했다.

```bash
groups
```

---

### 문제 3: 실제 장애 감지 검증 필요

스크립트가 정상 상태만 출력한다고 해서 장애 감지 기능이 검증된 것은 아니다.

해결:

1. Nginx 컨테이너를 직접 중지
2. 컨테이너와 HTTP 상태가 `FAIL`인지 확인
3. 종료 코드가 `1`인지 확인
4. Docker Compose로 컨테이너 복구
5. 다시 모든 항목이 `OK`인지 확인

---

## 26. 오늘 배운 내용

- Bash 스크립트는 여러 서버 점검 명령을 자동화할 수 있다.
- `uptime`으로 서버 부하와 가동 시간을 확인할 수 있다.
- `free -h`로 메모리 상태를 확인할 수 있다.
- `df -h /`로 루트 디스크 사용량을 확인할 수 있다.
- `systemctl is-active`로 서비스 상태를 확인할 수 있다.
- `docker inspect`로 컨테이너의 실제 실행 상태를 확인할 수 있다.
- `curl`로 웹서비스가 실제 HTTP 요청에 응답하는지 확인할 수 있다.
- Linux에서 종료 코드 `0`은 정상, `1`은 실패를 의미한다.
- Docker 서비스가 실행 중이어도 개별 컨테이너는 중지될 수 있다.
- 정상 테스트뿐 아니라 장애 발생과 복구 테스트도 중요하다.
- `tee -a`를 사용하면 출력 결과를 보면서 로그 파일에 추가 저장할 수 있다.
- `chmod +x`로 스크립트 실행 권한을 부여할 수 있다.
- PowerShell, SSH, SCP를 이용해 Windows에서 Ubuntu 서버를 관리할 수 있다.
- Docker 그룹은 편리하지만 강한 권한을 제공하므로 계정 관리가 중요하다.

---

## 27. Day 9 결과

- Bash 상태 점검 스크립트 작성 완료
- CPU 및 서버 가동 시간 점검 완료
- 메모리와 디스크 점검 완료
- Docker 서비스 상태 점검 완료
- Nginx 컨테이너 상태 점검 완료
- HTTP 응답 점검 완료
- 정상 상태에서 종료 코드 0 확인
- 장애 상태에서 종료 코드 1 확인
- Nginx 컨테이너 장애 및 복구 실습 완료
- 점검 결과 로그 저장 완료
- `scripts/health-check.sh` GitHub 업로드 완료

---

## 28. 다음 실습 계획

- Cron을 이용한 상태 점검 자동 실행
- 일정 시간마다 로그 파일 생성
- 로그 파일 크기 및 보관 방법 관리
- 장애 발생 기록 확인
- 웹 콘텐츠 자동 백업
- 백업 파일 압축 및 복원
- AWS S3 백업 연동

---



# Day 8 - Docker Compose를 이용한 Nginx 서비스 관리

## 1. 실습 목표

- Docker Compose의 역할 이해
- Docker Compose V2 설치
- `compose.yaml` 작성
- Compose 설정 문법 검사
- 기존 `docker run` 컨테이너를 Compose 방식으로 전환
- Compose를 이용한 서비스 시작 및 종료
- 컨테이너 상태와 로그 확인
- 컨테이너를 재생성해도 웹 데이터가 유지되는지 확인

---

## 2. Docker Compose란?

Docker Compose는 Docker 컨테이너의 실행 설정을 YAML 파일로 관리하는 도구다.

기존에는 Nginx 컨테이너를 실행하기 위해 다음과 같이 긴 명령어를 입력했다.

```bash
sudo docker run -d \
  --name home-idc-nginx \
  --restart=unless-stopped \
  -p 8080:80 \
  -v "$HOME/docker-nginx/html:/usr/share/nginx/html:ro" \
  nginx
```

Docker Compose를 사용하면 이미지, 컨테이너 이름, 포트, 마운트, 재시작 정책을 `compose.yaml` 파일에 기록할 수 있다.

이후에는 다음 한 줄로 서비스를 실행할 수 있다.

```bash
sudo docker compose up -d
```

### Docker Compose의 장점

- 긴 실행 명령어를 파일로 관리할 수 있다.
- 동일한 환경을 반복해서 생성할 수 있다.
- 설정 내용을 GitHub에 저장할 수 있다.
- 여러 컨테이너를 한 번에 관리할 수 있다.
- 컨테이너를 삭제한 뒤에도 같은 구성으로 쉽게 복구할 수 있다.
- 서버 환경을 다른 사람에게 전달하거나 재현하기 쉽다.

---

## 3. Docker Compose 설치 여부 확인

다음 명령어로 Docker Compose가 설치되어 있는지 확인했다.

```bash
sudo docker compose version
```

처음에는 다음 오류가 발생했다.

```text
docker: unknown command: docker compose
```

이는 Docker는 설치되어 있지만 Docker Compose V2는 설치되어 있지 않다는 뜻이다.

---

## 4. Docker Compose V2 설치

Ubuntu 패키지 관리 도구를 이용해 Docker Compose V2를 설치했다.

```bash
sudo apt install docker-compose-v2 -y
```

설치 후 버전을 확인했다.

```bash
sudo docker compose version
```

확인된 버전:

```text
Docker Compose version 2.40.3+ds1-0ubuntu1
```

이를 통해 Docker Compose V2가 정상적으로 설치된 것을 확인했다.

---

## 5. Docker Nginx 프로젝트 디렉터리로 이동

Day 7에서 생성한 Docker Nginx 디렉터리로 이동했다.

```bash
cd ~/docker-nginx
```

현재 작업 경로를 확인했다.

```bash
pwd
```

출력 결과:

```text
/home/sungwoo/docker-nginx
```

현재 디렉터리 구조:

```text
docker-nginx/
├── html/
│   └── index.html
└── compose.yaml
```

---

## 6. Compose 설정 파일 작성

Nano 편집기로 Compose 설정 파일을 생성했다.

```bash
nano compose.yaml
```

다음 내용을 작성했다.

```yaml
services:
  nginx:
    image: nginx:latest
    container_name: home-idc-nginx
    ports:
      - "8080:80"
    volumes:
      - ./html:/usr/share/nginx/html:ro
    restart: unless-stopped
```

Nano에서 다음 순서로 저장하고 종료했다.

```text
Ctrl + O
Enter
Ctrl + X
```

---

## 7. compose.yaml 설정 의미

### services

```yaml
services:
```

Compose에서 관리할 서비스 목록을 정의한다.

---

### nginx

```yaml
  nginx:
```

서비스 이름을 `nginx`로 지정했다.

이 이름은 다음과 같은 Compose 명령에서 사용할 수 있다.

```bash
sudo docker compose logs -f nginx
```

---

### image

```yaml
    image: nginx:latest
```

Docker Hub의 공식 Nginx 최신 이미지를 사용한다.

---

### container_name

```yaml
    container_name: home-idc-nginx
```

컨테이너 이름을 자동 생성하지 않고 `home-idc-nginx`로 고정한다.

---

### ports

```yaml
    ports:
      - "8080:80"
```

Ubuntu 서버의 8080번 포트를 Nginx 컨테이너의 80번 포트에 연결한다.

```text
Ubuntu Server:8080
        ↓
Docker 포트 매핑
        ↓
Nginx 컨테이너:80
```

Windows 브라우저에서는 VirtualBox 포트 포워딩까지 거쳐 다음 주소로 접속한다.

```text
http://127.0.0.1:8081
```

전체 연결 구조:

```text
Windows 127.0.0.1:8081
        ↓
VirtualBox 포트 포워딩
        ↓
Ubuntu Server:8080
        ↓
Docker Compose 포트 매핑
        ↓
Nginx 컨테이너:80
```

---

### volumes

```yaml
    volumes:
      - ./html:/usr/share/nginx/html:ro
```

현재 프로젝트의 `html` 디렉터리를 컨테이너의 Nginx 웹 디렉터리에 연결한다.

```text
Ubuntu 호스트
~/docker-nginx/html
        ↓
바인드 마운트
        ↓
컨테이너
/usr/share/nginx/html
```

`./html`은 `compose.yaml`이 있는 위치를 기준으로 한 상대 경로다.

마지막의 `:ro`는 컨테이너에서 읽기 전용으로 마운트한다는 뜻이다.

---

### restart

```yaml
    restart: unless-stopped
```

관리자가 직접 중지하지 않는 한, 서버 또는 Docker 서비스 재시작 후 컨테이너가 자동으로 다시 실행되도록 설정한다.

---

## 8. YAML 들여쓰기 규칙

YAML 파일은 들여쓰기를 이용해 설정의 계층 구조를 표현한다.

이번 파일에서 사용한 공백 구조:

```text
services:            앞 공백 0칸
  nginx:             앞 공백 2칸
    image:           앞 공백 4칸
    ports:           앞 공백 4칸
      - "8080:80"    앞 공백 6칸
```

주의 사항:

- 탭 대신 스페이스를 사용한다.
- 같은 계층의 항목은 같은 수의 공백을 사용한다.
- 콜론 뒤에는 필요한 경우 한 칸을 띄운다.
- 설정이 중복되지 않도록 확인한다.

---

## 9. 파일명 오류 해결

처음에는 파일을 다음과 같이 잘못 저장했다.

```text
conpose.yam1
```

Docker Compose는 기본적으로 `compose.yaml` 등의 정해진 파일명을 찾기 때문에 다음 오류가 발생했다.

```text
no configuration file provided: not found
```

현재 디렉터리의 파일을 확인했다.

```bash
ls -la
```

잘못된 파일명을 다음 명령어로 수정했다.

```bash
mv conpose.yam1 compose.yaml
```

---

## 10. 중복 설정 오류 해결

Compose 설정 문법을 확인하는 과정에서 다음 오류가 발생했다.

```text
services must be a mapping
```

파일 내용을 확인했다.

```bash
cat -n compose.yaml
```

숨은 문자와 줄 끝을 자세히 확인하기 위해 다음 명령어도 사용했다.

```bash
sed -n 'l' compose.yaml
```

확인 결과 같은 Compose 설정이 두 번 입력되어 다음과 같이 붙어 있었다.

```text
restart: unless-stoppedservices:
```

Nano에서 파일을 다시 열었다.

```bash
nano compose.yaml
```

`Ctrl + K`를 반복해서 기존 내용을 모두 삭제한 후, 올바른 설정을 한 번만 다시 작성했다.

이 과정에서 YAML 파일은 들여쓰기와 줄 구성이 매우 중요하다는 것을 확인했다.

---

## 11. Compose 설정 문법 검사

다음 명령어로 `compose.yaml` 설정을 검사했다.

```bash
sudo docker compose config
```

오류 없이 Compose 설정이 정리되어 출력됐다.

출력 내용에서 다음 항목들을 확인했다.

- 서비스 이름
- 컨테이너 이름
- Nginx 이미지
- 포트 매핑
- 바인드 마운트
- 재시작 정책
- Compose 기본 네트워크

이를 통해 Compose 파일의 문법과 설정이 정상임을 확인했다.

---

## 12. 기존 수동 생성 컨테이너 삭제

Day 7에서 `docker run` 명령어로 직접 생성한 컨테이너가 이미 존재했다.

Compose에서도 같은 컨테이너 이름과 포트를 사용하므로 충돌을 방지하기 위해 기존 컨테이너를 삭제했다.

```bash
sudo docker rm -f home-idc-nginx
```

### `-f` 옵션

`-f`는 실행 중인 컨테이너를 강제로 중지한 후 삭제한다.

출력 결과:

```text
home-idc-nginx
```

호스트에 바인드 마운트된 웹파일은 컨테이너 밖에 저장되어 있으므로 삭제되지 않았다.

---

## 13. Docker Compose로 서비스 실행

Compose 파일을 이용해 Nginx 서비스를 실행했다.

```bash
sudo docker compose up -d
```

출력에서 다음 작업이 수행된 것을 확인했다.

```text
Network Created
Container Created
Container Started
```

### 명령어 의미

- `docker compose up`: Compose 파일에 정의된 서비스 생성 및 실행
- `-d`: 백그라운드 모드로 실행

Compose는 필요한 컨테이너뿐 아니라 서비스가 사용할 기본 네트워크도 자동으로 생성했다.

---

## 14. 브라우저에서 웹서비스 확인

Windows 브라우저에서 다음 주소에 접속했다.

```text
http://127.0.0.1:8081
```

Day 7에서 작성한 다음 웹페이지가 그대로 표시됐다.

```text
Welcome to IDC Lab Day 7
```

이를 통해 다음 항목이 모두 정상 동작함을 확인했다.

- Docker Compose 실행
- 포트 매핑
- VirtualBox 포트 포워딩
- Nginx 컨테이너
- 바인드 마운트
- 호스트의 HTML 파일

---

## 15. Compose 서비스 상태 확인

Compose가 관리하는 컨테이너 상태를 확인했다.

```bash
sudo docker compose ps
```

출력 결과에서 다음 상태를 확인했다.

```text
Up About a minute ago
```

`Up`은 컨테이너가 현재 정상 실행 중이라는 뜻이다.

`docker ps`는 전체 Docker 컨테이너를 보여주고, `docker compose ps`는 현재 Compose 프로젝트의 컨테이너를 중심으로 보여준다.

---

## 16. Compose 서비스 종료 및 삭제

Compose가 관리하는 서비스를 종료했다.

```bash
sudo docker compose down
```

출력 결과에서 다음 작업을 확인했다.

```text
Container Removed
Network Removed
```

`docker compose down`은 Compose가 생성한 컨테이너와 기본 네트워크를 중지하고 삭제한다.

하지만 바인드 마운트로 연결한 Ubuntu 호스트의 파일은 삭제하지 않는다.

```text
삭제되는 항목
- Compose 컨테이너
- Compose 기본 네트워크

유지되는 항목
- compose.yaml
- html/index.html
- Docker 이미지
- 호스트의 웹 데이터
```

---

## 17. Compose 서비스 재생성

같은 Compose 파일로 서비스를 다시 실행했다.

```bash
sudo docker compose up -d
```

새로운 컨테이너와 네트워크가 생성되고 Nginx 서비스가 다시 시작됐다.

브라우저에서 다음 주소를 새로고침했다.

```text
http://127.0.0.1:8081
```

컨테이너가 삭제된 후 다시 생성됐지만 다음 문구가 그대로 나타났다.

```text
Welcome to IDC Lab Day 7
```

이를 통해 Compose 설정 재현성과 바인드 마운트 데이터 영속성이 함께 정상 동작함을 확인했다.

---

## 18. Compose 로그 실시간 확인

Compose 명령어를 이용해 Nginx 서비스의 로그를 실시간으로 확인했다.

```bash
sudo docker compose logs -f nginx
```

### 명령어 의미

- `docker compose logs`: Compose 서비스 로그 확인
- `-f`: 새로운 로그를 실시간으로 계속 표시
- `nginx`: 로그를 확인할 Compose 서비스 이름

명령어를 실행한 상태에서 브라우저를 새로고침했다.

```text
http://127.0.0.1:8081
```

새로고침할 때마다 Nginx 접속 로그가 터미널에 출력됐다.

로그 확인을 종료할 때는 다음 키를 사용했다.

```text
Ctrl + C
```

---

## 19. docker run과 Docker Compose 비교

| 구분 | docker run | Docker Compose |
|---|---|---|
| 설정 위치 | 긴 명령어 | `compose.yaml` |
| 반복 실행 | 명령어를 다시 입력 | `compose up -d` |
| 설정 공유 | 명령어를 별도 기록 | YAML 파일 공유 |
| 여러 서비스 관리 | 각각 실행 | 하나의 파일로 관리 |
| 네트워크 생성 | 직접 구성 가능 | 기본 네트워크 자동 생성 |
| 종료 및 정리 | 개별 명령어 필요 | `compose down` |
| GitHub 관리 | README에 명령 기록 | 실제 설정 파일 업로드 가능 |
| 환경 재현 | 실수 가능성이 큼 | 같은 구성으로 재현 가능 |

---

## 20. 오늘 배운 내용

- Docker Compose는 컨테이너 실행 설정을 YAML 파일로 관리한다.
- `docker-compose-v2` 패키지로 Compose V2를 설치할 수 있다.
- `compose.yaml`은 Compose의 기본 설정 파일명이다.
- YAML에서는 탭이 아니라 스페이스 들여쓰기를 사용해야 한다.
- `docker compose config`로 실행 전에 설정 문법을 검사할 수 있다.
- 같은 컨테이너 이름이나 포트를 사용하면 기존 컨테이너와 충돌할 수 있다.
- `docker compose up -d`로 서비스를 백그라운드 실행할 수 있다.
- `docker compose ps`로 Compose 서비스 상태를 확인할 수 있다.
- `docker compose down`으로 컨테이너와 네트워크를 정리할 수 있다.
- 바인드 마운트된 호스트 데이터는 `compose down` 후에도 유지된다.
- 같은 Compose 파일을 사용하면 동일한 환경을 빠르게 재생성할 수 있다.
- `docker compose logs -f`로 서비스 로그를 실시간 확인할 수 있다.

---

## 21. 장애 및 문제 해결 기록

### 문제 1: Docker Compose 명령어 없음

오류:

```text
docker: unknown command: docker compose
```

해결:

```bash
sudo apt install docker-compose-v2 -y
```

---

### 문제 2: Compose 설정 파일을 찾지 못함

오류:

```text
no configuration file provided: not found
```

원인:

```text
conpose.yam1
```

이라는 잘못된 파일명으로 저장했다.

해결:

```bash
mv conpose.yam1 compose.yaml
```

---

### 문제 3: services must be a mapping

오류:

```text
services must be a mapping
```

원인:

- 같은 설정이 두 번 입력됨
- 두 설정 사이에 줄바꿈이 없었음
- YAML 구조가 깨짐

문제가 된 부분:

```text
restart: unless-stoppedservices:
```

해결:

- 기존 내용을 모두 삭제
- 설정을 한 번만 다시 작성
- 탭 대신 스페이스로 들여쓰기
- `docker compose config`로 문법 재검사

---

## 22. 실제 프로젝트 파일

이번 Day 8 실습에서 생성한 실제 설정 파일:

```text
~/docker-nginx/compose.yaml
```

파일 내용:

```yaml
services:
  nginx:
    image: nginx:latest
    container_name: home-idc-nginx
    ports:
      - "8080:80"
    volumes:
      - ./html:/usr/share/nginx/html:ro
    restart: unless-stopped
```

최종 포트폴리오에서는 README 기록뿐 아니라 이 `compose.yaml` 파일도 GitHub 저장소에 추가할 예정이다.

---

## 23. 다음 실습 계획

- Bash 서버 상태 점검 스크립트 작성
- CPU, 메모리, 디스크 사용량 확인
- Nginx와 Docker 컨테이너 상태 자동 확인
- 점검 결과를 로그 파일에 저장
- 종료 코드와 조건문 사용
- Cron을 이용한 정기 실행
- 웹 콘텐츠 자동 백업
- AWS S3 백업 연동

---


# Day 7 - Docker 바인드 마운트와 데이터 영속성

## 1. 실습 목표

- Docker 컨테이너 데이터가 삭제되는 이유 이해
- Ubuntu 호스트에 웹페이지 파일 저장
- 호스트 디렉터리와 컨테이너 디렉터리 연결
- 읽기 전용 바인드 마운트 구성
- 컨테이너를 삭제하고 재생성해도 웹페이지가 유지되는지 확인
- 관리하기 쉬운 컨테이너 이름과 자동 재시작 정책 적용

---

## 2. 기존 방식의 문제점

기존에는 Docker Nginx 컨테이너 내부의 다음 파일을 직접 수정했다.

```text
/usr/share/nginx/html/index.html
```

하지만 컨테이너 내부에만 저장된 파일은 컨테이너를 삭제하면 함께 사라질 수 있다.

```text
컨테이너 삭제
    ↓
컨테이너 내부 파일 삭제
    ↓
수정한 웹페이지도 사라짐
```

이를 해결하기 위해 웹페이지 파일은 Ubuntu 호스트에 저장하고, 해당 디렉터리를 컨테이너에 연결하는 바인드 마운트를 사용했다.

---

## 3. Ubuntu 호스트에 웹 디렉터리 생성

웹페이지 파일을 보관할 디렉터리를 만들었다.

```bash
mkdir -p ~/docker-nginx/html
```

### 명령어 의미

- `mkdir`: 디렉터리 생성
- `-p`: 상위 디렉터리가 없으면 함께 생성
- `~`: 현재 사용자의 홈 디렉터리

생성된 디렉터리 구조를 확인했다.

```bash
ls -R ~/docker-nginx
```

확인된 디렉터리:

```text
html
```

---

## 4. 호스트에 HTML 파일 생성

Ubuntu 호스트의 디렉터리에 웹페이지 파일을 생성했다.

```bash
echo '<h1>Welcome to IDC Lab Day 7</h1>' > ~/docker-nginx/html/index.html
```

파일 내용을 확인했다.

```bash
cat ~/docker-nginx/html/index.html
```

출력 결과:

```html
<h1>Welcome to IDC Lab Day 7</h1>
```

### 출력 리다이렉션

`>` 기호는 명령어의 출력 결과를 파일에 저장한다.

```text
echo가 생성한 HTML 문장
        ↓
>
        ↓
index.html 파일에 저장
```

---

## 5. 기존 Nginx 컨테이너 중지

기존에 사용하던 Nginx 컨테이너를 중지했다.

```bash
sudo docker stop nice_keller
```

컨테이너 이름이 출력되어 정상적으로 중지된 것을 확인했다.

```text
nice_keller
```

---

## 6. 기존 컨테이너 삭제

중지된 기존 컨테이너를 삭제했다.

```bash
sudo docker rm nice_keller
```

출력 결과:

```text
nice_keller
```

컨테이너를 삭제해도 Docker 이미지 자체가 삭제되는 것은 아니다.

```text
Docker 이미지 = 컨테이너를 만드는 원본
Docker 컨테이너 = 이미지를 바탕으로 생성된 실행 환경
```

---

## 7. 바인드 마운트를 적용한 Nginx 실행

Ubuntu 호스트의 웹 디렉터리를 Docker Nginx의 웹 디렉터리에 연결해 새 컨테이너를 실행했다.

```bash
sudo docker run -d --name home-idc-nginx --restart=unless-stopped -p 8080:80 -v "$HOME/docker-nginx/html:/usr/share/nginx/html:ro" nginx
```

### 명령어 구성

| 옵션 | 의미 |
|---|---|
| `-d` | 컨테이너를 백그라운드에서 실행 |
| `--name home-idc-nginx` | 컨테이너 이름을 직접 지정 |
| `--restart=unless-stopped` | 관리자가 직접 중지하지 않는 한 자동 재시작 |
| `-p 8080:80` | Ubuntu 8080번 포트를 컨테이너 80번 포트에 연결 |
| `-v` | 호스트와 컨테이너 디렉터리 연결 |
| `:ro` | 컨테이너에서 읽기 전용으로 사용 |
| `nginx` | 공식 Nginx 이미지 사용 |

---

## 8. 바인드 마운트 구조

이번 실습에서 연결한 구조는 다음과 같다.

```text
Ubuntu 호스트
$HOME/docker-nginx/html
        ↓ 바인드 마운트
Docker 컨테이너
/usr/share/nginx/html
        ↓
Nginx가 웹페이지 제공
```

호스트 경로:

```text
/home/sungwoo/docker-nginx/html
```

컨테이너 경로:

```text
/usr/share/nginx/html
```

Nginx는 컨테이너의 `/usr/share/nginx/html`을 읽지만, 실제 데이터는 Ubuntu 호스트에 저장된다.

---

## 9. 읽기 전용 마운트 적용

마운트 설정 마지막에 다음 옵션을 사용했다.

```text
:ro
```

`ro`는 `read-only`의 약자로 읽기 전용을 뜻한다.

컨테이너는 웹 파일을 읽어서 사용자에게 제공할 수 있지만, 연결된 호스트 파일을 컨테이너 내부에서 수정할 수는 없다.

장점:

- 컨테이너 내부에서 발생하는 실수 방지
- 웹 콘텐츠 임의 변경 방지
- 호스트 파일 보호
- 서비스와 데이터의 역할 분리

---

## 10. 명령어 오류 해결

처음에는 Docker 실행 과정에서 다음과 같은 재시작 정책 오류가 발생했다.

```text
invalid restart policy
```

Docker가 `-p` 옵션을 재시작 정책값으로 잘못 인식했다.

재시작 정책을 다음처럼 등호와 함께 명확히 지정해 해결했다.

```text
--restart=unless-stopped
```

수정된 명령어:

```bash
sudo docker run -d --name home-idc-nginx --restart=unless-stopped -p 8080:80 -v "$HOME/docker-nginx/html:/usr/share/nginx/html:ro" nginx
```

긴 컨테이너 ID가 출력되어 컨테이너 생성에 성공했다.

---

## 11. 브라우저 접속 확인

Windows 브라우저에서 다음 주소에 접속했다.

```text
http://127.0.0.1:8081
```

다음 문구가 정상적으로 표시됐다.

```text
Welcome to IDC Lab Day 7
```

전체 요청 흐름:

```text
Windows 브라우저
127.0.0.1:8081
        ↓
VirtualBox 포트 포워딩
        ↓
Ubuntu Server:8080
        ↓
Docker 포트 매핑
        ↓
Nginx 컨테이너:80
        ↓
바인드 마운트
        ↓
~/docker-nginx/html/index.html
```

---

## 12. 데이터 영속성 테스트

바인드 마운트의 효과를 확인하기 위해 새로 만든 컨테이너를 중지했다.

```bash
sudo docker stop home-idc-nginx
```

이후 컨테이너를 삭제했다.

```bash
sudo docker rm home-idc-nginx
```

컨테이너가 삭제된 후에도 Ubuntu 호스트의 HTML 파일이 남아 있는지 확인했다.

```bash
cat ~/docker-nginx/html/index.html
```

출력 결과:

```html
<h1>Welcome to IDC Lab Day 7</h1>
```

컨테이너가 삭제됐지만 호스트에 저장된 웹페이지 파일은 그대로 유지됐다.

---

## 13. 컨테이너 재생성

기존과 같은 호스트 디렉터리를 연결해 Nginx 컨테이너를 다시 생성했다.

```bash
sudo docker run -d --name home-idc-nginx --restart=unless-stopped -p 8080:80 -v "$HOME/docker-nginx/html:/usr/share/nginx/html:ro" nginx
```

브라우저에서 다음 주소를 다시 확인했다.

```text
http://127.0.0.1:8081
```

컨테이너를 삭제하고 다시 만들었지만 다음 웹페이지가 그대로 표시됐다.

```text
Welcome to IDC Lab Day 7
```

이를 통해 데이터 영속성이 정상적으로 동작하는 것을 확인했다.

---

## 14. 바인드 마운트를 사용하는 이유

바인드 마운트의 주요 장점은 다음과 같다.

### 데이터 유지

컨테이너가 삭제돼도 호스트의 파일은 유지된다.

### 파일 관리 편의성

컨테이너 내부에 들어가지 않고 Ubuntu 호스트에서 직접 파일을 관리할 수 있다.

### 컨테이너 교체 용이성

기존 컨테이너에 문제가 생겨도 삭제한 후 같은 디렉터리를 연결해 새 컨테이너를 만들 수 있다.

### Git 및 백업 연동

호스트에 있는 파일은 GitHub에 올리거나 압축해 AWS S3에 백업할 수 있다.

### 서비스와 데이터 분리

```text
컨테이너 = 교체 가능한 실행 환경
호스트 디렉터리 = 유지해야 하는 실제 데이터
```

---

## 15. 바인드 마운트와 백업의 차이

바인드 마운트는 컨테이너가 삭제될 때 데이터가 함께 사라지는 것을 방지하지만, 백업 자체는 아니다.

Ubuntu 호스트의 디렉터리가 삭제되거나 가상 디스크에 문제가 생기면 데이터가 사라질 수 있다.

따라서 추후 다음과 같은 별도 백업이 필요하다.

```text
Ubuntu 웹 디렉터리
        ↓ 압축
로컬 백업 파일
        ↓ 업로드
AWS S3
```

---

## 16. 오늘 배운 내용

- 컨테이너 내부에만 저장된 데이터는 컨테이너 삭제 시 사라질 수 있다.
- 바인드 마운트는 호스트 디렉터리를 컨테이너 디렉터리에 연결한다.
- `-v 호스트경로:컨테이너경로` 형식으로 마운트를 설정한다.
- `:ro` 옵션으로 컨테이너에 읽기 권한만 제공할 수 있다.
- 컨테이너 이름을 지정하면 자동 생성 이름보다 관리하기 쉽다.
- `unless-stopped` 정책으로 컨테이너 자동 재시작을 설정할 수 있다.
- 컨테이너를 삭제해도 호스트에 저장된 데이터는 유지된다.
- 같은 호스트 디렉터리를 새 컨테이너에 연결하면 서비스를 빠르게 복구할 수 있다.
- 바인드 마운트는 데이터 영속성을 제공하지만 별도의 백업을 대신하지는 않는다.

---

## 17. 장애 복구 관점에서의 의미

이번 실습에서 다음과 같은 복구 절차를 확인했다.

```text
기존 Nginx 컨테이너 삭제
        ↓
호스트 HTML 파일 유지 확인
        ↓
새 Nginx 컨테이너 생성
        ↓
기존 디렉터리 다시 연결
        ↓
웹 서비스 정상 복구
```

서비스 실행 환경인 컨테이너와 실제 데이터를 분리함으로써 컨테이너 장애 또는 교체 상황에서 빠른 복구가 가능해졌다.

---

## 18. 다음 실습 계획

- Docker Compose 설치 및 기본 문법 학습
- 긴 `docker run` 명령어를 Compose 파일로 변환
- `docker compose up -d`로 서비스 실행
- `docker compose down` 후 재생성
- Bash 서버 상태 점검 스크립트 작성
- 웹 디렉터리 자동 백업
- Cron을 이용한 주기적 실행
- AWS S3 백업 연동

---


# Day 6 - Docker Nginx 컨테이너 구축 및 장애 복구

## 1. 실습 목표

- Docker 컨테이너에서 Nginx 실행
- 호스트 포트와 컨테이너 포트 연결
- Ubuntu에 직접 설치한 Nginx와 Docker Nginx 비교
- Docker 컨테이너 내부 구조 확인
- 컨테이너 웹페이지 수정
- Docker 로그 실시간 확인
- 컨테이너 중지 및 서비스 복구
- 컨테이너 자동 재시작 정책 설정

---

## 2. Docker Nginx 컨테이너 실행

Docker Hub의 공식 Nginx 이미지를 사용해 컨테이너를 실행했다.

```bash
sudo docker run -d -p 8080:80 nginx
```

### 명령어 의미

- `docker run`: 새로운 컨테이너 생성 및 실행
- `-d`: 컨테이너를 백그라운드에서 실행
- `-p 8080:80`: Ubuntu 서버의 8080번 포트를 컨테이너의 80번 포트에 연결
- `nginx`: 사용할 Docker 이미지 이름

포트 연결 구조:

```text
Ubuntu Server 8080
        ↓
Docker 포트 매핑
        ↓
Nginx 컨테이너 80
```

---

## 3. VirtualBox 포트 포워딩 추가

Windows 브라우저에서 Docker Nginx에 접속하기 위해 VirtualBox 포트 포워딩 규칙을 추가했다.

설정 경로:

```text
VirtualBox
→ home-idc-ubuntu
→ 설정
→ 네트워크
→ 어댑터 1
→ 고급
→ 포트 포워딩
```

추가한 규칙:

| 설정 | 값 |
|---|---|
| 이름 | docker-nginx |
| 프로토콜 | TCP |
| 호스트 IP | 127.0.0.1 |
| 호스트 포트 | 8081 |
| 게스트 IP | 공란 또는 10.0.2.15 |
| 게스트 포트 | 8080 |

전체 요청 흐름:

```text
Windows 브라우저
127.0.0.1:8081
        ↓
VirtualBox 포트 포워딩
        ↓
Ubuntu Server:8080
        ↓
Docker 포트 매핑
        ↓
Nginx 컨테이너:80
```

---

## 4. Docker Nginx 접속 확인

Windows 브라우저에서 다음 주소에 접속했다.

```text
http://127.0.0.1:8081
```

다음 기본 페이지가 표시되어 Docker Nginx가 정상적으로 실행되는 것을 확인했다.

```text
Welcome to nginx!
```

Ubuntu 서버 내부에서도 다음 명령어로 응답을 확인했다.

```bash
curl localhost:8080
```

Nginx 기본 HTML 코드가 출력되어 Ubuntu 서버와 컨테이너 사이의 포트 연결이 정상임을 확인했다.

---

## 5. 기존 Nginx와 Docker Nginx 비교

이번 실습 환경에는 서로 분리된 두 개의 Nginx가 실행되고 있다.

| 브라우저 주소 | 실행 위치 | 표시되는 페이지 |
|---|---|---|
| `127.0.0.1:8080` | Ubuntu에 직접 설치한 Nginx | Home IDC Lab Day 2 |
| `127.0.0.1:8081` | Docker 컨테이너의 Nginx | Docker Nginx 페이지 |

두 Nginx는 서로 다른 파일과 설정을 사용한다.

```text
Ubuntu 직접 설치 Nginx
→ /var/www/html

Docker Nginx
→ /usr/share/nginx/html
```

Docker를 사용하면 여러 서비스를 서로 분리해서 실행할 수 있고, 컨테이너 단위로 생성·중지·삭제·복구할 수 있다.

---

## 6. 실행 중인 컨테이너 확인

다음 명령어로 실행 중인 컨테이너를 확인했다.

```bash
sudo docker ps
```

실행 중인 Nginx 컨테이너의 자동 생성 이름은 다음과 같았다.

```text
nice_keller
```

컨테이너가 실행 중일 때 상태는 다음과 같이 표시된다.

```text
Up
```

종료된 컨테이너까지 모두 확인하려면 다음 명령어를 사용한다.

```bash
sudo docker ps -a
```

---

## 7. Nginx 컨테이너 내부 접속

실행 중인 Nginx 컨테이너 내부에 Bash 셸로 접속했다.

```bash
sudo docker exec -it nice_keller bash
```

### 명령어 의미

- `docker exec`: 실행 중인 컨테이너 안에서 명령 실행
- `-it`: 터미널을 통해 대화형으로 작업
- `nice_keller`: 컨테이너 이름
- `bash`: 컨테이너 내부에서 실행할 셸

접속에 성공하면 프롬프트가 다음과 같은 형태로 변경된다.

```text
root@컨테이너ID:/#
```

이 상태는 Ubuntu 호스트가 아니라 Docker 컨테이너 내부에서 명령을 실행하고 있다는 뜻이다.

---

## 8. 컨테이너 Nginx 설정 검사

컨테이너 내부에서 Nginx 설정 문법을 검사했다.

```bash
nginx -t
```

다음과 같은 메시지가 나타나 설정에 문법 오류가 없음을 확인했다.

```text
syntax is ok
test is successful
```

Docker 컨테이너에는 일반적으로 `systemd`가 실행되지 않기 때문에 다음 명령어는 사용할 수 없었다.

```bash
systemctl reload nginx
```

대신 다음 명령어로 Nginx 설정을 다시 불러왔다.

```bash
nginx -s reload
```

출력된 메시지:

```text
signal process started
```

이는 Nginx 프로세스가 설정 재적용 신호를 정상적으로 받았다는 뜻이다.

---

## 9. Nginx 설정 파일 구조 확인

Nginx 메인 설정 파일을 확인했다.

```bash
cat /etc/nginx/nginx.conf
```

설정 파일에서 다음 `include` 항목을 확인했다.

```nginx
include /etc/nginx/conf.d/*.conf;
```

이는 Nginx가 `/etc/nginx/conf.d` 디렉터리 안의 `.conf` 설정 파일을 추가로 읽는다는 뜻이다.

기본 서버 설정 파일도 확인했다.

```bash
cat /etc/nginx/conf.d/default.conf
```

주요 설정:

```nginx
listen 80;
root /usr/share/nginx/html;
```

설정 의미:

- `listen 80`: 컨테이너의 80번 포트에서 HTTP 요청 대기
- `root /usr/share/nginx/html`: 해당 디렉터리에서 웹페이지 파일 제공

따라서 Docker Nginx의 기본 웹페이지 파일은 다음 위치에 있다.

```text
/usr/share/nginx/html/index.html
```

---

## 10. Docker Nginx 웹페이지 수정

Nginx 공식 이미지에는 `vi`나 `nano` 편집기가 설치되어 있지 않아 다음 오류가 발생했다.

```text
vi: command not found
```

따라서 `echo`와 출력 리다이렉션을 이용해 HTML 파일을 수정했다.

```bash
echo '<h1>Welcome to IDC Lab Day 7</h1>' > /usr/share/nginx/html/index.html
```

### `>` 기호의 의미

`>`는 명령어의 출력 내용을 파일에 저장하며 기존 내용을 덮어쓴다.

```text
echo로 생성한 HTML
        ↓
>
        ↓
index.html에 저장
```

수정된 파일 내용을 확인했다.

```bash
cat /usr/share/nginx/html/index.html
```

출력 결과:

```html
<h1>Welcome to IDC Lab Day 7</h1>
```

브라우저에서 다음 주소를 새로고침했다.

```text
http://127.0.0.1:8081
```

변경된 문구가 정상적으로 표시됐다.

정적 HTML 파일 변경은 Nginx 설정 변경이 아니므로 일반적으로 Nginx를 재시작하거나 리로드하지 않아도 바로 반영된다.

---

## 11. 컨테이너에서 나오기

컨테이너 내부 작업을 마치고 Ubuntu 호스트로 돌아왔다.

```bash
exit
```

프롬프트가 다음 형태로 돌아와 컨테이너에서 정상적으로 빠져나온 것을 확인했다.

```text
sungwoo@home-idc-ubuntu
```

---

## 12. Docker Nginx 로그 구조 확인

컨테이너 내부에서 Nginx 로그 경로를 확인했다.

```bash
ls -l /var/log/nginx
```

확인 결과:

```text
access.log -> /dev/stdout
error.log  -> /dev/stderr
```

Docker Nginx는 로그를 일반 파일에 저장하는 대신 다음 표준 출력으로 전달한다.

- `stdout`: 일반 접속 로그
- `stderr`: 오류 로그

이 방식은 Docker 환경에서 일반적으로 사용되며, 호스트에서 `docker logs` 명령어로 로그를 확인할 수 있다.

---

## 13. 컨테이너 로그 실시간 확인

Ubuntu 호스트에서 다음 명령어를 실행했다.

```bash
sudo docker logs -f nice_keller
```

### 명령어 의미

- `docker logs`: 컨테이너 로그 확인
- `-f`: 새로운 로그를 실시간으로 계속 출력
- `nice_keller`: 로그를 확인할 컨테이너 이름

브라우저에서 다음 주소를 새로고침했다.

```text
http://127.0.0.1:8081
```

새로고침할 때마다 Docker 터미널에 Nginx 접속 로그가 실시간으로 출력되는 것을 확인했다.

실시간 로그 확인을 종료할 때는 다음 키를 사용했다.

```text
Ctrl + C
```

---

## 14. 컨테이너 이름 오타 문제 해결

처음에는 컨테이너 이름을 다음과 같이 잘못 입력했다.

```text
nice_kellar
```

그 결과 다음 오류가 발생했다.

```text
Error response from daemon:
No such container: nice_kellar
```

다음 명령어로 실제 컨테이너 이름을 다시 확인했다.

```bash
sudo docker ps -a
```

정확한 컨테이너 이름:

```text
nice_keller
```

정확한 이름을 사용한 후 로그 확인에 성공했다.

```bash
sudo docker logs -f nice_keller
```

---

## 15. Docker 컨테이너 장애 재현

컨테이너 장애 상황을 재현하기 위해 실행 중인 Nginx 컨테이너를 중지했다.

```bash
sudo docker stop nice_keller
```

브라우저에서 다음 주소를 새로고침했다.

```text
http://127.0.0.1:8081
```

컨테이너가 중지되어 Nginx가 요청에 응답하지 못했고, 브라우저가 계속 접속을 기다리는 현상을 확인했다.

---

## 16. Docker 컨테이너 서비스 복구

중지된 Nginx 컨테이너를 다시 시작했다.

```bash
sudo docker start nice_keller
```

브라우저를 다시 새로고침하자 웹페이지가 즉시 정상적으로 표시됐다.

컨테이너 상태도 확인했다.

```bash
sudo docker ps
```

다음 상태가 표시되어 정상 실행 중임을 확인했다.

```text
Up
```

이번 실습에서 확인한 복구 흐름:

```text
Docker Nginx 접속 장애
        ↓
docker ps로 상태 확인
        ↓
docker start로 컨테이너 시작
        ↓
브라우저에서 서비스 복구 확인
```

---

## 17. 컨테이너 자동 재시작 설정

Ubuntu 서버 또는 Docker 서비스가 재시작된 후 컨테이너가 자동으로 다시 실행되도록 재시작 정책을 설정했다.

```bash
sudo docker update --restart unless-stopped nice_keller
```

### `unless-stopped` 의미

컨테이너가 오류 또는 서버 재부팅으로 중지되면 Docker가 자동으로 다시 실행한다.

단, 관리자가 직접 `docker stop` 명령어로 컨테이너를 중지한 경우에는 자동으로 시작하지 않는다.

재시작 정책을 확인했다.

```bash
sudo docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' nice_keller
```

출력 결과:

```text
unless-stopped
```

이를 통해 컨테이너 자동 재시작 정책이 정상적으로 설정된 것을 확인했다.

---

## 18. 직접 설치 방식과 Docker 방식의 차이

| 구분 | Ubuntu 직접 설치 | Docker 컨테이너 |
|---|---|---|
| 실행 위치 | Ubuntu 운영체제 | 격리된 컨테이너 |
| 웹 파일 위치 | `/var/www/html` | `/usr/share/nginx/html` |
| 서비스 관리 | `systemctl` | `docker` 명령어 |
| 로그 확인 | `/var/log/nginx` | `docker logs` |
| 재시작 | `systemctl restart nginx` | `docker restart 컨테이너명` |
| 삭제 및 재생성 | 패키지와 설정 정리 필요 | 컨테이너 단위로 관리 가능 |
| 환경 분리 | 운영체제 환경 공유 | 컨테이너별 환경 분리 |

Docker가 항상 더 안전하거나 비용이 더 적게 드는 것은 아니다.

보안과 비용은 이미지 관리, 권한 설정, 네트워크 구성, 자원 사용량 및 운영 방식에 따라 달라진다. Docker의 주요 장점은 서비스 격리, 동일 환경 재현, 배포 및 복구의 편리함이다.

---

## 19. 오늘 배운 내용

- Docker를 이용해 Nginx 컨테이너를 실행할 수 있다.
- `-p 8080:80`은 호스트의 8080번 포트를 컨테이너의 80번 포트에 연결한다.
- VirtualBox 포트 포워딩을 추가하면 Windows에서 Docker 서비스에 접속할 수 있다.
- Ubuntu 직접 설치 Nginx와 Docker Nginx는 서로 독립적인 서비스다.
- `docker exec -it`로 실행 중인 컨테이너 내부에 접속할 수 있다.
- 컨테이너에서는 `systemctl`이 없는 경우가 많다.
- Nginx 컨테이너에서는 `nginx -s reload`를 사용할 수 있다.
- Docker Nginx의 웹 루트는 `/usr/share/nginx/html`이다.
- `>`를 사용하면 명령어 출력을 파일에 덮어쓸 수 있다.
- Docker Nginx 로그는 `stdout`과 `stderr`로 전달된다.
- `docker logs -f`로 컨테이너 로그를 실시간 확인할 수 있다.
- `docker stop`과 `docker start`로 장애와 복구를 실습할 수 있다.
- `unless-stopped` 정책으로 컨테이너 자동 재시작을 설정할 수 있다.

---

## 20. 문제 해결 기록

### 문제 1: Windows에서 Docker Nginx 접속 실패

Ubuntu 서버 내부에서는 다음 명령어가 정상적으로 동작했다.

```bash
curl localhost:8080
```

하지만 Windows 브라우저에서는 Docker Nginx에 접속할 수 없었다.

### 원인

VirtualBox에는 기존 Nginx용 포트 포워딩만 있었고, Docker Nginx의 Ubuntu 8080번 포트를 Windows로 전달하는 규칙이 없었다.

### 해결

다음 포트 포워딩 규칙을 추가했다.

```text
Windows 127.0.0.1:8081
→ Ubuntu Server:8080
→ Docker Nginx:80
```

이후 `http://127.0.0.1:8081` 접속에 성공했다.

---

### 문제 2: vi 편집기 없음

컨테이너 내부에서 다음 명령어를 사용하려 했다.

```bash
vi /usr/share/nginx/html/index.html
```

하지만 다음 오류가 발생했다.

```text
vi: command not found
```

### 해결

`echo`와 `>`를 이용해 HTML 파일을 수정했다.

```bash
echo '<h1>Welcome to IDC Lab Day 7</h1>' > /usr/share/nginx/html/index.html
```

---

### 문제 3: echo 결과만 출력되고 파일이 변경되지 않음

처음에는 다음 명령어만 실행했다.

```bash
echo '<h1>Welcome to IDC Lab Day 7</h1>'
```

이 명령어는 문구를 터미널에 출력할 뿐 파일에 저장하지 않는다.

다음과 같이 `>`와 파일 경로를 추가해 해결했다.

```bash
echo '<h1>Welcome to IDC Lab Day 7</h1>' > /usr/share/nginx/html/index.html
```

---

### 문제 4: 컨테이너에서 systemctl 사용 불가

컨테이너 내부에서 다음 명령어를 실행했지만 사용할 수 없었다.

```bash
systemctl reload nginx
```

### 원인

일반적인 Docker 컨테이너에서는 `systemd`가 PID 1로 실행되지 않으므로 `systemctl`을 사용할 수 없는 경우가 많다.

### 해결

Nginx 자체 명령어를 사용했다.

```bash
nginx -s reload
```

---

## 21. 다음 실습 계획

- Docker 컨테이너 데이터 영속성 이해
- Ubuntu 디렉터리와 컨테이너 웹 디렉터리 연결
- Docker 볼륨과 바인드 마운트 실습
- 컨테이너를 삭제하고 다시 생성해 웹페이지 유지 확인
- 컨테이너 이름을 직접 지정해 관리
- Docker Compose를 이용한 서비스 구성
- Prometheus와 Grafana 모니터링 환경 구축

---


# Day 5 - Linux 파일 권한 관리 및 Docker 설치

## 1. 실습 목표

- Linux 파일의 권한과 소유자 정보 확인
- `chmod`를 이용한 파일 권한 변경
- `chown`을 이용한 파일 소유자 변경
- 읽기·쓰기 권한의 차이 이해
- Ubuntu Server에 Docker 설치
- Docker 서비스를 시작하고 자동 실행 설정
- `hello-world` 컨테이너 실행

---

## 2. Nginx 웹페이지 파일 권한 확인

다음 명령어로 Nginx 웹페이지 디렉터리의 파일과 권한을 확인했다.

```bash
ls -l /var/www/html
```

확인된 주요 파일:

```text
index.nginx-debian.html
index.nginx-debian.html.bak
```

특정 파일의 권한과 소유자를 확인할 때는 다음 명령어를 사용했다.

```bash
ls -l /var/www/html/index.nginx-debian.html
```

출력 예시:

```text
-rw-r--r-- 1 root root ...
```

주요 정보는 다음 순서로 표시된다.

```text
파일 권한 / 링크 수 / 소유자 / 그룹 / 파일 크기 / 수정 시간 / 파일명
```

---

## 3. Linux 파일 권한 구조

Linux 파일 권한은 다음 세 대상에게 각각 적용된다.

```text
소유자(User)
그룹(Group)
그 외 사용자(Others)
```

권한 문자의 의미:

| 문자 | 의미 |
|---|---|
| `r` | Read, 읽기 |
| `w` | Write, 쓰기 및 수정 |
| `x` | Execute, 실행 |
| `-` | 해당 권한 없음 |

예를 들어 다음 권한은:

```text
rw-r--r--
```

다음과 같은 의미다.

```text
소유자: 읽기와 쓰기 가능
그룹: 읽기만 가능
그 외 사용자: 읽기만 가능
```

---

## 4. chmod를 이용한 읽기 전용 권한 설정

Nginx 웹페이지 파일을 모든 사용자가 읽기만 할 수 있도록 변경했다.

```bash
sudo chmod 444 /var/www/html/index.nginx-debian.html
```

변경 후 권한을 확인했다.

```bash
ls -l /var/www/html/index.nginx-debian.html
```

변경된 권한:

```text
r--r--r--
```

숫자 `444`의 의미:

```text
소유자: 읽기만 가능
그룹: 읽기만 가능
그 외 사용자: 읽기만 가능
```

Linux 권한 숫자의 기본값은 다음과 같다.

| 숫자 | 권한 |
|---|---|
| 4 | 읽기 |
| 2 | 쓰기 |
| 1 | 실행 |

여러 권한을 함께 부여할 때 숫자를 더한다.

```text
6 = 읽기 4 + 쓰기 2
7 = 읽기 4 + 쓰기 2 + 실행 1
```

---

## 5. echo 명령어 확인

다음 명령어를 실행했다.

```bash
echo test
```

터미널에 다음 문구가 출력됐다.

```text
test
```

`echo test`는 파일을 수정하는 명령어가 아니라 터미널 화면에 `test`라는 문자를 출력하는 명령어다.

파일에 내용을 저장하려면 리다이렉션 기호가 필요하다.

```bash
echo test > filename
```

하지만 이번 실습에서는 실제 Nginx 웹페이지 파일을 보호하기 위해 리다이렉션을 사용하지 않았다.

---

## 6. 파일 권한 원상 복구

Nginx가 정상적으로 파일을 제공하고 소유자가 파일을 수정할 수 있도록 권한을 다시 `644`로 복구했다.

```bash
sudo chmod 644 /var/www/html/index.nginx-debian.html
```

변경 결과를 확인했다.

```bash
ls -l /var/www/html/index.nginx-debian.html
```

복구된 권한:

```text
rw-r--r--
```

숫자 `644`의 의미:

```text
소유자: 읽기와 쓰기 가능
그룹: 읽기만 가능
그 외 사용자: 읽기만 가능
```

웹페이지나 설정 파일에서 자주 볼 수 있는 기본적인 파일 권한 형태다.

---

## 7. 현재 로그인 사용자 확인

다음 명령어로 현재 로그인한 사용자 계정을 확인했다.

```bash
whoami
```

출력 결과:

```text
sungwoo
```

`whoami`는 현재 명령을 실행하고 있는 사용자 계정을 확인하는 명령어다.

---

## 8. chown을 이용한 파일 소유자 변경

`chown`은 파일이나 디렉터리의 소유자와 그룹을 변경하는 명령어다.

Nginx 웹페이지 파일의 소유자와 그룹을 `sungwoo`로 변경했다.

```bash
sudo chown sungwoo:sungwoo /var/www/html/index.nginx-debian.html
```

명령어 구조:

```text
chown 소유자:그룹 파일경로
```

변경 후 소유자 정보를 확인했다.

```bash
ls -l /var/www/html/index.nginx-debian.html
```

소유자와 그룹이 다음과 같이 표시되는 것을 확인했다.

```text
sungwoo sungwoo
```

### chmod와 chown의 차이

| 명령어 | 역할 |
|---|---|
| `chmod` | 파일을 누가 읽고 쓰고 실행할 수 있는지 변경 |
| `chown` | 파일의 소유자와 그룹을 변경 |

쉽게 비유하면:

```text
chmod = 열쇠와 사용 권한 변경
chown = 집주인 변경
```

실제 운영 환경에서는 서비스 정책에 맞는 소유자와 권한을 사용해야 하며, 임의로 변경하기 전에 기존 설정을 확인해야 한다.

---

# Docker 설치 및 첫 컨테이너 실행

## 9. Docker란?

Docker는 애플리케이션과 실행에 필요한 파일을 컨테이너라는 단위로 묶어 실행하는 도구다.

일반적으로 프로그램을 직접 설치하면 운영체제의 설정과 다른 프로그램의 영향을 받을 수 있다.

Docker를 사용하면 프로그램이 실행될 환경을 하나의 컨테이너로 분리할 수 있다.

```text
Ubuntu Server
    └── Docker
          ├── Nginx 컨테이너
          ├── Prometheus 컨테이너
          └── Grafana 컨테이너
```

앞으로 Nginx, Prometheus, Grafana 등의 서비스를 Docker 컨테이너로 실행할 예정이다.

---

## 10. Docker 설치 여부 확인

Docker가 설치되어 있는지 확인했다.

```bash
docker --version
```

처음에는 Docker가 설치되지 않아 명령어를 찾을 수 없다는 메시지가 나타날 수 있다.

```text
command not found
```

---

## 11. Ubuntu 패키지 목록 업데이트

Docker를 설치하기 전에 Ubuntu 패키지 목록을 갱신했다.

```bash
sudo apt update
```

---

## 12. Docker 설치

Ubuntu 패키지 저장소에서 Docker를 설치했다.

```bash
sudo apt install docker.io -y
```

`-y` 옵션은 설치 과정의 확인 질문에 자동으로 동의한다는 뜻이다.

---

## 13. Docker 서비스 시작

Docker 서비스를 시작했다.

```bash
sudo systemctl start docker
```

Docker가 Ubuntu 서버를 재부팅한 후에도 자동으로 실행되도록 설정했다.

```bash
sudo systemctl enable docker
```

---

## 14. Docker 서비스 상태 확인

다음 명령어로 Docker 서비스 상태를 확인했다.

```bash
sudo systemctl status docker
```

다음 상태가 표시되어 정상 실행 중인 것을 확인했다.

```text
active (running)
```

상태 확인 화면에서 빠져나올 때는 다음 키를 사용한다.

```text
q
```

---

## 15. Docker 버전 확인

설치가 완료된 후 다음 명령어를 다시 실행했다.

```bash
docker --version
```

Docker 버전 정보가 정상적으로 출력되는 것을 확인했다.

---

## 16. hello-world 컨테이너 실행

Docker가 정상적으로 이미지를 다운로드하고 컨테이너를 실행할 수 있는지 확인하기 위해 공식 테스트 이미지를 실행했다.

```bash
sudo docker run hello-world
```

다음 문구가 출력되어 Docker가 정상적으로 동작하는 것을 확인했다.

```text
Hello from Docker!
```

이 명령을 실행하면 Docker는 다음 과정을 수행한다.

```text
1. 로컬에 hello-world 이미지가 있는지 확인
2. 이미지가 없으면 Docker Hub에서 다운로드
3. 이미지를 기반으로 컨테이너 생성
4. 컨테이너 실행
5. 테스트 메시지 출력
6. 작업 완료 후 컨테이너 종료
```

---

## 17. Docker 컨테이너 목록 확인

실행 중이거나 종료된 모든 컨테이너를 확인했다.

```bash
sudo docker ps -a
```

`hello-world` 컨테이너가 다음 상태로 표시됐다.

```text
Exited (0)
```

`Exited (0)`은 오류가 아니라 컨테이너가 맡은 작업을 정상적으로 완료하고 종료됐다는 뜻이다.

`hello-world` 컨테이너는 메시지를 한 번 출력한 후 계속 실행될 필요가 없기 때문에 자동으로 종료된다.

### Docker 상태 코드 의미

```text
Exited (0) = 정상 종료
Exited (0 이외의 숫자) = 오류 또는 비정상 종료 가능성
Up = 현재 실행 중
```

---

## 18. 이미지와 컨테이너의 차이

Docker 이미지와 컨테이너는 서로 다른 개념이다.

| 개념 | 의미 |
|---|---|
| 이미지 | 프로그램을 실행하기 위한 설계도 또는 원본 |
| 컨테이너 | 이미지를 기반으로 실제 실행된 프로그램 |
| Docker Hub | Docker 이미지를 내려받을 수 있는 저장소 |

비유하면 다음과 같다.

```text
이미지 = 붕어빵 틀
컨테이너 = 틀을 이용해 실제로 만든 붕어빵
```

하나의 이미지로 여러 개의 컨테이너를 만들 수 있다.

---

## 19. 오늘 배운 내용

- `ls -l`로 파일 권한과 소유자를 확인할 수 있다.
- `chmod`는 파일의 읽기·쓰기·실행 권한을 변경한다.
- `444`는 모든 사용자가 읽기만 가능한 권한이다.
- `644`는 소유자는 읽기와 쓰기가 가능하고 나머지는 읽기만 가능한 권한이다.
- `whoami`는 현재 로그인한 사용자를 확인한다.
- `chown`은 파일의 소유자와 그룹을 변경한다.
- Docker는 애플리케이션을 컨테이너 형태로 분리해 실행한다.
- `docker.io` 패키지를 통해 Ubuntu에 Docker를 설치할 수 있다.
- `systemctl`로 Docker 서비스를 시작하고 자동 실행을 설정할 수 있다.
- `docker run`은 이미지를 기반으로 새로운 컨테이너를 생성하고 실행한다.
- `docker ps -a`는 실행 중이거나 종료된 모든 컨테이너를 보여준다.
- `Exited (0)`은 컨테이너가 정상적으로 실행을 완료했다는 뜻이다.

---

## 20. 문제 해결 기록

### 문제 1: 파일 경로 오류

파일 경로를 입력하는 과정에서 경로 중간에 공백이 들어가 다음 오류가 발생했다.

```text
cannot access
```

잘못된 형태:

```text
/var/www /html /index.nginx-debian.html
```

올바른 형태:

```text
/var/www/html/index.nginx-debian.html
```

Linux 파일 경로는 특별한 경우가 아니라면 중간에 임의의 공백을 넣으면 안 된다.

---

### 문제 2: 파일 이름 착각

처음에는 Nginx 웹페이지 파일 이름을 `index.html`로 입력했으나 실제 파일 이름은 다음과 같았다.

```text
index.nginx-debian.html
```

다음 명령어로 실제 파일 이름을 확인한 뒤 정확한 경로를 사용했다.

```bash
ls -l /var/www/html
```

---

### 문제 3: echo 명령어 이해

다음 명령을 실행했을 때 `test`가 출력되어 파일이 변경된 것으로 착각했다.

```bash
echo test
```

하지만 이 명령어는 단순히 터미널에 문자를 출력한 것이며 파일을 변경하지 않는다.

파일 내용을 변경하려면 다음과 같이 출력 리다이렉션을 사용해야 한다.

```bash
echo test > filename
```

운영 파일을 실수로 덮어쓰지 않도록 실제 서비스 파일에서는 주의해야 한다.

---

## 21. 다음 실습 계획

- Docker로 Nginx 컨테이너 실행
- 호스트 포트와 컨테이너 포트 연결
- 기존 Ubuntu Nginx와 Docker Nginx 비교
- Docker 이미지와 컨테이너 관리 명령어 실습
- 컨테이너 중지, 시작, 삭제 실습
- Docker 컨테이너 로그 확인
- Prometheus와 Grafana 모니터링 환경 구축

---


# Day 4 - Nginx 로그 확인 및 웹 서버 장애 복구

## 1. 실습 목표

- Nginx 접속 로그 확인
- HTTP 상태 코드 이해
- Nginx 서비스를 일부러 중지해 장애 상황 재현
- 서비스 상태를 확인하고 웹 서버 복구
- 접속 로그를 실시간으로 모니터링

---

## 2. Nginx 접속 로그 확인

최근 Nginx 접속 기록 20줄을 확인했다.

```bash
sudo tail -n 20 /var/log/nginx/access.log
```

### 명령어 의미

- `sudo`: 관리자 권한으로 실행
- `tail`: 파일의 마지막 부분을 출력
- `-n 20`: 마지막 20줄을 표시
- `/var/log/nginx/access.log`: Nginx 접속 로그 파일

접속 로그에서는 다음과 같은 정보를 확인할 수 있었다.

- 접속한 클라이언트의 IP 주소
- 접속 시간
- 요청 방식
- 요청한 페이지
- HTTP 상태 코드
- 사용한 웹 브라우저와 운영체제 정보

접속 로그 예시:

```text
GET / HTTP/1.1 200
```

---

## 3. HTTP 상태 코드 확인

접속 로그에서 `200`과 `304` 상태 코드를 확인했다.

### HTTP 200

```text
200 OK
```

서버가 요청을 정상적으로 처리하고 웹페이지 내용을 전달했다는 뜻이다.

### HTTP 304

```text
304 Not Modified
```

요청한 파일이 이전과 달라지지 않았으므로 브라우저에 저장된 캐시를 사용해도 된다는 뜻이다.

처음 접속할 때는 `200`이 나타나고, 같은 페이지를 다시 불러올 때 `304`가 나타날 수 있다.

두 상태 모두 일반적인 정상 응답이다.

---

## 4. Nginx 장애 상황 재현

실제 서버 장애 대응 과정을 연습하기 위해 Nginx 서비스를 일부러 중지했다.

```bash
sudo systemctl stop nginx
```

Windows 브라우저에서 다음 주소를 새로고침했다.

```text
http://127.0.0.1:8080
```

브라우저에 다음과 같은 오류가 나타났다.

```text
사이트에 연결할 수 없음
```

Nginx 서비스가 중지되면서 Ubuntu 서버의 80번 포트에서 웹 요청을 처리할 프로그램이 없어졌기 때문이다.

---

## 5. Nginx 서비스 복구

중지된 Nginx 서비스를 다시 시작했다.

```bash
sudo systemctl start nginx
```

브라우저를 다시 새로고침하자 웹페이지가 정상적으로 표시됐다.

```text
Home IDC Lab Day 2
```

이를 통해 다음 장애 복구 흐름을 실습했다.

```text
서비스 장애 확인
        ↓
Nginx 서비스 상태 확인
        ↓
서비스 재시작
        ↓
브라우저에서 정상 동작 확인
```

---

## 6. Nginx 서비스 상태 확인

다음 명령어로 Nginx의 현재 상태를 확인했다.

```bash
sudo systemctl status nginx
```

확인한 주요 상태:

```text
Active: active (running)
Enabled
```

### 상태 의미

- `active (running)`: 현재 Nginx 서비스가 실행 중
- `enabled`: Ubuntu 서버가 부팅될 때 Nginx가 자동으로 실행됨

상태 확인 화면에서 빠져나올 때는 다음 키를 사용한다.

```text
q
```

---

## 7. Nginx 접속 로그 실시간 확인

Nginx 접속 로그를 실시간으로 확인했다.

```bash
sudo tail -f /var/log/nginx/access.log
```

### `-f` 옵션 의미

`-f`는 `follow`의 약자로, 로그 파일에 새로운 내용이 추가될 때마다 터미널에 바로 표시한다.

이 명령어를 실행한 상태에서 Windows 브라우저의 웹페이지를 여러 번 새로고침했다.

```text
http://127.0.0.1:8080
```

새로고침할 때마다 SSH 터미널에 새로운 접속 로그가 실시간으로 추가되는 것을 확인했다.

실시간 로그 확인을 종료할 때는 다음 키를 사용했다.

```text
Ctrl + C
```

---

## 8. 실시간 로그의 활용

실제 서버 운영 중 웹사이트 접속 장애가 발생하면 접속 로그를 통해 다음 내용을 확인할 수 있다.

- 사용자의 요청이 서버까지 도착하는지
- 어떤 주소로 요청했는지
- 서버가 어떤 상태 코드로 응답했는지
- 특정 시간에 오류가 집중됐는지
- 어떤 브라우저 또는 클라이언트가 접속했는지

예를 들어 접속 로그에 요청이 전혀 나타나지 않는다면 네트워크, 방화벽 또는 포트 포워딩 문제를 의심할 수 있다.

요청은 들어오지만 오류 상태 코드가 나타난다면 Nginx 설정이나 웹페이지 파일 문제를 확인할 수 있다.

---

## 9. Nginx 오류 로그

Nginx의 오류 기록은 다음 파일에 저장된다.

```text
/var/log/nginx/error.log
```

최근 오류 로그 20줄을 확인하는 정확한 명령어는 다음과 같다.

```bash
sudo tail -n 20 /var/log/nginx/error.log
```

오류 로그에는 다음과 같은 문제가 기록될 수 있다.

- 웹페이지 파일을 찾지 못함
- 파일 접근 권한 부족
- Nginx 설정 파일 오류
- 포트 충돌
- 업스트림 서버 연결 실패

오류가 발생하지 않았다면 아무 내용이 없거나 기록이 적을 수 있다.

---

## 10. 오늘 배운 내용

- Nginx 접속 로그는 `/var/log/nginx/access.log`에 저장된다.
- Nginx 오류 로그는 `/var/log/nginx/error.log`에 저장된다.
- `tail -n 20`은 로그 파일의 최근 20줄을 확인할 때 사용한다.
- `tail -f`는 새로운 로그를 실시간으로 확인할 때 사용한다.
- HTTP `200`은 요청이 정상 처리됐다는 뜻이다.
- HTTP `304`는 파일이 변경되지 않아 브라우저 캐시를 사용할 수 있다는 뜻이다.
- `systemctl stop`으로 서비스를 중지할 수 있다.
- `systemctl start`로 서비스를 다시 시작할 수 있다.
- `systemctl status`로 서비스 실행 상태와 자동 시작 여부를 확인할 수 있다.
- 장애 복구 후에는 브라우저와 서비스 상태를 모두 확인해야 한다.

---

## 11. 문제 해결 기록

### 문제: 로그 파일을 열 수 없다는 오류 발생

로그 명령어를 입력하는 과정에서 경로 중간에 공백이 들어가 다음과 같은 오류가 발생했다.

```text
cannot open
no files remaining
```

또한 `tail -f`에서 하이픈이 빠져 다음 오류가 발생했다.

```text
command not found
```

### 원인

Linux 경로에는 임의로 공백을 넣으면 안 되며, `-f` 옵션 앞에는 하이픈이 필요하다.

잘못된 형태:

```text
tail f /var /log /nginx /access .log
```

올바른 형태:

```bash
sudo tail -f /var/log/nginx/access.log
```

경로와 옵션을 정확하게 입력한 후 접속 로그가 실시간으로 표시되는 것을 확인했다.

---

## 12. 장애 대응 절차 정리

이번 실습을 통해 다음과 같은 기본 장애 대응 절차를 연습했다.

```text
1. 사용자가 웹사이트 접속 장애를 보고
2. 브라우저에서 장애 현상 재현
3. systemctl로 서비스 상태 확인
4. access.log와 error.log 확인
5. Nginx 서비스 시작 또는 재시작
6. 서비스 상태가 active인지 확인
7. 브라우저에서 웹페이지 정상 동작 확인
8. 로그를 통해 정상 요청 확인
```

---

## 13. 다음 실습 계획

- Linux 파일 소유자와 권한 확인
- `chmod`, `chown` 명령어 실습
- 권한 문제를 일부러 만들고 복구
- Bash 서버 상태 점검 스크립트 작성
- Nginx 상태를 자동으로 확인하는 스크립트 작성
- 점검 결과를 로그 파일로 저장

---


# Day 3 - SSH 원격 접속 및 UFW 방화벽 설정

## 1. 실습 목표

- Windows에서 Ubuntu Server에 SSH로 원격 접속
- VirtualBox의 SSH 포트 포워딩 설정
- UFW 방화벽 활성화
- SSH와 HTTP에 필요한 포트만 허용
- Linux 서버의 CPU 및 메모리 상태 확인

---

## 2. SSH란?

SSH는 `Secure Shell`의 약자로, 다른 컴퓨터에서 Linux 서버에 안전하게 접속해 명령어를 실행할 수 있게 해주는 방식이다.

이번 실습에서는 Ubuntu 가상머신 화면을 직접 조작하지 않고, Windows PowerShell에서 Ubuntu 서버에 접속했다.

```text
Windows PowerShell
        ↓
SSH 연결
        ↓
VirtualBox 포트 포워딩
        ↓
Ubuntu Server
```

---

## 3. VirtualBox SSH 포트 포워딩 설정

Ubuntu 가상머신은 NAT 네트워크를 사용하고 있기 때문에 Windows에서 직접 `10.0.2.15`의 22번 포트로 접속하면 연결 시간이 초과되었다.

```text
Connection timed out
```

이 문제를 해결하기 위해 VirtualBox에 SSH용 포트 포워딩 규칙을 추가했다.

설정 경로:

```text
VirtualBox
→ home-idc-ubuntu 선택
→ 설정
→ 네트워크
→ 어댑터 1
→ 고급
→ 포트 포워딩
```

추가한 규칙:

| 설정 | 값 |
|---|---|
| 이름 | ssh |
| 프로토콜 | TCP |
| 호스트 IP | 127.0.0.1 |
| 호스트 포트 | 2222 |
| 게스트 IP | 공란 또는 10.0.2.15 |
| 게스트 포트 | 22 |

### 포트 포워딩 의미

Windows의 `2222` 포트로 들어온 요청을 Ubuntu 서버의 SSH 포트인 `22`번으로 전달한다.

```text
Windows 127.0.0.1:2222
        ↓
VirtualBox 포트 포워딩
        ↓
Ubuntu Server 10.0.2.15:22
```

---

## 4. Windows PowerShell에서 SSH 접속

Windows PowerShell을 실행하고 다음 명령어로 Ubuntu 서버에 접속했다.

```powershell
ssh -p 2222 sungwoo@127.0.0.1
```

각 항목의 의미:

- `ssh`: SSH 원격 접속 명령어
- `-p 2222`: Windows에서 접속할 포트 번호
- `sungwoo`: Ubuntu 사용자 이름
- `127.0.0.1`: 현재 Windows PC를 가리키는 주소

최초 접속 시 서버를 신뢰할 것인지 묻는 메시지가 표시됐다.

```text
Are you sure you want to continue connecting?
```

다음과 같이 입력했다.

```text
yes
```

Ubuntu 계정 비밀번호를 입력한 후 다음과 같은 프롬프트가 표시되어 원격 접속에 성공했다.

```text
sungwoo@home-idc-ubuntu
```

---

## 5. SSH 접속 후 서버 IP 확인

원격 접속한 PowerShell에서 다음 명령어를 실행했다.

```bash
hostname -I
```

출력된 Ubuntu 가상머신 IP 주소:

```text
10.0.2.15
```

이를 통해 Windows PowerShell에서 실제 Ubuntu 서버에 접속해 명령어를 실행하고 있음을 확인했다.

---

## 6. UFW 방화벽 상태 확인

Ubuntu의 방화벽 상태를 확인했다.

```bash
sudo ufw status
```

출력 결과:

```text
Status: inactive
```

`inactive`는 UFW 방화벽이 아직 활성화되지 않았다는 뜻이다.

---

## 7. SSH 포트 허용

방화벽을 활성화하기 전에 원격 접속에 사용하는 SSH 포트를 먼저 허용했다.

```bash
sudo ufw allow 22/tcp
```

SSH는 기본적으로 TCP 22번 포트를 사용한다.

SSH 포트를 허용하지 않고 방화벽부터 활성화하면 원격 접속이 차단될 수 있으므로, 먼저 SSH 규칙을 추가하는 것이 중요하다.

---

## 8. HTTP 웹 서버 포트 허용

Nginx 웹 서버 접속에 필요한 HTTP 80번 포트를 허용했다.

```bash
sudo ufw allow 80/tcp
```

HTTP 웹 서비스는 기본적으로 TCP 80번 포트를 사용한다.

---

## 9. UFW 방화벽 활성화

필요한 포트를 허용한 후 UFW 방화벽을 활성화했다.

```bash
sudo ufw enable
```

출력 결과:

```text
Firewall is active and enabled on system startup
```

이는 방화벽이 즉시 활성화되었으며 Ubuntu 서버를 재부팅해도 자동으로 실행된다는 뜻이다.

---

## 10. 방화벽 규칙 확인

현재 적용된 방화벽 규칙을 번호와 함께 확인했다.

```bash
sudo ufw status numbered
```

확인된 규칙:

```text
22/tcp
80/tcp
22/tcp (v6)
80/tcp (v6)
```

IPv4와 IPv6 규칙이 각각 표시되므로 총 네 개의 규칙이 나타나는 것은 정상이다.

현재 서버에서 허용한 주요 포트:

| 포트 | 용도 |
|---|---|
| TCP 22 | SSH 원격 접속 |
| TCP 80 | Nginx HTTP 웹 서비스 |

---

## 11. 서버 CPU 및 프로세스 상태 확인

다음 명령어를 실행해 CPU 사용률, 메모리 사용량, 실행 중인 프로세스를 실시간으로 확인했다.

```bash
top
```

`top` 화면에서는 다음 정보를 확인할 수 있다.

- CPU 사용률
- 메모리 사용량
- 시스템 실행 시간
- 실행 중인 프로세스
- 프로세스별 자원 사용량

`top` 화면을 종료할 때는 다음 키를 사용했다.

```text
q
```

---

## 12. 서버 메모리 상태 확인

다음 명령어로 서버의 메모리 사용 상태를 확인했다.

```bash
free -h
```

`-h` 옵션은 메모리 용량을 사람이 읽기 쉬운 MB 또는 GB 단위로 표시한다.

주요 항목:

| 항목 | 의미 |
|---|---|
| total | 전체 메모리 용량 |
| used | 현재 사용 중인 메모리 |
| free | 사용하지 않는 메모리 |
| available | 새 프로그램이 사용할 수 있는 메모리 |
| swap | 메모리가 부족할 때 디스크를 대신 사용하는 공간 |

---

## 13. 오늘 배운 내용

- SSH를 사용하면 다른 컴퓨터에서 Linux 서버를 원격으로 관리할 수 있다.
- VirtualBox NAT 환경에서는 포트 포워딩을 이용해 SSH에 접속할 수 있다.
- Ubuntu SSH의 기본 포트는 TCP 22번이다.
- Nginx HTTP 웹 서비스의 기본 포트는 TCP 80번이다.
- UFW는 Ubuntu에서 사용하는 방화벽 관리 도구다.
- 방화벽을 켜기 전에 SSH 포트를 먼저 허용해야 원격 접속이 끊기지 않는다.
- 방화벽에서는 서비스 운영에 필요한 포트만 허용하는 것이 안전하다.
- `top` 명령어로 CPU와 프로세스를 실시간으로 확인할 수 있다.
- `free -h` 명령어로 메모리와 Swap 사용량을 확인할 수 있다.

---

## 14. 문제 해결 기록

### 문제 1: SSH 연결 시간 초과

처음에는 Windows PowerShell에서 다음과 같이 가상머신 IP로 직접 접속했다.

```powershell
ssh sungwoo@10.0.2.15
```

그러나 다음 오류가 발생했다.

```text
Connection timed out
```

### 원인

VirtualBox 가상머신이 NAT 네트워크를 사용하고 있어 Windows 호스트에서 가상머신의 22번 포트로 직접 접속할 수 없었다.

### 해결

VirtualBox에서 호스트 포트 `2222`를 게스트 포트 `22`로 전달하는 포트 포워딩 규칙을 만들었다.

그 후 다음 명령어로 접속했다.

```powershell
ssh -p 2222 sungwoo@127.0.0.1
```

SSH 원격 접속에 정상적으로 성공했다.

---

### 문제 2: UFW 상태를 Active로 잘못 확인

처음에는 UFW 상태 출력의 `inactive`를 `active`로 잘못 읽었다.

다시 확인한 결과 방화벽이 비활성화된 상태임을 확인했다.

```bash
sudo ufw status
```

이후 SSH와 HTTP 포트를 허용하고 방화벽을 활성화했다.

---

## 15. 보안상 주의할 점

GitHub 공개 저장소에는 다음 정보를 올리지 않는다.

- Ubuntu 로그인 비밀번호
- SSH 개인 키
- AWS Access Key
- AWS Secret Access Key
- 실제 회사 서버 IP
- 개인정보 및 인증 정보

이번 프로젝트의 `10.0.2.15`와 `127.0.0.1`은 개인 실습 환경의 로컬 주소이므로 공개해도 외부에서 직접 접속할 수 없다.

---

## 16. 다음 실습 계획

- Linux 파일 및 디렉터리 권한 실습
- Nginx 접속 로그와 오류 로그 확인
- 웹 서버를 일부러 중지하고 장애 원인 확인
- Nginx 서비스 재시작 및 복구
- Bash 기반 서버 상태 점검 스크립트 작성
- Cron을 이용한 자동 실행 설정

---


## DAY 2 
# Day 2 - Nginx 기본 웹페이지 수정

## 1. 실습 목표

- Nginx가 제공하는 웹페이지 파일 위치 확인
- 원본 HTML 파일 백업
- Nano 편집기를 이용한 웹페이지 수정
- 브라우저에서 변경 결과 확인

---

## 2. Nginx 웹페이지 파일 확인

Nginx의 기본 웹페이지 파일이 저장된 디렉터리를 확인했다.

```bash
ls -l /var/www/html
```

확인된 기본 웹페이지 파일:

```text
index.nginx-debian.html
```

`/var/www/html`은 Nginx가 웹페이지 파일을 불러오는 기본 디렉터리다.

---

## 3. 원본 HTML 파일 백업

웹페이지를 수정하기 전에 문제가 발생했을 때 복구할 수 있도록 원본 파일을 백업했다.

```bash
sudo cp /var/www/html/index.nginx-debian.html /var/www/html/index.nginx-debian.html.bak
```

백업 파일이 정상적으로 생성되었는지 확인했다.

```bash
ls -l /var/www/html
```

확인된 백업 파일:

```text
index.nginx-debian.html.bak
```

### cp 명령어 의미

`cp`는 파일을 복사할 때 사용하는 Linux 명령어다.

```text
원본 파일 → 백업 파일
```

---

## 4. Nano 편집기로 HTML 파일 수정

다음 명령어를 사용해 Nginx 기본 웹페이지를 수정했다.

```bash
sudo nano /var/www/html/index.nginx-debian.html
```

HTML 파일에서 기존 `Welcome to nginx!` 문구 아래에 다음 내용을 추가했다.

```html
<h1>Home IDC Lab Day 2</h1>
```

Nano 편집기에서 다음 키를 사용해 저장하고 종료했다.

```text
Ctrl + O : 파일 저장
Enter    : 파일 이름 확인
Ctrl + X : Nano 편집기 종료
```

---

## 5. 브라우저에서 변경 결과 확인

Windows 웹 브라우저에서 다음 주소에 접속했다.

```text
http://127.0.0.1:8080
```

페이지를 새로고침한 결과 다음 문구가 정상적으로 표시됐다.

```text
Home IDC Lab Day 2
```

이를 통해 수정한 HTML 파일을 Nginx가 정상적으로 사용자에게 제공하는 것을 확인했다.

---

## 6. 웹페이지 요청 흐름

```text
Windows 웹 브라우저
        ↓
127.0.0.1:8080
        ↓
VirtualBox 포트 포워딩
        ↓
Ubuntu Server의 80번 포트
        ↓
Nginx
        ↓
/var/www/html/index.nginx-debian.html
```

---

## 7. 오늘 배운 내용

- Nginx의 기본 웹페이지는 `/var/www/html` 디렉터리에 저장된다.
- 실제 파일을 수정하기 전에 원본 파일을 백업하는 것이 중요하다.
- `cp` 명령어로 파일을 복사하고 백업할 수 있다.
- Nano는 Linux 터미널에서 사용하는 텍스트 편집기다.
- HTML의 `<h1>` 태그는 큰 제목을 표시할 때 사용한다.
- 웹페이지 파일을 수정하면 Nginx를 재설치하지 않아도 브라우저 새로고침으로 결과를 확인할 수 있다.
- 서버 운영에서는 변경 전 백업과 변경 후 정상 동작 확인이 중요하다.

---

## 8. 문제 해결 및 주의 사항

처음에는 기본 웹페이지 파일명을 `index.html`로 예상했지만, 실제 Ubuntu Nginx 환경에서는 다음 파일명이 사용되고 있었다.

```text
index.nginx-debian.html
```

따라서 파일을 수정하기 전에 다음 명령어로 실제 파일명을 먼저 확인하는 것이 중요하다.

```bash
ls -l /var/www/html
```

---

## 9. 다음 실습 계획

- Linux 파일과 디렉터리 권한 확인
- Nginx 로그 확인
- Windows에서 SSH로 Ubuntu 서버 접속
- UFW 방화벽 설정
- 간단한 서버 장애 발생 및 복구 실습

---


## DAY 1 -Ubuntu Server and Nginx

# hhome-idc-lab
Linux, VirtualBox, Nginx home server practice

VirtualBox를 이용해 Ubuntu Linux 서버를 구축하고,  
웹 서버 운영·모니터링·백업·AWS 연동을 연습하는 홈랩 프로젝트입니다.

IDC 서버 운영/관리 직무에 필요한 Linux 서버 구축, 네트워크 설정, 장애 대응, 자동화 경험을 쌓는 것이 목표입니다.

---

## 프로젝트 목표

- Ubuntu Linux 서버 설치 및 운영
- Linux 명령어와 서비스 관리 연습
- Nginx 웹 서버 구축
- VirtualBox 네트워크 및 포트 포워딩 이해
- 서버 모니터링 환경 구축
- 백업 파일 AWS S3 업로드 자동화
- 장애 발생 및 복구 과정 기록

---

# Day 1 - Ubuntu Server 및 Nginx 구축

## 1. 실습 환경

- Host OS: Windows
- 가상화 프로그램: Oracle VirtualBox
- Guest OS: Ubuntu Server
- CPU: 2 Core
- Memory: 4GB
- Virtual Disk: 25GB
- Web Server: Nginx

---

## 2. Ubuntu Server 가상머신 생성

VirtualBox에서 새로운 가상머신을 생성했다.

가상머신 이름:

```text
home-idc-ubuntu
```

Ubuntu Server ISO 파일을 연결한 후 운영체제를 설치했다.

설치 과정에서 다음 설정을 적용했다.

- Ubuntu Pro: 사용하지 않음
- OpenSSH Server: 설치
- Featured Server Snaps: 선택하지 않음
- Linux 사용자 계정 생성
- 서버 호스트명 설정

---

## 3. 서버 정보 확인

로그인 후 다음 명령어를 사용해 사용자, 서버 이름, IP 주소를 확인했다.

```bash
whoami
hostname
hostname -I
```

확인된 가상머신 내부 IP 주소:

```text
10.0.2.15
```

`10.0.2.15`는 VirtualBox의 NAT 네트워크에서 가상머신에 할당된 내부 IP 주소다.

---

## 4. Ubuntu 패키지 업데이트

설치된 패키지 목록을 갱신했다.

```bash
sudo apt update
```

업데이트 가능한 패키지를 실제로 업그레이드했다.

```bash
sudo apt upgrade -y
```

### 명령어 의미

- `sudo`: 관리자 권한으로 명령 실행
- `apt`: Ubuntu 패키지 관리 도구
- `update`: 설치 가능한 패키지 목록 갱신
- `upgrade`: 설치된 패키지 업데이트
- `-y`: 설치 확인 질문에 자동으로 Yes 선택

---

## 5. Nginx 웹 서버 설치

다음 명령어로 Nginx를 설치했다.

```bash
sudo apt install nginx -y
```

Nginx 서비스 상태를 확인했다.

```bash
systemctl status nginx
```

다음 상태가 표시되어 Nginx가 정상적으로 실행 중인 것을 확인했다.

```text
active (running)
```

상태 확인 화면에서 빠져나올 때는 `q` 키를 사용한다.

---

## 6. Ubuntu 내부에서 웹 서버 확인

Ubuntu 서버 내부에서 다음 명령어를 실행했다.

```bash
curl localhost
```

Nginx 기본 페이지의 HTML 코드가 출력되어 웹 서버가 정상적으로 응답하는 것을 확인했다.

### curl의 역할

`curl`은 터미널에서 웹 서버에 요청을 보내고 응답을 확인하는 도구다.

---

## 7. VirtualBox 포트 포워딩 설정

VirtualBox 가상머신은 NAT 네트워크를 사용하기 때문에 Windows 브라우저에서 Ubuntu 서버에 직접 접속하기 위한 포트 포워딩을 설정했다.

설정 경로:

```text
VirtualBox
→ home-idc-ubuntu 선택
→ 설정
→ 네트워크
→ 어댑터 1
→ 고급
→ 포트 포워딩
```

포트 포워딩 규칙:

| 설정 | 값 |
|---|---|
| 이름 | nginx |
| 프로토콜 | TCP |
| 호스트 IP | 127.0.0.1 |
| 호스트 포트 | 8080 |
| 게스트 IP | 10.0.2.15 또는 공란 |
| 게스트 포트 | 80 |

### 포트 포워딩 의미

Windows의 `8080` 포트로 들어온 요청을 Ubuntu 가상머신의 Nginx가 사용하는 `80` 포트로 전달한다.

```text
Windows 브라우저
127.0.0.1:8080
        ↓
VirtualBox 포트 포워딩
        ↓
Ubuntu Server
10.0.2.15:80
        ↓
Nginx
```

---

## 8. Windows 브라우저에서 접속 확인

Windows의 웹 브라우저에서 다음 주소로 접속했다.

```text
http://127.0.0.1:8080
```

브라우저에 다음 페이지가 나타나는 것을 확인했다.

```text
Welcome to nginx!
```

이를 통해 다음 통신 흐름이 정상적으로 작동하는 것을 확인했다.

```text
Windows → VirtualBox → Ubuntu Server → Nginx
```

---

## 9. 오늘 배운 내용

- VirtualBox를 이용하면 한 대의 PC 안에 별도의 가상 서버를 만들 수 있다.
- Ubuntu Server는 Linux 기반 서버 운영체제다.
- Nginx는 웹페이지와 웹 콘텐츠를 사용자에게 전달하는 웹 서버다.
- `systemctl` 명령어로 Linux 서비스를 확인하고 관리할 수 있다.
- `curl localhost`를 이용해 서버 내부에서 웹 서비스의 응답을 확인할 수 있다.
- VirtualBox NAT 환경에서는 포트 포워딩을 사용해 호스트 PC에서 가상머신 서비스에 접근할 수 있다.
- `127.0.0.1`은 현재 사용 중인 컴퓨터 자신을 가리키는 주소다.
- Nginx의 기본 HTTP 포트는 `80`이다.

---

## 10. 문제 해결 기록

### 문제

처음에 다음 명령어를 잘못 입력해 예상한 IP 주소가 나오지 않았다.

```bash
hostname -i
```

### 원인

소문자 `i`와 대문자 `I`는 서로 다른 옵션이다.

### 해결

다음과 같이 대문자 `I`를 사용했다.

```bash
hostname -I
```

그 결과 가상머신 IP 주소인 `10.0.2.15`를 확인할 수 있었다.

---

## 11. 다음 실습 계획

- Nginx 기본 웹페이지 수정
- Linux 파일 및 디렉터리 권한 실습
- SSH를 이용해 Windows에서 Ubuntu 서버에 접속
- UFW 방화벽 설정
- 서버 로그 확인
- Bash 백업 스크립트 작성
- Cron을 이용한 자동 백업
- AWS S3에 백업 파일 업로드
- CloudWatch를 이용한 모니터링 및 알림 구성
- GitHub에 구축 및 장애 해결 과정 기록

---

## 주의 사항

GitHub 공개 저장소에는 다음 정보를 올리지 않는다.

- Linux 로그인 비밀번호
- AWS Access Key
- AWS Secret Access Key
- 개인정보
- 민감한 내부 IP 또는 계정 정보
