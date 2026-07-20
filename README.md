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
