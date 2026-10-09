#!/usr/bin/env bash
# Test d'intégration du broker Mosquitto de Sentinel-X, avec VOTRE configuration réelle :
#   server/mosquitto/config/mosquitto.conf + acl, certificats de server/gen-certs.sh.
# Vérifie : TLS obligatoire, authentification, ACL par compte (esp-node, dashboard, vision).
# Lancement : bash tests/mqtt_tls_test.sh   (nécessite mosquitto, mosquitto-clients, openssl)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); chmod 755 "$T"
BROKER_PID=""
trap '[ -n "$BROKER_PID" ] && kill "$BROKER_PID" 2>/dev/null || true; rm -rf "$T"' EXIT
TLS=18883; PLAIN=11883
fail() { echo "ECHEC : $1"; exit 1; }

# 1) Certificats : on réutilise gen-certs.sh sur une copie (sans le chown sudo, sans toucher au dépôt)
mkdir -p "$T/server" "$T/firmware/include"
sed '/sudo chown/d' "$ROOT/server/gen-certs.sh" > "$T/server/gen-certs.sh"
( cd "$T/server" && bash gen-certs.sh 127.0.0.1 >/dev/null 2>&1 ) || fail "gen-certs.sh a échoué"
chmod 644 "$T"/server/certs/*

# 2) Configuration réelle, avec les chemins du conteneur remplacés par des chemins temporaires
mkdir -p "$T/conf" "$T/data"
cp "$ROOT/server/mosquitto/config/acl" "$T/conf/acl"
for u in esp-node dashboard vision; do
  mosquitto_passwd -b -c "$T/conf/passwd.new" "$u" "pw-$u" 2>/dev/null
  cat "$T/conf/passwd.new" >> "$T/conf/passwd"; rm -f "$T/conf/passwd.new"
done
sed -e "s#/mosquitto/config#$T/conf#g" -e "s#/mosquitto/certs#$T/server/certs#g" \
    -e "s#/mosquitto/data#$T/data#g" \
    -e "s#^listener 1883#listener $PLAIN 127.0.0.1#" -e "s#^listener 8883#listener $TLS 127.0.0.1#" \
    "$ROOT/server/mosquitto/config/mosquitto.conf" > "$T/conf/mosquitto.conf"
chmod -R a+rX "$T"

mosquitto -c "$T/conf/mosquitto.conf" > "$T/broker.log" 2>&1 &
BROKER_PID=$!
sleep 1
kill -0 "$BROKER_PID" 2>/dev/null || { cat "$T/broker.log"; fail "le broker ne démarre pas avec la config du projet"; }

CA="$T/server/certs/ca.crt"
tls_pub() { timeout 8 mosquitto_pub -h localhost -p $TLS --cafile "$CA" "$@"; }
tls_sub() { timeout 10 mosquitto_sub -h localhost -p $TLS --cafile "$CA" "$@"; }

# 3a) Chaîne réelle : esp-node publie en TLS -> le dashboard (listener interne) reçoit
mosquitto_sub -h 127.0.0.1 -p $PLAIN -u dashboard -P pw-dashboard -t 'sentinel/#' -C 1 -W 5 > "$T/a.txt" &
S=$!; sleep 1
tls_pub -u esp-node -P pw-esp-node -t sentinel/pyramide-01/telemetry -m '{"t":24.5,"h":52,"gas":120,"pir":false}'
wait $S || true
grep -q '"t":24.5' "$T/a.txt" || fail "la télémétrie de l'ESP n'arrive pas au dashboard"
echo "OK  1 - télémétrie esp-node (TLS) -> dashboard"

# 3b) Connexion anonyme refusée
! tls_pub -t sentinel/pyramide-01/telemetry -m x 2>/dev/null || fail "connexion anonyme acceptée"
echo "OK  2 - connexion sans identifiants refusée"

# 3c) Mauvais mot de passe refusé
! tls_pub -u esp-node -P mauvais -t sentinel/pyramide-01/telemetry -m x 2>/dev/null || fail "mauvais mot de passe accepté"
echo "OK  3 - mauvais mot de passe refusé"

# 3d) Pas de connexion en clair sur le port TLS
! timeout 5 mosquitto_pub -h localhost -p $TLS -u esp-node -P pw-esp-node -t sentinel/pyramide-01/telemetry -m x 2>/dev/null \
  || fail "connexion en clair acceptée sur le port TLS"
echo "OK  4 - connexion en clair refusée sur 8883"

# 3e) ACL : un esp-node compromis ne peut pas se faire passer pour la caméra
mosquitto_sub -h 127.0.0.1 -p $PLAIN -u dashboard -P pw-dashboard -t 'sentinel/vision/#' -C 1 -W 3 > "$T/b.txt" &
S=$!; sleep 1
tls_pub -u esp-node -P pw-esp-node -t sentinel/vision/detections -m '{"detections":[]}' || true
wait $S || true
[ ! -s "$T/b.txt" ] || fail "ACL : esp-node a pu publier sur sentinel/vision/"
echo "OK  5 - ACL : esp-node ne peut pas publier comme la caméra"

# 3f) ACL : le dashboard peut commander le buzzer, l'esp-node reçoit la commande
tls_sub -u esp-node -P pw-esp-node -t sentinel/pyramide-01/cmd -C 1 -W 5 > "$T/c.txt" &
S=$!; sleep 1
mosquitto_pub -h 127.0.0.1 -p $PLAIN -u dashboard -P pw-dashboard -t sentinel/pyramide-01/cmd -m '{"buzzer":"alarm"}'
wait $S || true
grep -q buzzer "$T/c.txt" || fail "la commande buzzer n'arrive pas à l'ESP"
echo "OK  6 - commande buzzer dashboard -> esp-node"

echo "Tous les tests MQTT (TLS + comptes + ACL) sont passés."
