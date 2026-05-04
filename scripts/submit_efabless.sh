#!/usr/bin/env bash
# Prépare un tarball de soumission eFabless / ChipFoundry.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DATE=$(date +%Y%m%d_%H%M)
OUT="submission/sahel1-$DATE"
mkdir -p "$OUT"

# 1. Vérifs préalables
echo "→ Lint Verilator..."
make lint

echo "→ Simulations..."
bash scripts/run_sim.sh

# 2. GDS
GDS="runs/sahel1/results/final/gds/agri_drone_soc.gds"
if [[ ! -f "$GDS" ]]; then
    echo "ERREUR : $GDS absent. Lance d'abord scripts/run_openlane.sh"
    exit 1
fi

# 3. Copie des artefacts
cp -r info.yaml README.md LICENSE rtl docs openlane firmware "$OUT/"
cp "$GDS" "$OUT/"
cp -r runs/sahel1/reports "$OUT/reports" 2>/dev/null || true
cp -r runs/sahel1/results/final "$OUT/final" 2>/dev/null || true

# 4. Archive
tar czf "$OUT.tar.gz" -C submission "$(basename $OUT)"
echo "✓ Tarball prêt : $OUT.tar.gz"
echo
echo "Étapes suivantes :"
echo "  1. Créer un compte sur https://platform.efabless.com"
echo "  2. Créer un projet 'agri_drone_soc' lié à un shuttle ChipIgnite ouvert"
echo "  3. Pousser le repo Git public (ou téléverser le tarball)"
echo "  4. Lancer le 'precheck' eFabless :"
echo "       docker run -v \$(pwd):/work efabless/mpw_precheck:latest ..."
echo "  5. Soumettre quand precheck OK."
