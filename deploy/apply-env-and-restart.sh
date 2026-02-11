#!/usr/bin/env bash
#
# NHN Deploy User Command용: BACKEND_UPSTREAM + Observability 변수 반영 후 nginx/Promtail/Pushgateway 재시작.
# 환경 변수 또는 /opt/nginx-proxy/.env 에서 읽어 backend.upstream.conf 생성·.env 병합·서비스 reload.
#
set -euo pipefail

OPT_DIR="${OPT_DIR:-/opt/nginx-proxy}"
ENV_FILE="${ENV_FILE:-$OPT_DIR/.env}"
CONF_DIR="${CONF_DIR:-$OPT_DIR/conf.d}"
TEMPLATE="${TEMPLATE:-$OPT_DIR/conf/backend.upstream.conf.template}"
BACKEND_CONF="${BACKEND_CONF:-$CONF_DIR/backend.upstream.conf}"
# 기본값 (수정 시 여기만 바꾸면 됨)
DEFAULT_BACKEND="${DEFAULT_BACKEND:-192.168.2.55:80}"
DEFAULT_LOKI_URL="${DEFAULT_LOKI_URL:-http://192.168.4.73:3100}"
DEFAULT_PUSHGATEWAY_URL="${DEFAULT_PUSHGATEWAY_URL:-http://192.168.4.73:9091}"

# .env에 쓸 수 있는 변수 (export 후 실행 시 병합됨)
ENV_KEYS=(
  BACKEND_UPSTREAM
  LOKI_URL
  PROMETHEUS_PUSHGATEWAY_URL
  INSTANCE_IP
  PUSHGATEWAY_JOB
)

# .env를 먼저 로드 (있으면) — 이후 스크립트 기본값이 비어 있는 것만 채움
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE" 2>/dev/null || true
  set +a
fi

# .env에 없거나 비어 있으면 상단 DEFAULT_* 변수 사용
BACKEND_UPSTREAM="${BACKEND_UPSTREAM:-$DEFAULT_BACKEND}"
LOKI_URL="${LOKI_URL:-$DEFAULT_LOKI_URL}"
PROMETHEUS_PUSHGATEWAY_URL="${PROMETHEUS_PUSHGATEWAY_URL:-$DEFAULT_PUSHGATEWAY_URL}"
INSTANCE_IP="${INSTANCE_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
export BACKEND_UPSTREAM LOKI_URL PROMETHEUS_PUSHGATEWAY_URL INSTANCE_IP

usage() {
  echo "Usage: export BACKEND_UPSTREAM=ip:port [LOKI_URL=...] ... && $0"
  echo "       $0 --env-file <파일>  # 파일 내용을 export 후 .env에 병합"
  echo "       $0 --stdin           # .env 전체를 stdin으로 덮어쓴 뒤 적용"
  echo "       $0 --restart-only    # 설정 변경 없이 서비스만 재시작"
  echo "       $0 --skip-observability-check  # Promtail/Pushgateway 필수 검사 생략 (비권장)"
  echo "       $0 --debug           # 각 명령 출력하며 실행 (오류 위치 확인용)"
  exit 0
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
fi

SKIP_OBSERVABILITY_CHECK=false
while [[ "${1:-}" == "--skip-observability-check" ]]; do
  SKIP_OBSERVABILITY_CHECK=true
  shift
done

# --debug: 실행되는 명령 그대로 출력 (set -x)
if [[ "${1:-}" == "--debug" ]]; then
  set -x
  shift
fi

# --env-file: 해당 파일을 source 한 뒤 .env 병합 (export 없이 파일로 설정 가능)
if [[ "${1:-}" == "--env-file" ]] && [[ -n "${2:-}" ]]; then
  if [[ -f "$2" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$2" 2>/dev/null || true
    set +a
    echo "Loaded env from $2"
  else
    echo "Error: file not found: $2" >&2
    exit 1
  fi
  shift 2
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
else
  # export된 값 + 기존 .env 병합하여 .env 갱신
  echo "[1/5] .env 병합 중..."
  tmp=$(mktemp)
  for key in "${ENV_KEYS[@]}"; do
    val="${!key:-}"
    if [[ -z "$val" ]] && [[ -f "$ENV_FILE" ]]; then
      line=$(sudo grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -1) || true
      if [[ -n "$line" ]]; then
        val="${line#*=}"
        val="${val#\"}"; val="${val%\"}"
      fi
    fi
    if [[ -n "$val" ]]; then
      val_escaped="${val//$'\n'/ }"
      val_escaped="${val_escaped//\"/\\\"}"
      echo "${key}=\"${val_escaped}\"" >> "$tmp"
    fi
  done
  if [[ -s "$tmp" ]]; then
    sudo cp -f "$tmp" "$ENV_FILE"
    echo "  Written env to $ENV_FILE"
  fi
  rm -f "$tmp"
fi

# Observability 필수: Promtail(로그), Pushgateway(node/nginx 메트릭) 무조건 전송
if [[ "$SKIP_OBSERVABILITY_CHECK" != "true" ]]; then
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE" 2>/dev/null || true
    set +a
  fi
  MISSING=""
  [[ -z "${LOKI_URL:-}" ]] && MISSING="${MISSING} LOKI_URL(Promtail)"
  [[ -z "${PROMETHEUS_PUSHGATEWAY_URL:-}" ]] && MISSING="${MISSING} PROMETHEUS_PUSHGATEWAY_URL(node/nginx메트릭)"
  if [[ -n "$MISSING" ]]; then
    echo "Error: Observability 전송 필수. 다음 변수를 설정하세요:${MISSING}" >&2
    echo "  LOKI_URL=http://loki:3100  # Promtail → Loki 로그" >&2
    echo "  PROMETHEUS_PUSHGATEWAY_URL=http://pushgateway:9091  # node_exporter/nginx 메트릭 푸시" >&2
    echo "  생략 시: $0 --skip-observability-check (비권장)" >&2
    exit 1
  fi
  echo "  Observability: LOKI_URL, PROMETHEUS_PUSHGATEWAY_URL 설정됨"
fi

echo "[2/5] backend.upstream.conf 생성..."
sudo mkdir -p "$CONF_DIR"
# 템플릿에서 placeholder 치환
if [[ -f "$TEMPLATE" ]]; then
  sed "s|__BACKEND_UPSTREAM__|$BACKEND_UPSTREAM|g" "$TEMPLATE" | sudo tee "$BACKEND_CONF" > /dev/null
  echo "Written $BACKEND_CONF (backend $BACKEND_UPSTREAM)"
else
  # 템플릿 없으면 최소 upstream만 작성
  echo "upstream photo_api_backend { server $BACKEND_UPSTREAM; keepalive 32; }" | sudo tee "$BACKEND_CONF" > /dev/null
  echo "  Written $BACKEND_CONF (no template)"
fi

echo "[3/5] nginx 설정 검사 및 reload..."
sudo nginx -t
sudo systemctl reload nginx
echo "  Nginx reloaded with BACKEND_UPSTREAM=$BACKEND_UPSTREAM"
sudo systemctl status nginx --no-pager || true

echo "[4/5] Promtail/Pushgateway 타이머 재시작..."
# Promtail: 먼저 disable → .env는 이미 [1/5]에서 반영됨 → LOKI_URL 있으면 enable+start
if systemctl list-unit-files --full promtail.service 2>/dev/null | grep -q promtail.service; then
  sudo systemctl stop promtail 2>/dev/null || true
  sudo systemctl disable promtail 2>/dev/null || true
  if [[ -n "${LOKI_URL:-}" ]]; then
    sudo systemctl enable promtail 2>/dev/null || true
    sudo systemctl start promtail 2>/dev/null || true
    echo "  Promtail enabled and started"
  else
    echo "  Promtail disabled (LOKI_URL not set)"
  fi
fi
if systemctl list-unit-files --full pushgateway-push.timer 2>/dev/null | grep -q pushgateway-push.timer; then
  sudo systemctl restart pushgateway-push.timer 2>/dev/null || true
  echo "  Restarted pushgateway-push.timer"
fi

echo "[5/5] 완료."
