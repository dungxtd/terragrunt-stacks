#!/usr/bin/env bash
# Usage: vault-portforward.sh <start|stop> [port]
set -euo pipefail

ACTION=${1:-start}
PORT=${2:-18200}
PID_FILE=/tmp/vault-pf.pid
LOG_FILE=/tmp/vault-pf.log

vault_health() {
  curl -s -o /dev/null -w "%{http_code}" "http://localhost:${PORT}/v1/sys/health" 2>/dev/null || echo 0
}

start() {
  if lsof -i :"${PORT}" >/dev/null 2>&1; then
    CODE=$(vault_health)
    case "$CODE" in
      200|429) echo "vault port-forward already healthy on :${PORT} (HTTP $CODE)"; return 0 ;;
      503)     echo "vault sealed on :${PORT} — waiting for KMS auto-unseal..." ;;
      *)       echo "port :${PORT} open but vault unhealthy (HTTP $CODE)" >&2; exit 1 ;;
    esac
  fi

  if ! kubectl get pods -n vault -l app.kubernetes.io/name=vault \
      --field-selector=status.phase=Running --no-headers 2>/dev/null | grep -q .; then
    echo "no running vault pod — port-forward skipped"
    return 0
  fi

  kubectl port-forward svc/vault "${PORT}":8200 -n vault >"${LOG_FILE}" 2>&1 &
  echo $! > "${PID_FILE}"

  for i in $(seq 1 60); do
    CODE=$(vault_health)
    case "$CODE" in
      200|429) echo "vault ready (${i}s, HTTP $CODE)"; return 0 ;;
      503)     printf "(%ds) vault sealed — waiting for KMS auto-unseal...\n" "$i" ;;
      *)       printf "(%ds) waiting (HTTP %s)...\n" "$i" "$CODE" ;;
    esac
    if ! kill -0 "$(cat "${PID_FILE}")" 2>/dev/null; then
      echo "vault port-forward process died:" >&2
      cat "${LOG_FILE}" >&2
      exit 1
    fi
    sleep 1
  done

  echo "vault not ready after 60s — port-forward log:" >&2
  cat "${LOG_FILE}" >&2
  exit 1
}

stop() {
  if [ ! -f "${PID_FILE}" ]; then
    echo "no PID file — port-forward was not started by this script"
    return 0
  fi
  PID=$(cat "${PID_FILE}")
  kill "$PID" 2>/dev/null && echo "vault port-forward stopped (PID $PID)" || true
  rm -f "${PID_FILE}"
}

case "$ACTION" in
  start) start ;;
  stop)  stop  ;;
  *)     echo "usage: $0 <start|stop> [port]" >&2; exit 1 ;;
esac
