#!/usr/bin/env bash
# ==============================================================================
# Script: check_sim.sh
# Purpose: Deteksi & bersihkan sesi Gazebo / SITL yang tertinggal.
#
# Kenapa perlu:
#   Setiap `gz sim` membuka transport GZ di partisi yang sama
#   (/world/<nama_world>/...). Kalau ada dua server dengan world yang sama,
#   keduanya mem-publish ke topik yang sama, sehingga:
#     - GUI menerima 2 pose ROV berbeda -> robot "fliker" / dobel
#     - kamera bisa mengikuti ROV dari server lain -> arena tampak bergeser
#       (yang bergerak sebenarnya kamera, bukan arena)
#
# Catatan penting:
#   1. Nama proses `gz sim` sebenarnya adalah `ruby`, BUKAN `gz`.
#      `pkill -x gz` TIDAK mematikan apa pun. Pakai pola `-f`.
#   2. `pgrep -f` ikut mencocokkan command line script ini sendiri,
#      karena itu fungsi di bawah menyaring PID sendiri dan induknya.
# ==============================================================================

set -u

SELF=$$
PARENT=$PPID

# pgrep -f yang tidak ikut menangkap script ini sendiri
find_pids() {
    local pattern="$1" pid
    for pid in $(pgrep -f "$pattern" 2>/dev/null || true); do
        [ "$pid" = "$SELF" ] && continue
        [ "$pid" = "$PARENT" ] && continue
        # lewati proses yang command line-nya memuat nama script ini
        if tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q "check_sim.sh"; then
            continue
        fi
        echo "$pid"
    done
}

show() {
    local label="$1" pids="$2"
    echo "[!] $label masih berjalan:"
    ps -o pid,etime,args -p "$(echo "$pids" | tr '\n' ',' | sed 's/,$//')" 2>/dev/null
}

echo "=========================================================="
echo "    Cek sesi simulasi yang masih berjalan                 "
echo "=========================================================="

FOUND=""

GZ_PIDS=$(find_pids '^gz sim')
[ -n "$GZ_PIDS" ] && { FOUND=1; show "Gazebo" "$GZ_PIDS"; }

SITL_PIDS=$(find_pids 'build/sitl/bin/ardusub')
[ -n "$SITL_PIDS" ] && { FOUND=1; show "ArduSub SITL" "$SITL_PIDS"; }

MP_PIDS=$(find_pids 'mavproxy\.py')
[ -n "$MP_PIDS" ] && { FOUND=1; show "MAVProxy" "$MP_PIDS"; }

if [ -z "$FOUND" ]; then
    echo "[OK] Tidak ada sesi simulasi yang tertinggal."
    exit 0
fi

echo
read -r -p "Matikan semua proses di atas? [y/N] " ANSWER
case "$ANSWER" in
    y|Y)
        echo "Mematikan..."
        # `gz sim` berjalan sebagai ruby; pola -f ini yang benar
        [ -n "$GZ_PIDS" ]   && kill -9 $GZ_PIDS   2>/dev/null || true
        [ -n "$SITL_PIDS" ] && kill -9 $SITL_PIDS 2>/dev/null || true
        [ -n "$MP_PIDS" ]   && kill -9 $MP_PIDS   2>/dev/null || true
        sleep 1
        echo "Sisa Gazebo  : $(find_pids '^gz sim' | wc -l)"
        echo "Sisa SITL    : $(find_pids 'build/sitl/bin/ardusub' | wc -l)"
        echo "Sisa MAVProxy: $(find_pids 'mavproxy\.py' | wc -l)"
        echo "[OK] Bersih."
        ;;
    *)
        echo "Dibatalkan. Perlu diingat: server ganda akan membuat simulasi kacau."
        ;;
esac
