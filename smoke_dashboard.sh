#!/usr/bin/env bash
# Smoke test du dashboard (conteneur ou serveur local).
# Usage : SENTINEL_INGEST_TOKEN=ci-token bash tests/smoke_dashboard.sh [URL]
# Le serveur testé doit avoir été lancé avec le même SENTINEL_INGEST_TOKEN.
set -euo pipefail
URL="${1:-http://localhost:3000}"
TOKEN="${SENTINEL_INGEST_TOKEN:-ci-token}"
fail() { echo "ECHEC : $1"; exit 1; }

for i in $(seq 1 30); do
  curl -fsS "$URL/api/health" >/dev/null 2>&1 && break
  [ "$i" = 30 ] && fail "/api/health ne répond pas"
  sleep 2
done
echo "OK  1 - le dashboard démarre et /api/health répond"

curl -fsS "$URL/api/telemetry" | grep -q '"history"' || fail "/api/telemetry ne renvoie pas de données"
echo "OK  2 - /api/telemetry renvoie un état (mode simulation sans capteur)"

BODY='{"temperature":24.5,"humidity":50,"gas":120,"presence":false}'
post() { curl -s -o /dev/null -w '%{http_code}' -X POST "$URL/api/telemetry" -H 'content-type: application/json' "$@"; }

[ "$(post -d "$BODY")" = 401 ] || fail "ingestion sans jeton non refusée (401 attendu)"
[ "$(post -H 'authorization: Bearer mauvais' -d "$BODY")" = 401 ] || fail "mauvais jeton non refusé (401 attendu)"
echo "OK  3 - l'ingestion sans jeton ou avec un mauvais jeton est refusée (401)"

[ "$(post -H "authorization: Bearer $TOKEN" -d "$BODY")" = 202 ] || fail "mesure valide non acceptée (202 attendu)"
[ "$(post -H "authorization: Bearer $TOKEN" -d '{"temperature":500,"gas":120,"presence":false}')" = 422 ] \
  || fail "mesure impossible non rejetée (422 attendu)"
echo "OK  4 - mesure valide acceptée (202), mesure aberrante rejetée (422)"
echo "Smoke test du dashboard : OK"
