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
#   ./scripts/start_sim.sh sauvc_qualification.world
#   ./scripts/start_sim.sh --fpv                  # + panel kamera FPV
#   ./scripts/start_sim.sh sauvc_qualification.world --fpv
#
# Flag --fpv menambahkan panel "FPV camera" di samping 3D view. Panel itu
# menampilkan gambar dari sensor `fpv_camera` di hidung bluerov2_heavy.
# 3D view tetap kamera bebas, jadi fitur Follow (TPP) tetap bisa dipakai
# bersamaan. Tanpa flag ini, tampilan Gazebo sama persis seperti sebelumnya.
# Flag ini jalan untuk world apa pun yang memuat model://bluerov2_heavy;
# topik kamera disesuaikan otomatis dengan nama world.
# ==============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORLD_NAME=""
USE_FPV=0

#------------------------------------------------------------------------------
# 0. Parsing argumen (world boleh di mana saja, flag boleh di mana saja)
#------------------------------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        --fpv)   USE_FPV=1 ;;
        -h|--help)
            # Print the whole leading comment block (lines 2.. up to the
            # closing ==== line), with the leading "# " stripped.
            awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        -*)
            echo "[ERROR] Flag tidak dikenal: $arg"
            echo "        Yang tersedia: --fpv"
            exit 1
            ;;
        *)
            if [ -n "$WORLD_NAME" ]; then
                echo "[ERROR] World disebut lebih dari sekali: $WORLD_NAME, $arg"
                exit 1
            fi
            WORLD_NAME="$arg"
            ;;
    esac
done
WORLD_NAME="${WORLD_NAME:-bluerov2_heavy_underwater.world}"

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
# 2b. Siapkan GUI config untuk FPV (nama world bisa berbeda-beda)
#------------------------------------------------------------------------------
GUI_CONFIG="$REPO_DIR/worlds/fpv_gui.config"
if [ "$USE_FPV" -eq 1 ]; then
    if ! grep -q "model://bluerov2_heavy" "$WORLD_PATH"; then
        echo "[ERROR] --fpv butuh world yang memuat model://bluerov2_heavy."
        echo "        World '$WORLD_NAME' tidak memuatnya, jadi tidak ada"
        echo "        sensor kamera yang bisa ditampilkan."
        exit 1
    fi

    # Nama world di dalam SDF (dipakai di prefiks topik gz-transport).
    WORLD_INNER_NAME=$(sed -n 's/.*<world name="\([^"]*\)".*/\1/p' "$WORLD_PATH" | head -n 1)
    if [ -z "$WORLD_INNER_NAME" ]; then
        echo "[ERROR] Tidak menemukan <world name=\"...\"> di $WORLD_PATH"
        exit 1
    fi

    # Ganti hanya prefiks world pada baris <topic>, bukan komentar.
    GUI_CONFIG="/tmp/fpv_gui_${WORLD_INNER_NAME}.config"
    sed "s#<topic>/world/[^/]*/#<topic>/world/${WORLD_INNER_NAME}/#" \
        "$REPO_DIR/worlds/fpv_gui.config" > "$GUI_CONFIG"

    if ! grep -q "<topic>/world/${WORLD_INNER_NAME}/" "$GUI_CONFIG"; then
        echo "[ERROR] Gagal menyiapkan topik FPV untuk world '$WORLD_INNER_NAME'."
        exit 1
    fi
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
if [ "$USE_FPV" -eq 1 ]; then
    echo "Kamera : FPV aktif (panel kanan, gambar dari hidung ROV)"
    echo "         TPP tetap: klik kanan bluerov2_heavy di Entity Tree > Follow"
    echo "         Topik : /world/$WORLD_INNER_NAME/.../sensor/fpv_camera/image"
else
    echo "Kamera : TPP saja (pakai --fpv untuk panel FPV)"
fi
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

if [ "$USE_FPV" -eq 1 ]; then
    exec gz sim -v 3 -r --gui-config "$GUI_CONFIG" "$WORLD_PATH"
fi
exec gz sim -v 3 -r "$WORLD_PATH"
