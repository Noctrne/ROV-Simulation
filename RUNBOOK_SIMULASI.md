# Runbook Simulasi ROV — BlueROV2 8 Thruster

Panduan menjalankan simulasi Gazebo Harmonic + ArduSub SITL di PC ini.

Ada tiga skenario:

| Skenario | Tujuan | Butuh program `rovros2_ws`? |
|---|---|---|
| **A — Basic + QGroundControl** | Memastikan Gazebo, SITL, dan QGC sehat | Tidak |
| **B — Uji `rovros2_ws`** | Menguji program ROV yang dideploy ke Jetson | Ya |
| **C — Arena SAUVC** | Latihan babak penyisihan SAUVC (§1.7) | Tidak (opsional) |

Skenario B = Skenario A + tiga flag `--out` + node ROS. **Kode `rovros2_ws` tidak diubah sama sekali.**
Skenario C = Skenario A dengan world `sauvc_qualification.world`.

Konfigurasi yang dipakai di seluruh dokumen:

| Item | Nilai |
|---|---|
| Model | `bluerov2_heavy` (8 thruster) |
| World | `bluerov2_heavy_underwater.world` |
| Arena | `sim_course` — obstacle course statis (lihat §1.5) |
| Arena SAUVC | `sauvc_qualification.world` — kolam + gate kualifikasi (lihat §1.7) |
| Kamera | TPP (Follow) dan FPV opsional via `--fpv` (lihat §1.6) |
| Frame SITL | `vectored_6dof` (`FRAME_CONFIG = 2`) |
| Fisika | Gazebo Harmonic (`gz sim`) |
| Autopilot | ArduSub SITL dari `~/ardupilot_sitl` |

### Script yang tersedia di repo ini

Ada dua script bantuan yang dipakai sepanjang runbook ini:

| Script | Fungsi |
|---|---|
| `scripts/check_sim.sh` | Cek & bersihkan sesi Gazebo/SITL/MAVProxy yang tertinggal. **Jalankan sebelum mulai.** |
| `scripts/start_sim.sh` | Start Gazebo + set environment. **Menolak start** kalau sudah ada server Gazebo lain. |
| `scripts/start_sim.sh --fpv` | Sama, tapi menambah panel kamera FPV di samping 3D view (lihat §1.6). |

Sisanya (`cw.sh`, `ccw.sh`, `forward.sh`, `up.sh`, `down.sh`, `stop.sh`) adalah
utilitas lama untuk mengirim thrust langsung ke Gazebo tanpa ArduPilot.

---

## 1. Prasyarat

### 1.1 Repo / workspace yang diperlukan

| Path | Peran | Skenario |
|---|---|---|
| `~/ROV-Simulation` | World + model 8 thruster + plugin hidrodinamika (**repo ini**) | A, B |
| `~/ardupilot_gazebo` | Menyediakan `build/libArduPilotPlugin.so` penghubung Gazebo ↔ SITL | A, B |
| `~/ardupilot_sitl` | Binary ArduSub SITL + `Tools/autotest/sim_vehicle.py` | A, B |
| `~/QGroundControl-x86_64.AppImage` | Ground station untuk monitoring | A (wajib), B (opsional) |
| `~/ros2_projects/rovros2_ws` | Program ROV yang diuji | B |

Yang **tidak** diperlukan:

| Path | Alasan |
|---|---|
| `~/ros2_projects/simulrovros2_ws` | Hanya referensi ide `--out`; world/model-nya tidak dipakai di runbook ini |
| `~/ardupilot` | Untuk cross-compile firmware ke Pixhawk fisik, bukan SITL |
| `~/ardupilot/...` hasil build ARM | Tidak dipakai simulasi |

### 1.2 Software

- Ubuntu 22.04
- ROS 2 Humble (`/opt/ros/humble/setup.bash`)
- Gazebo Harmonic — perintah `gz sim` tersedia
- ArduSub SITL sudah pernah di-build (`~/ardupilot_sitl/build/sitl/bin/ardusub` ada)
- Python `pymavlink` (dipakai node `rovros2_ws`)
- QGroundControl AppImage

### 1.3 Cek cepat prasyarat

```bash
gz sim --version
ls ~/ardupilot_gazebo/build/libArduPilotPlugin.so
ls ~/ardupilot_sitl/Tools/autotest/sim_vehicle.py
ls ~/ardupilot_sitl/build/sitl/bin/ardusub
ls ~/ros2_projects/rovros2_ws/install/setup.bash   # hanya untuk Skenario B
```

Semua harus ada. Kalau `rovros2_ws/install/setup.bash` belum ada, build dulu:

```bash
cd ~/ros2_projects/rovros2_ws
source /opt/ros/humble/setup.bash
colcon build --packages-select rov_msgs rovros rov_startup
```

### 1.4 Port yang dipakai

| Port | Dipakai oleh | Keterangan |
|---|---|---|
| UDP 9002 / 9003 | Gazebo ↔ SITL | internal plugin JSON, jangan diubah |
| UDP 14550 | QGroundControl | dibuat otomatis oleh `sim_vehicle.py` |
| UDP 14551 | `control_node` | RC override |
| UDP 14552 | `depth_node` | telemetri tekanan |
| UDP 14553 | `att_node` | telemetri attitude |
| TCP 5760 | MAVProxy ↔ SITL | harus bebas dari `mavlink-router` |

### 1.5 Arena / obstacle course

Ketiga world memuat model statis `model://sim_course`, berisi ornamen di
sekitar spawn point ROV `(0, 0, -2)`:

| Ornamen | Keterangan |
|---|---|
| Seabed plateau | pasir 18×18 m, permukaan atas z = −3.5 |
| `gate_1`, `gate_2` | frame PVC, bukaan ±1.3 × 1.9 m (gate 2 diputar 60°) |
| `slalom` | 3 tiang putih, jarak 2 m |
| `hurdle` | bar horizontal 1.5 m di atas pasir |
| `pipeline` | pipa 5.5 m di atas 3 sadel |
| `blocks`, `rocks_west`, `rocks_east` | blok beton dan batu |
| `target_board` | pelat putih dengan bullseye |
| `marker_buoy` | pelampung permukaan + kabel + pemberat |

Semua `<static>true</static>`: plugin buoyancy/hidrodinamika hanya bekerja
pada ROV. Detail layout, cara menggeser, dan cara menghapus ada di
[`models/sim_course/README.md`](models/sim_course/README.md).

Untuk kembali ke laut kosong, hapus/comment blok berikut di file world:

```xml
<include>
  <uri>model://sim_course</uri>
  <pose>0 0 0 0 0 0</pose>
</include>
```

> Ornamen tidak menambah beban komputasi yang berarti dan tidak mengubah
> fisika ROV. Sudah diukur: saat ROV bergerak 1.2 m, semua link arena tetap
> pada `delta = (0.0, 0.0, 0.0)`.

### 1.6 Kamera: TPP vs FPV

Ada dua cara melihat ROV, dan keduanya bisa aktif bersamaan:

| Mode | Sumber gambar | Cara mengaktifkan |
|---|---|---|
| **TPP** (third person) | kamera bebas milik GUI Gazebo | klik kanan `bluerov2_heavy` di **Entity Tree** → **Follow** |
| **FPV** (first person) | sensor `fpv_camera` di hidung ROV | start dengan `./scripts/start_sim.sh --fpv` |

Penting dipahami: **TPP bukan kamera robot.** Fitur *Follow* hanya membuat
kamera bebas GUI mengejar model. Karena itu FPV butuh sensor kamera sungguhan
di dalam model — dan sensor itulah yang ditambahkan di `bluerov2_heavy`.

Spesifikasi sensor (`models/bluerov2_heavy/model.sdf.in`):

| Parameter | Nilai |
|---|---|
| Nama sensor | `fpv_camera` (di `base_link`) |
| Posisi | `0.15 0 0.09` — di hidung, menghadap `+x` (maju) |
| Resolusi | 1280 × 720 (16:9) |
| `horizontal_fov` | 1.2 rad (±69°), VFOV ±42° |
| `update_rate` | 15 Hz (terukur ±11 fps setelah bridge ROS) |

Topik gambar yang dihasilkan:

```text
/world/bluerov2_heavy_underwater/model/bluerov2_heavy/link/base_link/sensor/fpv_camera/image
```

Cek dari terminal lain:

```bash
gz topic -l | grep fpv_camera
gz topic -e -t /world/bluerov2_heavy_underwater/model/bluerov2_heavy/link/base_link/sensor/fpv_camera/image -n 1
```

#### Cara pakai

```bash
./scripts/start_sim.sh --fpv
```

Panel **FPV camera** muncul di sisi kanan jendela Gazebo, di samping 3D view.
3D view tetap kamera bebas, jadi skenario TPP Anda tidak berubah: klik kanan
ROV → **Follow** seperti biasa. Untuk "pindah kamera", cukup lihat panel yang
berbeda — tidak ada mode yang perlu dimatikan.

Sejak stack SAUVC ditambahkan, ada panel kedua **Detection (SAUVC)** di
bawahnya. Panel itu menampilkan gambar yang sama plus bounding box gate,
titik center, garis error-x, dan status detektor. Sumbernya topik gz
`/sauvc/debug`, yang diisi oleh `sauvc_qual_sim.launch.py` (bridge ROS → gz).

| Panel | Sumber | Isi |
|---|---|---|
| FPV camera | sensor `fpv_camera` (gz) | gambar mentah |
| Detection (SAUVC) | node `sauvc_cam` lewat bridge | gambar + bbox + error-x |

Panel Detection akan **kosong** kalau `sauvc_qual_sim.launch.py` tidak jalan.
Itu normal; FPV camera tetap berfungsi. Urutan start yang benar:

```bash
# 1. Gazebo dengan dua panel
./scripts/start_sim.sh sauvc_qualification.world --fpv

# 2. SITL + mavlink-router, lalu launch node SAUVC
ros2 launch rov_startup sauvc_qual_sim.launch.py
```

Cek cepat bahwa gambar debug sampai ke Gazebo:

```bash
gz topic -l | grep sauvc/debug
gz topic -e -t /sauvc/debug -n 1 | head -c 400
```

Tanpa flag `--fpv`, tampilan Gazebo sama persis seperti sebelumnya (tidak ada
panel FPV, tidak ada perubahan perilaku).

#### Syarat teknis

- World `bluerov2_heavy_underwater.world` sudah memuat plugin
  `gz-sim-sensors-system` (dengan `<render_engine>ogre2</render_engine>`).
  Tanpa plugin ini sensor kamera tidak menghasilkan gambar apa pun.
- Panel FPV ada di file terpisah `worlds/fpv_gui.config`, dipakai lewat
  `gz sim --gui-config`. File ini tidak mengubah `~/.gz/sim/8/gui.config`
  milik Anda.
- Hanya model `bluerov2_heavy` yang punya kamera. `--fpv` bisa dipakai di
  world mana pun yang memuat model itu (termasuk `sauvc_qualification.world`);
  script menolak kalau world tidak memuatnya.

#### Catatan performa

Kamera menambah kerja render. Diukur di PC ini (server saja, tanpa GUI):

| Kondisi | RTF | Laju iterasi |
|---|---|---|
| Tanpa kamera (world base) | 0.83 | ~157 iterasi/s |
| Dengan kamera 15 Hz | 0.78 | ~159 iterasi/s |

Selisihnya sekitar 7%, jadi 15 Hz aman. Kalau suatu saat RTF turun drastis:

- turunkan `<update_rate>` di `model.sdf.in` menjadi `10`;
- atau set `update_rate` ke `0` saat kamera tidak dipakai.

> Sensor kamera **tidak** menambah collision, jadi massa, buoyancy, dan
> hidrodinamika ROV tidak berubah sama sekali. Biayanya hanya render.

#### Kalau panel FPV hitam

| Penyebab | Solusi |
|---|---|
| World tidak memuat `bluerov2_heavy` | kamera hanya ada di model itu |
| Plugin `gz-sim-sensors-system` hilang dari world | tambahkan lagi (lihat §1.6 Syarat teknis) |
| Gazebo baru start dan `lock_step` menunggu SITL | jalankan SITL dulu (§3 A2), gambar muncul setelah sim berjalan |
| Simulasi masih paused | tekan Play di panel World control |

### 1.7 Arena SAUVC (kualifikasi)

World terpisah untuk latihan babak penyisihan SAUVC:
`worlds/sauvc_qualification.world`. **World lain tidak diubah**; arena ini
memakai model sendiri, bukan `sim_course`.

```bash
./scripts/start_sim.sh sauvc_qualification.world
./scripts/start_sim.sh sauvc_qualification.world --fpv   # + panel kamera
```

Sistem koordinat:

| Item | Nilai |
|---|---|
| `x = 0` | bibir kolam (garis start) |
| `+x` | maju, masuk ke kolam |
| `+y` | kiri |
| `z = 0` | permukaan air |
| Lebar kolam | 10 m (`y = -5 .. +5`) — asumsi, mudah diubah |
| Gate | `x = 10`, sejajar bibir kolam |
| Spawn ROV | `(0.4, 0, -0.6)`, menghadap gate |

Profil dasar kolam:

| Bagian | Rentang x | Kedalaman | z dasar |
|---|---|---|---|
| Datar dangkal | 0.0 – 1.8 m | 1.28 m | −1.28 |
| Menurun | 1.8 – 19.3 m | 1.28 → 2.00 m | −1.28 → −2.00 |
| Datar dalam | 19.3 – 20.3 m | 2.00 m | −2.00 |

Gate (mengapung, sisi atas menempel permukaan air):

| Bagian | Warna | Ukuran |
|---|---|---|
| 2 tiang | oranye `#FF910F` | diameter 4 cm, panjang 100 cm, di `y = ±0.75` |
| Palang atas | putih `#FFFFFF` | diameter 4 cm, panjang 150 cm |

Bukaan nominal 1.50 m × 1.00 m (antar pusat tiang, dari permukaan air).
Karena pipa tebal 4 cm, bukaan bersih ±1.46 m × 0.96 m. Di `x = 10` dasar
kolam −1.617 m, jadi ada ±0.62 m ruang di bawah gate.

Permukaan kolam (keramik):

| Item | Nilai |
|---|---|
| Ukuran keramik | 20 cm × 10 cm (sisi panjang melintang kolam di lantai, horizontal di dinding) |
| Nat (grout) | 4 mm, biru tua |
| Garis lane lantai | 4 garis, lebar 25 cm, di `y = ±1` dan `y = ±3` → 5 section @ 2 m, gate di section tengah |
| Warna lantai (terukur) | `#22B0D2` (foto `#20B0D0`) |
| Warna dinding (terukur) | `#0153A2` (foto `#0050A0`) |

> Gazebo 8 di workspace ini tidak punya fog/penyerapan air, jadi warna biru
> air "dibakar" ke tekstur keramik. Tekstur dan mesh dibuat oleh
> `python3 scripts/make_pool_assets.py`; detail ada di
> [`models/sauvc_pool/README.md`](models/sauvc_pool/README.md).

> Warna gate disetel agar citra kamera benar-benar mendekati referensi:
> terukur `#FE920F` (tiang) dan `#FEFFFF` (palang) dari `fpv_camera`.
> Ini penting kalau pipeline vision memakai threshold warna. Detail dan
> cara mengubah ada di [`models/sauvc_pool/README.md`](models/sauvc_pool/README.md).

Catatan:

- Gate bersifat **statis** (dipaku di permukaan, tidak ikut mengapung naik
  turun). Buoyancy/hidrodinamika hanya bekerja pada ROV.
- ROV tetap *positively buoyant* seperti di world lain; untuk latihan
  kedalaman, selam dulu lalu tahan dengan `heave` atau `ALT_HOLD`.
- `--fpv` otomatis menyesuaikan nama topik kamera dengan nama world, jadi
  panel FPV tetap jalan tanpa mengedit config.

#### 1.7.1 Stack ROS 2 SAUVC (kualifikasi)

Node SAUVC ada di `rovros2_ws/src/rovros/rovros/sauvc_2027/`:

| Node | Fungsi |
|---|---|
| `sauvc_cam` | kamera + deteksi gate (HSV) → `ROVCamera` + gambar debug |
| `sauvc_qual` | state machine kualifikasi → `/rov/control/command` |

Topik:

| Topik | Tipe | Isi |
|---|---|---|
| `/sauvc/camera/image` | `sensor_msgs/Image` | FPV dari Gazebo (via bridge) |
| `/sauvc/detection` | `rov_msgs/ROVCamera` | metadata + `ROVDetection[]` |
| `/sauvc/debug` | `sensor_msgs/Image` | bbox + garis error-x |
| `/rov/control/command` | `rov_msgs/ROVControl` | perintah ke `control_node` |

Jalankan (SITL + mavlink-router harus sudah hidup):

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_projects/rovros2_ws/install/setup.bash

# deteksi + misi + driver
ros2 launch rov_startup sauvc_qual_sim.launch.py

# plus jendela debug bbox
ros2 launch rov_startup sauvc_qual_sim.launch.py show_debug:=true

# hanya deteksi, tanpa SITL (control/depth/att tidak dijalankan)
ros2 launch rov_startup sauvc_qual_sim.launch.py start_drivers:=false

# trigger misi (pengganti kemiringan roll di simulasi)
ros2 topic pub --once /rov/mission/trigger std_msgs/msg/Empty
```

Urutan misi: `ARM → DIVE (depth > 0.7 m) → SETTLE → FORWARD → TRACK →
PASS → SETTLE → U-TURN → SETTLE → FORWARD → TRACK → PASS → SETTLE →
SURFACE → DONE`. Koreksi hanya `yaw` dari `error_x` gate; tiap gerakan
diikuti jeda diam. Trigger kedua saat misi berjalan = abort.

Konfigurasi ada di `rovros2_ws/src/rovros/config/sauvc.yaml`
(`target_depth`, `surge`, `yaw_kp`, `pass_bbox_h`, `settle_s`, dst).
Deteksi sekarang memakai HSV tanpa ML; untuk pindah ke YOLO nanti cukup
mengisi `model_path` di YAML itu (backend YOLO menyusul).

Cek cepat:

```bash
ros2 node list | grep sauvc        # sauvc_cam, sauvc_qual
ros2 topic echo --once /sauvc/detection
ros2 topic echo /rov/control/command
```

---

## 2. Persiapan (sekali per sesi)

Jalankan di terminal mana pun:

```bash
sudo systemctl stop mavlink-router
killall -9 sim_vehicle.py ardusub mavproxy.py 2>/dev/null || true
```

Tujuan:

- membebaskan port TCP 5760 yang biasanya dipegang service `mavlink-router`;
- mematikan SITL / MAVProxy lama yang tertinggal.

> `mavlink-router` hanya dipakai saat ROV terhubung ke Pixhawk fisik.
> Saat simulasi, service ini harus berhenti.

### 2.1 Pastikan tidak ada Gazebo yang tertinggal

Ini **wajib** dan sering terlewat. Kalau ada dua server Gazebo dengan world
yang sama, keduanya mem-publish ke topik global yang sama
(`/world/<nama_world>/pose/info`), sehingga:

- robot terlihat **fliker / dobel** di dua posisi berbeda;
- kamera yang mengikuti robot membuat **arena tampak ikut bergeser**
  (yang bergerak sebenarnya kamera, bukan arena).

Cek dan bersihkan dengan script yang tersedia:

```bash
cd ~/ROV-Simulation
./scripts/check_sim.sh
```

> **Penting:** proses `gz sim` sebenarnya bernama **`ruby`**, bukan `gz`.
> Perintah `pkill -x gz` atau `pkill gz` **tidak mematikan apa pun**.
> Gunakan pola `-f`:
>
> ```bash
> pkill -9 -f '^gz sim'
> ```


---

## 3. Skenario A — Simulasi basic + QGroundControl

### Terminal A1 — Gazebo

```bash
cd ~/ROV-Simulation
export GZ_SIM_RESOURCE_PATH=$HOME/ROV-Simulation/models:$HOME/ROV-Simulation/worlds
export GZ_SIM_SYSTEM_PLUGIN_PATH=$HOME/ardupilot_gazebo/build
gz sim -v 3 -r worlds/bluerov2_heavy_underwater.world
```

Atau lewat script yang sudah menolak jalan kalau ada server lain:

```bash
~/ROV-Simulation/scripts/start_sim.sh
```

Kalau ingin panel kamera FPV (tampilan dari hidung ROV), tambahkan flag:

```bash
~/ROV-Simulation/scripts/start_sim.sh --fpv
```

Detail mode TPP/FPV ada di §1.6.

Yang diharapkan:

- jendela Gazebo terbuka;
- ROV Heavy (8 thruster) menggantung di air pada z = −2;
- lantai pasir dan **obstacle course** terlihat di sekitar ROV
  (gate kuning di depan, tiang slalom, bar hurdle, dll. — lihat §1.5).

> Plugin memakai `lock_step`, jadi Gazebo akan **tampak menunggu** sampai SITL jalan.
> Ini normal, bukan hang.

> ROV model ini sedikit *positively buoyant* dan akan naik ke permukaan kalau
> thruster diam. Itu perilaku model, bukan bug. Untuk mengerjakan lintasan,
> selam dulu lalu tahan kedalaman dengan `heave` atau `ALT_HOLD`.


### Terminal A2 — ArduSub SITL

```bash
cd ~/ardupilot_sitl
python3 Tools/autotest/sim_vehicle.py -v ArduSub -f vectored_6dof -N --model=JSON
```

Penjelasan flag:

| Flag | Arti |
|---|---|
| `-v ArduSub` | kendaraan bawah air |
| `-f vectored_6dof` | frame 8 thruster, `FRAME_CONFIG = 2` |
| `-N` | jangan rebuild SITL (binary sudah ada) |
| `--model=JSON` | pakai interface JSON ke Gazebo |

Penting:

- **Jangan** pakai `-f vectored` atau `-f gazebo-bluerov2`.
  Keduanya `FRAME_CONFIG = 1` (6 thruster) → 2 thruster diam, gerak ROV kacau.
- Kalau sebelumnya pernah menjalankan frame 6 thruster, `FRAME_CONFIG` tersimpan di EEPROM SITL.
  Jalankan sekali dengan `-w`, atau di prompt MAVProxy:

  ```text
  param set FRAME_CONFIG 2
  reboot
  ```

- Kalau prompt tidak terlihat, tekan **Enter** → muncul `MANUAL>`.

Uji dasar di prompt MAVProxy:

```text
param show FRAME_CONFIG      # HARUS 2

arm throttle
mode alt_hold

rc 3 1450                    # turun
rc 3 1500                    # netral
rc 5 1550                    # maju
rc 1 1600                    # roll kanan (bukti mode 6DOF)
rc 1 1500
rc 5 1500

disarm
```

### Terminal A3 — QGroundControl

```bash
~/QGroundControl-x86_64.AppImage
```

- QGC otomatis connect ke UDP `14550`; tidak perlu menambah link.
- Kalau AppImage gagal karena FUSE:

  ```bash
  ~/QGroundControl-x86_64.AppImage --appimage-extract-and-run
  ```

### Checklist A

| Cek | Cara | Harapan |
|---|---|---|
| Model benar | Gazebo | 8 thruster terlihat |
| Frame benar | `param show FRAME_CONFIG` | **2** |
| SITL hidup | Terminal A2 | prompt `MANUAL>` |
| QGC connect | QGC | vehicle hijau, attitude bergerak |
| Arm | `arm throttle` | QGC **Armed**, kedelapan thruster berputar |
| Maju | `rc 5 1550` | ROV maju di Gazebo |
| 6DOF | `rc 1 1600` | ROV miring ke kanan |
| Depth | QGC | **jangan jadi patokan** (lihat §6) |

Kalau `rc 1 1600` tidak membuat ROV miring, curigai `FRAME_CONFIG` masih 1
atau world yang dimuat bukan Heavy.

---

## 4. Skenario B — Menguji program `rovros2_ws`

Skenario A + endpoint tambahan + node ROS. **Tidak ada perubahan kode dan tidak perlu clone repo.**

### Terminal B1 — Gazebo

Sama persis dengan A1:

```bash
cd ~/ROV-Simulation
export GZ_SIM_RESOURCE_PATH=$HOME/ROV-Simulation/models:$HOME/ROV-Simulation/worlds
export GZ_SIM_SYSTEM_PLUGIN_PATH=$HOME/ardupilot_gazebo/build
gz sim -v 3 -r worlds/bluerov2_heavy_underwater.world
```

Atau: `~/ROV-Simulation/scripts/start_sim.sh`

> Obstacle course aktif di world ini. Untuk uji misi AUV jarak jauh, arena
> bisa menghalangi lintasan. Kalau ingin menguji gerak murni tanpa halangan,
> pakai world kosong atau comment include `sim_course` (§1.5).

### Terminal B2 — SITL + 3 endpoint untuk node ROS

```bash
cd ~/ardupilot_sitl
python3 Tools/autotest/sim_vehicle.py -v ArduSub -f vectored_6dof -N --model=JSON \
  --out 127.0.0.1:14551 \
  --out 127.0.0.1:14552 \
  --out 127.0.0.1:14553
```

Di MAVProxy:

```text
param show FRAME_CONFIG      # 2
arm throttle
```

Port `14550` untuk QGC tetap dibuat otomatis.

### Terminal B3 — QGroundControl (opsional, disarankan)

Sama seperti A3.

Gunanya sebagai pembanding:

- QGC melihat attitude berubah, `ros2 topic echo` tidak → masalah di node Anda;
- dua-duanya tidak berubah → masalah di SITL/Gazebo.

### Terminal B4 — Program `rovros2_ws`

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_projects/rovros2_ws/install/setup.bash
```

Kalau ada perubahan kode sejak build terakhir:

```bash
cd ~/ros2_projects/rovros2_ws
colcon build --packages-select rov_msgs rovros rov_startup
source install/setup.bash
```

#### Langkah 1 — Uji `control_node` saja

```bash
ros2 run rovros control_node
```

Di terminal lain (sumber yang sama):

```bash
ros2 topic pub -r 20 /rov/control/command rov_msgs/msg/ROVControl \
  "{surge: 0.3, heave: 0.0, yaw: 0.0, arm: true, alt_hold: false}"
```

Kalau ROV maju, lapisan `control_node` → MAVLink → SITL → Gazebo sudah beres.
`Ctrl+C` akan mengirim netral + disarm (safe shutdown).

#### Langkah 2 — Uji misi AUV

```bash
ros2 launch rov_startup rov_videosubmission.launch.py
```

Picu misi dari terminal lain:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_projects/rovros2_ws/install/setup.bash
ros2 topic pub --once /rov/mission/trigger std_msgs/msg/Empty "{}"
```

#### Langkah 3 — Uji mode manual

```bash
ros2 launch rov_startup rov_keyboard.launch.py
```

Catatan:

- `camera_node` akan error karena tidak ada `/dev/video0`;
  node lain tetap jalan, error ini bisa diabaikan.
- Script pengirim input operator harus diarahkan ke `127.0.0.1`, bukan `192.168.2.2`.
  Script ini alat uji di PC, bukan kode yang dideploy ke Jetson.

Alternatif kirim input langsung:

```bash
python3 - <<'PY'
import socket, json, time
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
for _ in range(100):
    s.sendto(json.dumps({
        "surge": 0.3, "sway": 0.0, "heave": 0.0, "yaw": 0.0,
        "arm_button": False, "alt_hold_button": False, "grip_button": False,
        "keyboard_present": True
    }).encode(), ("127.0.0.1", 5006))
    time.sleep(0.05)
PY
```

Input harus dikirim ≥ 20 Hz. Berhenti lebih dari 0,5 detik = failsafe
(netral + disarm). Itu perilaku yang benar, bukan bug.

### Checklist B

| Cek | Perintah | Harapan |
|---|---|---|
| Node hidup | `ros2 node list` | `rov_control`, `rov_attitude`, `rov_depth`, `rov_roll_trigger`, `rov_video_submission` |
| Attitude masuk | `ros2 topic echo /rov/sensor/attitude` | ~10 Hz, nilai masuk akal |
| Perintah keluar | `ros2 topic echo /rov/control/command` | berubah mengikuti fase misi |
| Status kontrol | log `rov_control` | `MODE=... ARM=... LINK=ok` |
| Misi | Gazebo | DIVE turun → FORWARD maju → TURN belok → BACK kembali |
| Abort | picu trigger saat misi jalan | netral + disarm + MANUAL |
| 6DOF | kirim `roll`/`pitch` bukan nol | ROV benar-benar miring |

---

## 5. Ringkasan cepat

```text
Skenario A (basic + QGC)
  A0  ./scripts/check_sim.sh          # WAJIB: bersihkan sesi lama
  A1  ./scripts/start_sim.sh          # atau gz sim langsung
      ./scripts/start_sim.sh --fpv    # opsional: + panel kamera FPV
  A2  sim_vehicle.py -f vectored_6dof -N --model=JSON
  A3  QGroundControl AppImage

Skenario B (uji rovros2_ws)
  B0  ./scripts/check_sim.sh
  B1  sama dengan A1
  B2  sim_vehicle.py -f vectored_6dof -N --model=JSON
        --out 127.0.0.1:14551 --out 127.0.0.1:14552 --out 127.0.0.1:14553
  B3  QGC (opsional)
  B4  ros2 launch rov_startup rov_videosubmission.launch.py

Skenario C (arena SAUVC / latihan kualifikasi)
  C0  ./scripts/check_sim.sh
  C1  ./scripts/start_sim.sh sauvc_qualification.world --fpv
  C2  sim_vehicle.py -f vectored_6dof -N --model=JSON
  C3  QGC (opsional)
```

Urutan start selalu: **bersihkan → Gazebo → SITL → QGC → node ROS.**

---

## 6. Yang normal "gagal"

| Gejala | Sebab | Tindakan |
|---|---|---|
| `camera_node` error | tidak ada `/dev/video0` di simulasi | abaikan; node lain tetap jalan |
| `/rov/sensor/depth` tidak berubah | `rov_depth.py` menunggu `SCALED_PRESSURE2`; SITL mengirim `SCALED_PRESSURE`, dan model Heavy tidak punya sensor tekanan | abaikan; depth hanya untuk log |
| `FAILSAFE=ACTIVE` di awal | belum ada input | normal |
| Gripper tidak bergerak | CH7 dipakai grip, sedangkan SERVO1–8 di Heavy semuanya thruster | gripper hanya bisa diuji di hardware |
| ROV hanya bergerak sebagian | `FRAME_CONFIG` tidak cocok dengan model | set `FRAME_CONFIG = 2`, world Heavy |
| ROV diam total | belum `arm throttle`, atau Gazebo masih paused | arm lewat MAVProxy; tekan Play di Gazebo |
| **Robot fliker / terlihat dua robot** | ada **lebih dari satu server Gazebo** dengan world yang sama | `./scripts/check_sim.sh` lalu jalankan ulang |
| **Arena terasa ikut bergeser** | sama seperti di atas — kamera mengikuti robot dari server lain | pastikan hanya 1 server: `pgrep -f '^gz sim'` harus kosong sebelum start |
| `pkill -x gz` tidak mempan | nama proses `gz sim` sebenarnya `ruby` | pakai `pkill -9 -f '^gz sim'` |

## 7. Aturan yang jangan dilanggar

1. **Satu terminal = satu workspace.**
   Terminal B4 hanya `rovros2_ws`; jangan source `simulrovros2_ws` di sana.
2. **Jangan jalankan node `simulrov`** saat menguji `rovros2_ws`
   — keduanya berebut port 14551–14553.
3. **Jangan jalankan `failsafe_node` bersama `videosubmission_node`**
   — keduanya menulis ke `/rov/control/command`.
4. **Jangan jalankan `scripts/script_mavrouter.sh`** — itu untuk Pixhawk fisik.
5. **World Heavy + `vectored_6dof` harus berpasangan.**
   World Heavy dengan `FRAME_CONFIG = 1`, atau world base dengan `FRAME_CONFIG = 2`,
   sama-sama menghasilkan gerak menyesatkan.
6. **Angka tuning tidak transferable.**
   Heavy: 8 thruster, 13 kg. `6T6D` fisik: 6 thruster, geometri berbeda.
   Durasi/fase hanya valid untuk menguji logika, bukan untuk disalin ke robot.
7. **Satu server Gazebo saja.**
   Jalankan `./scripts/check_sim.sh` sebelum mulai, dan pakai
   `./scripts/start_sim.sh` yang sudah menolak start kalau ada server lain.
8. **Jangan pakai `pkill -x gz`.** Proses `gz sim` bernama `ruby`.
   Gunakan `pkill -9 -f '^gz sim'`.
9. **Edit `model.sdf.in`, bukan `model.sdf`.**
   `model.sdf` adalah hasil generate (`scripts/generate_model.py`). Kalau
   hanya `.sdf` yang diedit, perubahan hilang pada regenerate berikutnya —
   termasuk sensor `fpv_camera`.

---

## 8. Troubleshooting

| Masalah | Penyebab | Solusi |
|---|---|---|
| `bind failed on port 5760` | `mavlink-router` atau SITL lama masih jalan | `sudo systemctl stop mavlink-router`; `killall -9 sim_vehicle.py ardusub mavproxy.py` |
| Gazebo berhenti di `validate_structures` | SITL menunggu paket JSON dari Gazebo | pastikan Gazebo jalan dan tidak paused |
| Prompt MAVProxy tidak muncul | log menutupi prompt | tekan **Enter** |
| QGC tidak connect | SITL belum jalan, atau `--no-extra-ports` dipakai | jalankan SITL tanpa `--no-extra-ports` |
| `control_node` menunggu heartbeat | port `14551` tidak ada / SITL belum siap | pastikan `--out 127.0.0.1:14551` ada, lalu restart node |
| ROV di Gazebo tidak bergerak walau armed | frame tidak cocok / Gazebo paused | `param show FRAME_CONFIG` harus 2; tekan Play |
| Panel FPV hitam | world bukan `bluerov2_heavy`, atau `lock_step` masih menunggu SITL | pakai `bluerov2_heavy_underwater.world`; jalankan SITL (A2); tekan Play (§1.6) |
| `--fpv` ditolak script | world itu belum punya sensor kamera | hanya `bluerov2_heavy_underwater.world` yang punya `fpv_camera` |

---

### 8.1 Robot dobel / arena bergeser

Gejala:

- dalam satu frame terlihat dua robot di posisi berbeda;
- robot "fliker" bolak-balik;
- arena terasa bergeser mengikuti robot.

Penyebab: dua proses Gazebo mem-publish ke topik yang sama. GUI lalu
menampilkan dua aliran pose yang saling bertabrakan, dan karena kamera
mengikuti robot, seluruh scene (termasuk arena) tampak bergeser.

Diagnosis:

```bash
# harus KOSONG sebelum memulai simulasi
pgrep -af '^gz sim'
```

Solusi:

```bash
cd ~/ROV-Simulation
./scripts/check_sim.sh          # interaktif, akan menawarkan kill
# atau langsung:
pkill -9 -f '^gz sim'
```

Lalu jalankan lagi dengan `./scripts/start_sim.sh` yang sudah punya
pengaman (menolak start kalau ada server lain).

Bukti bahwa arena memang statis: pengukuran pose `seabed`, `gate_1`,
`slalom`, dan `blocks` menunjukkan delta `(0.0, 0.0, 0.0)` tepat, sementara
ROV bergerak ±1.2 m saat thruster diberi perintah.


---

## 9. Referensi

- Gazebo Harmonic: <https://gazebosim.org/docs/harmonic/install>
- ardupilot_gazebo: <https://github.com/ArduPilot/ardupilot_gazebo>
- BlueROV2 SITL (upstream): <https://github.com/clydemcqueen/bluerov2_gz>
- ArduSub SITL: <https://ardupilot.org/dev/docs/setting-up-sitl-on-linux.html>
- MAVProxy: <https://ardupilot.org/mavproxy/docs/getting_started/download_and_installation.html>
- Sensor kamera Gazebo: <https://gazebosim.org/docs/harmonic/sensors>
- Plugin GUI `ImageDisplay`: <https://gazebosim.org/docs/harmonic/gui_config>
