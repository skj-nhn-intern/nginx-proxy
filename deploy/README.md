# nginx-proxy NHN Deploy

이 디렉터리는 **NHN Deploy**에서 User Command로 사용할 스크립트를 포함합니다.

## 전제

- 서버에는 **nginx-proxy 인스턴스 이미지**로 생성된 인스턴스가 있으며, `/opt/nginx-proxy`에 설정이 설치되어 있음.
- nginx 서비스는 `nginx.service`로 동작하며, 백엔드 업스트림은 `/opt/nginx-proxy/conf.d/backend.upstream.conf`에서 정의됨.

## User Command 설정 (NHN Deploy)

- **Run As**: nginx reload 권한이 있는 계정 (예: `root`).
- **User Command** 예시:
  - 환경 변수로 백엔드만 설정 후 적용:
    ```bash
    export BACKEND_UPSTREAM="로드밸런서IP:포트"
    sudo /opt/nginx-proxy/deploy/apply-env-and-restart.sh
    ```
  - 표준입력으로 `.env` 전체 덮어쓴 뒤 적용:
    ```bash
    sudo /opt/nginx-proxy/deploy/apply-env-and-restart.sh --stdin
    ```
  - 설정 변경 없이 nginx만 reload:
    ```bash
    sudo /opt/nginx-proxy/deploy/apply-env-and-restart.sh --restart-only
    ```

## 환경 변수

| 변수 | 설명 | 기본값 |
|------|------|--------|
| `BACKEND_UPSTREAM` | 백엔드 주소 (IP 또는 호스트:포트) | `127.0.0.1:8000` |
| `LOKI_URL` | Loki URL (Promtail 로그 전송, 비우면 Promtail 미기동) | - |
| `PROMETHEUS_PUSHGATEWAY_URL` | Pushgateway URL (node/nginx 메트릭 푸시, 비우면 푸시 안 함) | - |
| `INSTANCE_IP` | 인스턴스 식별용 (메트릭/로그 라벨, 비우면 hostname -I 사용) | - |
| `OPT_DIR` | 설치 경로 | `/opt/nginx-proxy` |
| `ENV_FILE` | .env 경로 | `/opt/nginx-proxy/.env` |

## 배포 후 검증

같은 서버에서:

```bash
sudo /opt/nginx-proxy/deploy/verify-after-deploy.sh
```

원격에서 (프록시 IP로):

```bash
BASE_URL=http://프록시IP:80 ./deploy/verify-after-deploy.sh
```

## 참고

- **photo-api** 공유 링크: `/share/{token}` 경로가 그대로 백엔드(photo-api)로 프록시됨.
- **클라이언트 IP**: `X-Forwarded-For`, `X-Real-IP` 헤더로 무조건 전달됨.
- **SSL**: 추후 `conf/nginx-proxy.conf` 하단의 HTTPS 블록 주석 해제 후 인증서 경로 설정.
