# nginx-proxy NHN Deploy

이 디렉터리는 **NHN Deploy**에서 User Command로 사용할 스크립트를 포함합니다.

## 전제

- 서버에는 **nginx-proxy 인스턴스 이미지**로 생성된 인스턴스가 있으며, `/opt/nginx-proxy`에 설정이 설치되어 있음.
- nginx 서비스는 `nginx.service`로 동작하며, 백엔드 업스트림은 `/opt/nginx-proxy/conf.d/backend.upstream.conf`에서 정의됨.

## User Command 설정 (NHN Deploy)

- **Run As**: nginx reload 권한이 있는 계정 (예: `root`).
- **User Command** 예시:
  - **스크립트 안에서 export**: `apply-env-and-restart.sh` 상단의 `# === 여기서 환경변수 export (선택) ===` 아래 주석을 해제하고 값을 넣은 뒤 실행.
  - **파일로 한 번에 로드** (export 없이):
    ```bash
    sudo /opt/nginx-proxy/deploy/apply-env-and-restart.sh --env-file /path/to/deploy.env
    ```
  - **셸에서 export 후 실행**:
    ```bash
    export BACKEND_UPSTREAM="로드밸런서IP:포트"
    export LOKI_URL="http://loki:3100"
    export PROMETHEUS_PUSHGATEWAY_URL="http://pushgateway:9091"
    sudo /opt/nginx-proxy/deploy/apply-env-and-restart.sh
    ```
  - **stdin으로 .env 전체 덮어쓰기**:
    ```bash
    sudo /opt/nginx-proxy/deploy/apply-env-and-restart.sh --stdin
    ```
  - **설정 변경 없이 재시작만**:
    ```bash
    sudo /opt/nginx-proxy/deploy/apply-env-and-restart.sh --restart-only
    ```

## 환경 변수 (저장 위치: `/opt/nginx-proxy/.env`)

Promtail·Pushgateway·Prometheus 관련 변수는 **같은 .env**에 두고, `apply-env-and-restart.sh` 실행 시 병합·반영됩니다.

| 변수 | 필수 | 설명 | 기본값 |
|------|------|------|--------|
| `BACKEND_UPSTREAM` | ✓ | 백엔드 주소 (IP 또는 호스트:포트) | `127.0.0.1:8000` |
| `LOKI_URL` | - | Loki URL (Promtail → 로그 전송) | - |
| `PROMETHEUS_PUSHGATEWAY_URL` | - | Pushgateway URL (node_exporter/nginx 메트릭 푸시) | - |
| `INSTANCE_IP` | - | 인스턴스 식별용 (메트릭/로그 라벨, 비우면 hostname -I 사용) | - |
| `PUSHGATEWAY_JOB` | - | Pushgateway job 라벨 | `nginx-proxy` |
| `OPT_DIR` | - | 설치 경로 | `/opt/nginx-proxy` |
| `ENV_FILE` | - | .env 경로 | `/opt/nginx-proxy/.env` |

## 배포 후 검증

같은 서버에서:

```bash
sudo /opt/nginx-proxy/deploy/verify-after-deploy.sh
```

원격에서 (프록시 IP로):

```bash
BASE_URL=http://프록시IP:80 ./deploy/verify-after-deploy.sh
```

## 502 Bad Gateway 나올 때

502는 **nginx가 백엔드(FastAPI)에 연결하지 못할 때** 발생합니다. 프록시 서버(133.186.219.101)에 SSH 접속한 뒤 아래 순서로 확인하세요.

1. **백엔드 주소가 올바른지**
   ```bash
   cat /opt/nginx-proxy/conf.d/backend.upstream.conf
   ```
   `server` 뒤에 **실제 FastAPI가 떠 있는 IP:포트**가 있어야 합니다 (예: `10.0.0.5:8000`). `__BACKEND_UPSTREAM__` 그대로면 설정이 적용된 적이 없음.

2. **.env에 설정된 값**
   ```bash
   grep BACKEND_UPSTREAM /opt/nginx-proxy/.env
   ```

3. **프록시 → 백엔드 연결 테스트**  
   위에서 확인한 IP와 포트(예: 8000)로:
   ```bash
   curl -s -o /dev/null -w "%{http_code}" http://백엔드IP:8000/docs
   # 또는
   curl -s -o /dev/null -w "%{http_code}" http://백엔드IP:8000/
   ```
   `200`이 나와야 합니다. 연결 실패(000, timeout)면 **네트워크/방화벽** 문제(서브넷·ACG·보안 그룹에서 프록시 → 백엔드 포트 허용 여부) 또는 **백엔드 서버에서 FastAPI 미기동**을 의심하세요.

4. **수정 후 적용**
   ```bash
   export BACKEND_UPSTREAM="실제_백엔드_IP:8000"
   sudo /opt/nginx-proxy/deploy/apply-env-and-restart.sh
   ```

**요약**: `BACKEND_UPSTREAM`이 FastAPI가 실제로 떠 있는 서버의 IP:포트를 가리키고, 프록시 서버에서 그 주소로 접속 가능해야 합니다.

---

## 참고

- **photo-api** 공유 링크: `/share/{token}` 경로가 그대로 백엔드(photo-api)로 프록시됨.
- **클라이언트 IP**: `X-Forwarded-For`, `X-Real-IP` 헤더로 무조건 전달됨.
- **SSL**: 추후 `conf/nginx-proxy.conf` 하단의 HTTPS 블록 주석 해제 후 인증서 경로 설정.
