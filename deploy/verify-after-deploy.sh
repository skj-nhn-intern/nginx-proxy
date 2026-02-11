#!/usr/bin/env bash
#
# 배포 후 검증: nginx 동작 및 프록시 응답 확인.
# apply-env-and-restart.sh 실행 후 같은 서버 또는 원격에서 실행.
#
# 사용 예:
#   로컬: sudo /opt/nginx-proxy/deploy/verify-after-deploy.sh
#   원격: BASE_URL=http://프록시IP:80 ./verify-after-deploy.sh
#
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:80}"
MAX_WAIT="${MAX_WAIT:-30}"
CURL_TIMEOUT="${CURL_TIMEOUT:-10}"

url_display="$BASE_URL"
ok()  { echo "  ✅ $*"; }
fail() { echo "  ❌ $*" >&2; }
warn() { echo "  ⚠️  $*"; }

# 1) nginx 서비스 상태
check_nginx() {
  echo "1. nginx 서비스 상태"
  if ! command -v systemctl &>/dev/null; then
    warn "systemctl 없음, 생략"
    return 0
  fi
  if ! systemctl is-active --quiet nginx 2>/dev/null; then
    fail "nginx가 active가 아님. sudo systemctl status nginx 확인"
    return 1
  fi
  ok "nginx active"
  return 0
}

# 2) 프록시 통해 /health (백엔드가 살아 있어야 200)
check_health() {
  echo "2. 프록시 헬스 ($url_display/health)"
  local waited=0 code body
  while true; do
    code=$(curl -s -o /tmp/nginx-proxy-health-$$.json -w "%{http_code}" --connect-timeout 5 --max-time "$CURL_TIMEOUT" "$BASE_URL/health" 2>/dev/null || echo "000")
    body=$(cat /tmp/nginx-proxy-health-$$.json 2>/dev/null || true)
    rm -f /tmp/nginx-proxy-health-$$.json

    if [[ "$code" == "200" ]] && echo "$body" | grep -q "healthy"; then
      ok "HTTP $code, body: $body"
      return 0
    fi
    if [[ "$code" == "502" || "$code" == "503" ]]; then
      warn "HTTP $code — 백엔드가 아직 없거나 다운일 수 있음 (BACKEND_UPSTREAM 확인)"
      return 0
    fi
    if [[ "$waited" -ge "$MAX_WAIT" ]]; then
      fail "헬스 실패 (HTTP $code, body: ${body:0:80})"
      return 1
    fi
    echo "    대기 중... (${waited}s/${MAX_WAIT}s)"
    sleep 2
    waited=$((waited + 2))
  done
}

# 3) /api/ prefix → 백엔드 루트 (예: /)
check_api_proxy() {
  echo "3. API 프록시 ($url_display/api/)"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time "$CURL_TIMEOUT" "$BASE_URL/api/" 2>/dev/null || echo "000")
  if [[ "$code" == "200" ]]; then
    ok "HTTP $code"
  elif [[ "$code" == "502" || "$code" == "503" ]]; then
    warn "HTTP $code — 백엔드 미연결일 수 있음"
  else
    fail "HTTP $code"
    return 1
  fi
  return 0
}

main() {
  echo "=== nginx-proxy 배포 검증: $url_display ==="
  failed=0
  check_nginx   || failed=1
  check_health  || failed=1
  check_api_proxy || true

  echo ""
  if [[ $failed -eq 0 ]]; then
    echo "✅ 배포 검증 완료."
    exit 0
  else
    echo "❌ 배포 검증 실패. 위 항목을 확인하세요."
    exit 1
  fi
}

main "$@"
