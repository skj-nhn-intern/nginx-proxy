# nginx-proxy

백엔드 API(photo-api 등) 앞단 **리버스 프록시** 서비스입니다. 추후 백엔드 API 로드밸런서 IP를 백엔드로 사용할 예정이며, **클라이언트 IP 추적**이 필수이고 **SSL**은 추후 추가 예정입니다.

## 역할

- **/api/** → 백엔드로 prefix 제거 후 전달 (`/api/auth/login` → `/auth/login`)
- **/share/** → photo-api 공유 링크 (인증 없이 앨범 공유)
- **/health** → 백엔드 헬스체크
- **/** → 기타 백엔드 루트
- **클라이언트 IP**: `X-Forwarded-For`, `X-Real-IP` 등으로 무조건 전달

## 디렉터리 구조

```
nginx-proxy/                    ← 이 레포 루트
├── .github/workflows/
│   └── build-and-test-image.yml   # 이미지 빌드 워크플로 (여기만 사용)
├── conf/
│   ├── nginx-proxy.conf
│   ├── backend.upstream.conf.template
│   └── env.example
├── deploy/
│   ├── apply-env-and-restart.sh
│   ├── verify-after-deploy.sh
│   └── README.md
├── scripts/ci/
│   └── ...
└── ...
```

## 인스턴스 이미지 빌드 (GitHub Actions)

- 워크플로: **`.github/workflows/build-and-test-image.yml`**
- GitHub Actions에서 NHN Cloud 인스턴스 생성·이미지 빌드에 필요한 시크릿은 팀/운영에서 설정.
- 생성 이미지 이름: `nginx-proxy-YYYYMMDD-HHMMSS`

## NHN Deploy

- User Command: `sudo /opt/nginx-proxy/deploy/apply-env-and-restart.sh`
- 배포 시 `BACKEND_UPSTREAM`(백엔드 로드밸런서 IP:포트)을 설정하면 `conf.d/backend.upstream.conf`가 갱신된 뒤 nginx가 reload 됨.
- 자세한 사용법: [deploy/README.md](deploy/README.md)

## 트래픽 효율

- **버퍼**: `proxy_buffer_size` 128k, `proxy_buffers` 4×256k, `proxy_busy_buffers_size` 256k
- **업스트림**: `keepalive 32` (backend.upstream.conf)
- **메인 nginx**: 이미지 빌드 시 `worker_connections` 65535, `worker_processes auto` 적용

## Observability (Promtail, Pushgateway)

이미지에는 다음이 포함됩니다.

| 구성요소 | 역할 |
|----------|------|
| **Promtail** | nginx access/error 로그 → Loki (`LOKI_URL` 설정 시 기동) |
| **node_exporter** | 호스트 메트릭 (9100) |
| **nginx-prometheus-exporter** | nginx stub_status 메트릭 (9113) |
| **pushgateway-push.timer** | 30초마다 node + nginx 메트릭을 Pushgateway로 푸시 (`PROMETHEUS_PUSHGATEWAY_URL` 설정 시) |

NHN Deploy 또는 `.env`에 `LOKI_URL`, `PROMETHEUS_PUSHGATEWAY_URL`, `INSTANCE_IP`를 설정하면 로그·메트릭이 전송됩니다.

## SSL (추후)

- `conf/nginx-proxy.conf` 하단에 HTTPS 서버 블록이 주석으로 포함되어 있음.
- 인증서 경로 설정 후 주석 해제하고, 필요 시 HTTP→HTTPS 리다이렉트 적용.
