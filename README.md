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
