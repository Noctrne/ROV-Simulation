# BlueROV2 in Gazebo Harmonic

> Status: proof-of-concept, updated for Gazebo Harmonic binaries

This is a model of the BlueROV2, including support for both the base and heavy
configurations, that runs in Gazebo Harmonic. It uses the BuoyancyPlugin,
HydrodynamicsPlugin and ThrusterPlugin.

![bluerov2_gz](images/bluerov2.png)

## Documentation

| Document | Contents |
|---|---|
| [RUNBOOK_SIMULASI.md](RUNBOOK_SIMULASI.md) | Step-by-step simulation runbook (Bahasa Indonesia): prerequisites, Gazebo + ArduSub SITL + QGroundControl, testing an external ROS 2 program, troubleshooting |
| [models/sim_course/README.md](models/sim_course/README.md) | Static obstacle course: layout, coordinate table, how to move or remove pieces |
| [models/sauvc_pool/README.md](models/sauvc_pool/README.md) | SAUVC qualification arena: pool depth profile, gate dimensions, reference colours |

The repo is tested with `~/ardupilot_gazebo` and `~/ardupilot_sitl`; see the
runbook for the exact commands and the `--out` MAVLink endpoints used to feed a
ROS 2 control program.

## Helper scripts

| Script | Purpose |
|---|---|
| `scripts/start_sim.sh [world]` | Start Gazebo with the right environment. Refuses to start if another Gazebo server is already running. |
| `scripts/start_sim.sh [world] --fpv` | Same, plus an FPV camera panel next to the 3D view (image from the nose of `bluerov2_heavy`). The 3D view stays a free camera, so Follow (TPP) still works. |
| `scripts/check_sim.sh` | Detect and clean up leftover Gazebo / SITL / MAVProxy sessions. |
| `scripts/make_pool_assets.py` | Regenerate the SAUVC pool tile textures and floor/wall meshes (`models/sauvc_pool/`). |
| `scripts/cw.sh`, `ccw.sh`, `forward.sh`, `up.sh`, `down.sh`, `stop.sh` | Send raw thrust commands to a model (no ArduPilot needed). |

> Two Gazebo servers publishing to the same world topics make the ROV flicker
> between two positions and make the scene appear to slide. Always clean up
> first. Note that the `gz sim` process is named `ruby`, so `pkill -x gz` does
> nothing — use `pkill -9 -f '^gz sim'`.

## Requirements

Please ensure that the following requirements have been met prior to installing the
project:

* [Gazebo Harmonic](https://gazebosim.org/docs/harmonic/install)
* [ardupilot_gazebo for Harmonic](https://github.com/ArduPilot/ardupilot_gazebo)
* [ArduSub and MAVProxy](https://ardupilot.org/dev/docs/building-setup-linux.html)

See the [Dockerfile](docker/Dockerfile) for full installation details.

## Running Gazebo

Gazebo can be launched using the following commands:

~~~bash
export GZ_SIM_RESOURCE_PATH=~/colcon_ws/src/bluerov2_gz/models:~/colcon_ws/src/bluerov2_gz/worlds
export GZ_SIM_SYSTEM_PLUGIN_PATH=~/ardupilot_gazebo/build
gz sim -v 3 -r <gazebo-world-file>
~~~

where `<gazebo-world-file>` should be replaced with:
* `bluerov2_underwater.world` for the BlueROV2 base configuration
* `bluerov2_heavy_underwater.world` for the BlueROV2 Heavy configuration
* `bluerov2_ping.world` for a BlueROV2 base with a Ping sonar
* `sauvc_qualification.world` for the SAUVC qualification arena (see below)

The three BlueROV2 training worlds include the static `sim_course` obstacle
course around the spawn point (gates, slalom poles, a pipe hurdle, a pipeline,
concrete blocks, rocks, a target board and a marker buoy). Remove that
`<include>` block from the world file to get an empty seabed again.

### SAUVC qualification arena

`sauvc_qualification.world` is a separate arena for the SAUVC qualification
course and does not include `sim_course`:

* 10 m wide pool, water surface at `z = 0`
* bottom 1.28 m deep for the first 1.8 m, then a slope down to 2.00 m over
  17.5 m, then 1 m flat
* floating gate 10 m from the pool edge: two orange posts (`#FF910F`) and a
  white top bar (`#FFFFFF`), 4 cm diameter, 1.50 m wide by 1.00 m high

The gate's top sits on the water surface, so its clear opening is entirely
below `z = 0`. See [models/sauvc_pool/README.md](models/sauvc_pool/README.md)
for the full geometry and the colour calibration.

```bash
./scripts/start_sim.sh sauvc_qualification.world
./scripts/start_sim.sh sauvc_qualification.world --fpv
```

#### ROS 2 detection + mission stack

Two nodes in `rovros2_ws` run the qualification attempt end to end:

| Node | Role |
|---|---|
| `sauvc_cam` | subscribes to the FPV image, detects the gate with HSV colour thresholding (no ML), publishes `rov_msgs/ROVCamera` + a debug image |
| `sauvc_qual` | state machine (dive → forward/track → pass → U-turn → pass → surface), publishes `rov_msgs/ROVControl` |

```bash
ros2 launch rov_startup sauvc_qual_sim.launch.py                 # mission + drivers
ros2 launch rov_startup sauvc_qual_sim.launch.py show_debug:=true
ros2 launch rov_startup sauvc_qual_sim.launch.py start_drivers:=false  # detection only
ros2 topic pub --once /rov/mission/trigger std_msgs/msg/Empty    # start / abort
```

Parameters live in `rovros2_ws/src/rovros/config/sauvc.yaml`. The detection
backend is chosen by `model_path`: empty means the classical HSV detector, a
`.pt` path will select YOLO once that backend is added — `sauvc_qual` never
changes because it only reads `ROVCamera`.

### Cameras: TPP and FPV

The 3D view in Gazebo is a free camera, not a robot camera. The third-person
view (TPP) you get with **Entity Tree → right click on `bluerov2_heavy` →
Follow** is that free camera chasing the model.

A first-person view (FPV) therefore needs a real camera sensor on the model.
`bluerov2_heavy` has one: `fpv_camera` on `base_link`, at the nose, looking
forward (1280×720, hfov 1.2 rad, vfov ±42°, 15 Hz). Start Gazebo with a GUI
config that shows its image:

~~~bash
./scripts/start_sim.sh --fpv
~~~

A panel called **FPV camera** then appears next to the 3D view, plus a second
panel **Detection (SAUVC)** that shows the same image with the detected gate
bounding box (gz topic `/sauvc/debug`, fed by `sauvc_qual_sim.launch.py`).
The detection panel stays empty until that launch is running. The 3D view is
unchanged, so Follow (TPP) keeps working at the same time — switching cameras
just means looking at the other panel. Without `--fpv`, Gazebo behaves exactly
as before.

The camera is rendered by the `gz-sim-sensors-system` plugin in
`worlds/bluerov2_heavy_underwater.world`; the panel is defined in
`worlds/fpv_gui.config`. Image topic:

~~~text
/world/bluerov2_heavy_underwater/model/bluerov2_heavy/link/base_link/sensor/fpv_camera/image
~~~

Only `bluerov2_heavy` has a camera so far. The sensor has no collision, so
mass, buoyancy and hydrodynamics are unaffected; it only costs render time
(measured ~7% RTF at 15 Hz on this machine).

Once Gazebo has been launched, you can directly send thrust commands to the BlueROV2
model in Gazebo:

~~~bash
cd ~/colcon_ws/src/bluerov2_gz
scripts/cw.sh <model_name>
scripts/stop.sh <model_name>
~~~

where `<model_name>` is replaced with the corresponding model defined in the world:
* `bluerov2` for the `bluerov2_underwater.world`
* `bluerov2_heavy` for the `bluerov2_heavy_underwater.world`
* `bluerov2_ping` for the `bluerov2_ping.world`

Now launch ArduSub and ardupilot_gazebo:

~~~bash
cd ~/ardupilot
Tools/autotest/sim_vehicle.py -L RATBeach -v ArduSub -f <frame> --model=JSON --out=udp:0.0.0.0:14550 --console
~~~

where `<frame>` is replaced with either `vectored` for the BlueROV2 base configuration or
`vectored_6dof` for the BlueROV2 Heavy configuration.

Note: if you run into problems switching between the vectored and vectored_6dof frame add the `-w` option to delete all ArduSub parameters.

Use MAVProxy to send commands to ArduSub:

~~~bash
arm throttle
rc 3 1450     
rc 3 1500
mode alt_hold
rc 5 1550
disarm
~~~

Additional information regarding the usage of each model may be found in a model's
respective directory.

## ROS2 and Colcon

ROS2 users should add `ardupilot_gazebo -b ros2` and `bluerov2_gz` to the colcon workspace and use
colcon to build and manage the environment.

## References

* https://github.com/ardupilot/ardupilot_gazebo/wiki
* https://gazebosim.org/docs/harmonic/install
* https://ardupilot.org/dev/docs/building-setup-linux.html
* https://ardupilot.org/dev/docs/setting-up-sitl-on-linux.html
* https://ardupilot.org/mavproxy/docs/getting_started/download_and_installation.html
* https://www.ardusub.com/developers/rc-input-and-output.html
* https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html
