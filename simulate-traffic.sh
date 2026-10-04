#!/usr/bin/env bash
# simulate-traffic.sh — Générateur de trafic pour le lab de formation BricoShop.
#
# But : produire des logs riches (parcours clients normaux + quelques anomalies)
#       afin de démontrer la détection d'anomalies et Logs Insights dans CloudWatch.
#
# Usage   : ./simulate-traffic.sh <URL_BASE> <DUREE_MINUTES>
# Exemple : ./simulate-traffic.sh https://app.secagent-lab.click 10
#
# N'utilise que curl. À lancer UNIQUEMENT contre ton propre site de formation.

set -uo pipefail

BASE="${1:?Usage: $0 <URL_BASE> <DUREE_MINUTES>}"
MINUTES="${2:?Usage: $0 <URL_BASE> <DUREE_MINUTES>}"
BASE="${BASE%/}"   # retire un éventuel slash final

RUN_ID="$(date +%s)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
END=$(( $(date +%s) + MINUTES * 60 ))

# curl commun : silencieux, pas de corps affiché, timeout court
CURL=(curl -s -o /dev/null --max-time 10)
UA="simulate-traffic/1.0 (lab)"
PRODUCTS=(1 2 3 4 5 6 7 8 9 10 11 12)

log() { echo "[$(date +%H:%M:%S)] $*"; }

# --- Un client fictif : inscription, navigation, panier, commande ---
user_session() {
  local n="$1"
  local jar="$TMP/user_${n}.cookies"
  local email="client${n}.run${RUN_ID}@exemple.fr"
  local pass="Passe${n}-2026"

  # 1re vague : inscription (connexion auto). Vagues suivantes : la session du
  # cookie jar est réutilisée, la ré-inscription produit juste un signup_failed.
  "${CURL[@]}" -c "$jar" -b "$jar" -A "$UA" -X POST "$BASE/api/signup" \
    -d "email=${email}&password=${pass}"

  # Navigation : accueil + catalogue + quelques fiches produits
  "${CURL[@]}" -b "$jar" -A "$UA" "$BASE/"
  "${CURL[@]}" -b "$jar" -A "$UA" "$BASE/api/products"
  local views=$(( RANDOM % 4 + 2 ))
  for ((v = 0; v < views; v++)); do
    local pid="${PRODUCTS[RANDOM % ${#PRODUCTS[@]}]}"
    "${CURL[@]}" -b "$jar" -A "$UA" "$BASE/api/products/$pid"
    sleep "0.$(( RANDOM % 9 + 1 ))"
  done

  # Panier : 1 à 3 lignes
  local adds=$(( RANDOM % 3 + 1 ))
  for ((a = 0; a < adds; a++)); do
    local pid="${PRODUCTS[RANDOM % ${#PRODUCTS[@]}]}"
    local qty=$(( RANDOM % 3 + 1 ))
    "${CURL[@]}" -b "$jar" -A "$UA" -X POST "$BASE/api/cart" \
      -d "productId=${pid}&quantity=${qty}"
    sleep "0.$(( RANDOM % 9 + 1 ))"
  done
  "${CURL[@]}" -b "$jar" -A "$UA" "$BASE/cart"

  # 70 % des sessions vont jusqu'à la commande (dont ~5 % échoueront côté serveur)
  if (( RANDOM % 10 < 7 )); then
    "${CURL[@]}" -b "$jar" -A "$UA" -X POST "$BASE/api/checkout"
  fi
}

# --- Anomalie : ~200 connexions échouées sur le même compte en ~1 min ---
# Simule un pic de login_failed, facilement repérable par la détection d'anomalies.
failed_login_burst() {
  local email="compte-cible.run${RUN_ID}@exemple.fr"
  log "Rafale d'anomalie : 200 connexions échouées sur ${email} (~60 s)"
  for ((i = 1; i <= 200; i++)); do
    "${CURL[@]}" -A "$UA" -X POST "$BASE/api/login" \
      -d "email=${email}&password=invalide-${i}" &
    # 20 requêtes en parallèle puis courte pause => ~200 étalées sur ~60 s
    if (( i % 20 == 0 )); then wait; sleep 6; fi
  done
  wait
}

# --- Bruit : quelques pages inexistantes (404) ---
not_found_noise() {
  local paths=(/promo-ete /categorie/jardin /produits/999 /ancienne-page \
               /api/products/9999 /blog/bricolage /favicon.ico)
  local p="${paths[RANDOM % ${#paths[@]}]}"
  "${CURL[@]}" -A "$UA" "$BASE$p"
}

# ------------------------------------------------------------------ boucle
log "Cible : ${BASE} — durée : ${MINUTES} min"

# La rafale d'anomalie se déclenche une fois, après 1 min de trafic normal.
( sleep 60; failed_login_burst ) &
BURST_PID=$!

round=0
while (( $(date +%s) < END )); do
  round=$(( round + 1 ))
  log "Vague ${round} : 20 clients..."
  for n in $(seq 1 20); do
    user_session "$n" &
  done
  for _ in 1 2 3; do not_found_noise & done
  wait
  sleep 3
done

wait "$BURST_PID" 2>/dev/null || true
log "Simulation terminée."
