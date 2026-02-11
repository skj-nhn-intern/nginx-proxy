#!/usr/bin/env bash
# node_exporter(9100) + nginx_exporter(9113) 메트릭을 수집해 Pushgateway로 전송
# PROMETHEUS_PUSHGATEWAY_URL, INSTANCE_IP 필요 (/.env 또는 환경변수)
set -euo pipefail

ENV_FILE="${ENV_FILE:-/opt/nginx-proxy/.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE" 2>/dev/null || true
  set +a
fi

URL="${PROMETHEUS_PUSHGATEWAY_URL:-}"
INSTANCE="${INSTANCE_IP:-$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'unknown')}"
JOB="${PUSHGATEWAY_JOB:-nginx-proxy}"

if [[ -z "$URL" ]]; then
  echo "PROMETHEUS_PUSHGATEWAY_URL not set, skip push" >&2
  exit 0
fi

URL="${URL%/}"
TMP_DIR="${TMP_DIR:-/tmp/nginx-proxy-push}"
mkdir -p "$TMP_DIR"
node_metrics="$TMP_DIR/node.$$"
nginx_metrics="$TMP_DIR/nginx.$$"
trap 'rm -f "$node_metrics" "$nginx_metrics"' EXIT

curl -sf --connect-timeout 2 --max-time 5 "http://127.0.0.1:9100/metrics" > "$node_metrics" 2>/dev/null || true
curl -sf --connect-timeout 2 --max-time 5 "http://127.0.0.1:9113/metrics" > "$nginx_metrics" 2>/dev/null || true

if [[ ! -s "$node_metrics" && ! -s "$nginx_metrics" ]]; then
  echo "No metrics collected from 9100 or 9113" >&2
  exit 0
fi

# Pushgateway: POST to /metrics/job/<job>/instance/<instance>
# Combine both metric outputs (blank line between to avoid duplicate # HELP in same group)
{
  [[ -s "$node_metrics" ]] && cat "$node_metrics"
  [[ -s "$node_metrics" && -s "$nginx_metrics" ]] && echo ""
  [[ -s "$nginx_metrics" ]] && cat "$nginx_metrics"
} | curl -sf --connect-timeout 5 --max-time 30 -X POST \
  --data-binary @- \
  "$URL/metrics/job/$JOB/instance/$INSTANCE" || true
