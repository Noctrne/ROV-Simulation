#!/usr/bin/env bash
# ==============================================================================
# Script: start_sim.sh
# Purpose: Menjalankan Gazebo dengan world bawah air + obstacle course,
#          dengan pengaman agar tidak pernah ada dua server Gazebo sekaligus.
#
# Kenapa perlu pengaman:
#   `gz sim` mem-publish ke topik global /world/<nama_world>/pose/info.
#   Kalau ada dua server dengan world yang sama, GUI menerima DUA aliran pose.
#   Akibatnya: robot terlihat "fliker" / muncul dua robot di posisi berbeda,
#   dan kamera yang mengikuti robot membuat arena tampak ikut bergeser.
#
# Pemakaian:
#   ./scripts/start_sim.sh                        # bluerov2_heavy (8 thruster)
#   ./scripts/start_sim.sh bluerov2_underwater.world
#   ./scripts/start_sim.sh bluerov2_ping.world
# ==============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORLD_NAME="${1:-bluerov2_heavy_underwater.world}"

#------------------------------------------------------------------------------
# 1. Tolak jalan kalau sudah ada server Gazebo
#------------------------------------------------------------------------------
# CATATAN: proses `gz sim` sebenarnya bernama `ruby`, BUKAN `gz`.
#          Karena itu `pgrep -x gz` selalu kosong dan tidak berguna.
#          Pola yang benar adalah `-f '^gz sim'`.
RUNNING=$(pgrep -f '^gz sim' || true)
if [ -n "$RUNNING" ]; then
    echo "=========================================================="
    echo "[ERROR] Sudah ada server Gazebo yang berjalan:"
    ps -o pid,etime,args -p "$(echo "$RUNNING" | tr '\n' ',' | sed 's/,$//')" 2>/dev/null
    echo ""
    echo "Dua server dengan world yang sama akan membuat robot dobel/fliker."
    echo "Bersihkan dulu:"
    echo "    ./scripts/check_sim.sh"
    echo "  atau:"
    echo "    pkill -9 -f '^gz sim'"
    echo "=========================================================="
    exit 1
fi

#------------------------------------------------------------------------------
# 2. Cek world file
#------------------------------------------------------------------------------
WORLD_PATH="$REPO_DIR/worlds/$WORLD_NAME"
if [ ! -f "$WORLD_PATH" ]; then
    echo "[ERROR] World tidak ditemukan: $WORLD_PATH"
    echo "Pilihan yang tersedia:"
    ls -1 "$REPO_DIR/worlds"
    exit 1
fi

#------------------------------------------------------------------------------
# 3. Environment
#------------------------------------------------------------------------------
export GZ_SIM_RESOURCE_PATH="$REPO_DIR/models:$REPO_DIR/worlds:${GZ_SIM_RESOURCE_PATH:-}"
export GZ_SIM_SYSTEM_PLUGIN_PATH="$HOME/ardupilot_gazebo/build:${GZ_SIM_SYSTEM_PLUGIN_PATH:-}"

if [ ! -f "$HOME/ardupilot_gazebo/build/libArduPilotPlugin.so" ]; then
    echo "[WARN] libArduPilotPlugin.so tidak ditemukan di ~/ardupilot_gazebo/build"
    echo "       ROV tidak akan bisa dikendalikan ArduSub SITL."
fi

echo "=========================================================="
echo "    Gazebo Harmonic - ROV underwater simulation           "
echo "=========================================================="
echo "Repo   : $REPO_DIR"
echo "World  : $WORLD_NAME"
echo "Plugin : $HOME/ardupilot_gazebo/build"
echo ""
echo "Setelah Gazebo terbuka, jalankan ArduSub SITL di terminal lain:"
echo "  cd ~/ardupilot_sitl"
echo "  python3 Tools/autotest/sim_vehicle.py \\"
echo "    -v ArduSub -f vectored_6dof -N --model=JSON \\"
echo "    --out 127.0.0.1:14551 --out 127.0.0.1:14552 --out 127.0.0.1:14553"
echo "=========================================================="

#------------------------------------------------------------------------------
# 4. Jalan
#------------------------------------------------------------------------------
cd "$REPO_DIR"
exec gz sim -v 3 -r "$WORLD_PATH"
