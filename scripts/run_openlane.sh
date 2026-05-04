#!/usr/bin/env bash
# Lance le flow OpenLane via Docker → produit le GDSII final.
# Pré-requis : Docker, et OpenLane cloné dans $OPENLANE_DIR (par défaut ~/OpenLane).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OPENLANE_DIR="${OPENLANE_DIR:-$HOME/OpenLane}"

if [[ ! -d "$OPENLANE_DIR" ]]; then
    echo "OpenLane introuvable. Cloner avec :"
    echo "  git clone https://github.com/The-OpenROAD-Project/OpenLane $OPENLANE_DIR"
    echo "  cd $OPENLANE_DIR && make"
    exit 1
fi

# Vérifier picorv32
if [[ ! -f "$ROOT/ext/picorv32/picorv32.v" ]]; then
    echo "PicoRV32 manquant — exécution de 'make deps'..."
    (cd "$ROOT" && make deps)
fi

cd "$OPENLANE_DIR"
make mount \
    DESIGN_DIR="$ROOT/openlane/agri_drone_soc" \
    docker_command="flow.tcl -design $ROOT/openlane/agri_drone_soc -run_path $ROOT/runs -tag sahel1 -overwrite"

# Récupérer le GDS final
LATEST="$ROOT/runs/sahel1/results/final/gds/agri_drone_soc.gds"
if [[ -f "$LATEST" ]]; then
    echo "✓ GDSII : $LATEST"
    ls -lh "$LATEST"
else
    echo "✗ GDSII non produit. Voir runs/sahel1/logs/."
    exit 1
fi
