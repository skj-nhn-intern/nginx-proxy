#!/usr/bin/env bash
#
# NHN Deploy User Command용: BACKEND_UPSTREAM 반영 후 nginx 설정 갱신 및 reload.
# 환경 변수 또는 /opt/nginx-proxy/.env 에서 BACKEND_UPSTREAM을 읽어
# backend.upstream.conf 를 생성하고 nginx를 reload 합니다.
#
set -euo pipefail

OPT_DIR="${OPT_DIR:-/opt/nginx-proxy}"
ENV_FILE="${ENV_FILE:-$OPT_DIR/.env}"
CONF_DIR="${CONF_DIR:-$OPT_DIR/conf.d}"
TEMPLATE="${TEMPLATE:-$OPT_DIR/conf/backend.upstream.conf.template}"
BACKEND_CONF="${BACKEND_CONF:-$CONF_DIR/backend.upstream.conf}"
DEFAULT_BACKEND="${DEFAULT_BACKEND:-127.0.0.1:8000}"

# .env 파일이 있으면 로드
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE" 2>/dev/null || true
  set +a
fi

BACKEND_UPSTREAM="${BACKEND_UPSTREAM:-$DEFAULT_BACKEND}"

usage() {
  echo "Usage: export BACKEND_UPSTREAM=ip:port && $0"
  echo "       $0 --stdin        # read .env content from stdin (전체 덮어씀 후 적용)"
  echo "       $0 --restart-only # upstream 설정은 그대로, nginx만 reload"
  exit 0
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
fi

if [[ "${1:-}" == "--restart-only" ]]; then
  echo "Reload only (no upstream rewrite)"
  sudo nginx -t && sudo systemctl reload nginx
  echo "Reloaded nginx"
  exit 0
fi

if [[ "${1:-}" == "--stdin" ]]; then
  sudo tee "$ENV_FILE" > /dev/null
  echo "Written .env from stdin to $ENV_FILE"
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE" 2>/dev/null || true
  set +a
  BACKEND_UPSTREAM="${BACKEND_UPSTREAM:-$DEFAULT_BACKEND}"
fi

sudo mkdir -p "$CONF_DIR"
# 템플릿에서 placeholder 치환
if [[ -f "$TEMPLATE" ]]; then
  sed "s|__BACKEND_UPSTREAM__|$BACKEND_UPSTREAM|g" "$TEMPLATE" | sudo tee "$BACKEND_CONF" > /dev/null
  echo "Written $BACKEND_CONF (backend $BACKEND_UPSTREAM)"
else
  # 템플릿 없으면 최소 upstream만 작성
  echo "upstream photo_api_backend { server $BACKEND_UPSTREAM; keepalive 32; }" | sudo tee "$BACKEND_CONF" > /dev/null
  echo "Written $BACKEND_CONF (no template)"
fi

sudo nginx -t
sudo systemctl reload nginx
echo "Nginx reloaded with BACKEND_UPSTREAM=$BACKEND_UPSTREAM"
sudo systemctl status nginx --no-pager || true

# Promtail(Pushgateway)·메트릭 푸시 타이머: .env 변경 시 재시작
if systemctl list-unit-files --full promtail.service 2>/dev/null | grep -q promtail.service; then
  sudo systemctl restart promtail 2>/dev/null || true
  echo "Restarted promtail (LOKI_URL/INSTANCE_IP 반영)"
fi
if systemctl list-unit-files --full pushgateway-push.timer 2>/dev/null | grep -q pushgateway-push.timer; then
  sudo systemctl restart pushgateway-push.timer 2>/dev/null || true
  echo "Restarted pushgateway-push.timer (PUSHGATEWAY/INSTANCE_IP 반영)"
fi
