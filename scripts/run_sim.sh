#!/usr/bin/env bash
# Lance toutes les simulations Icarus et affiche un résumé PASS/FAIL.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build
TBS=(pwm ndvi aes uart)
PASS=0; FAIL=0
for tb in "${TBS[@]}"; do
    echo "=== sim-$tb ==="
    if make sim-$tb 2>&1 | tee build/sim-$tb.log | grep -qE "PASS|INFO"; then
        echo "[PASS] $tb"; PASS=$((PASS+1))
    else
        echo "[FAIL] $tb"; FAIL=$((FAIL+1))
    fi
done
echo
echo "Résumé : $PASS PASS / $FAIL FAIL"
[[ $FAIL -eq 0 ]]
