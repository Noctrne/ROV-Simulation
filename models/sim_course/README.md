# `models/sim_course` — Static training course

Obstacle course placed around the ROV spawn point at `(0, 0, -2)`.
Used by all three worlds in this repo (`bluerov2_underwater.world`,
`bluerov2_heavy_underwater.world`, `bluerov2_ping.world`).

For the full simulation procedure (Gazebo + ArduSub SITL + QGroundControl +
ROS 2), see [`RUNBOOK_SIMULASI.md`](../../RUNBOOK_SIMULASI.md).

## Design rules

* **Everything is `<static>true</static>`.** The buoyancy and hydrodynamics
  plugins only act on the ROV, so the course never floats away and never
  adds drag to the simulated vehicle.
* **No web dependency.** All geometry is primitive SDF (box, cylinder,
  sphere), no external meshes or textures.
* **Spawn point stays clear.** The nearest obstacle is the gate 3.5 m away,
  so the ROV never spawns inside geometry.

## The course is verified static

If the arena ever appears to slide when the ROV moves, the course is **not**
the cause — it is two Gazebo servers publishing to the same topics (usually a
leftover session). Measure it:

```bash
gz topic -e -t /world/bluerov2_heavy_underwater/pose/info -n 1 \
  | grep -A4 'name: "seabed"'
```

During validation the ROV moved 1.2 m under thrust while every arena link
(`seabed`, `gate_1`, `slalom`, `blocks`) stayed at exactly
`delta = (0.0, 0.0, 0.0)`.

Clean up a leftover session with:

```bash
cd ~/ROV-Simulation && ./scripts/check_sim.sh
```

> The `gz sim` process is actually named `ruby`, so `pkill -x gz` matches
> nothing. Use `pkill -9 -f '^gz sim'`.


## Vertical layout

| Surface | z (m) |
|---|---|
| Water surface | 0.00 |
| ROV spawn / hover depth | -2.00 |
| Sand top surface | -3.50 |

Obstacles that break the ROV's hover plane are the ones that matter:
gate frames reach z = -1.56 and -1.46, slalom poles and target board
reach -1.90, hurdle bar sits at -1.95.

## Layout (top view, +x forward, +y left)

```
   +y
    |          blocks (0, 3)          buoy (2.5, 3.5)
    |      hurdle (-3.5, 1.5)         gate 2 (6, 2.5)
    |
    |   pipeline (-6.5, 0)             gate 1 (3.5, 0)
    + :::::::::::::::::::::::::::::::::::::::::::::> +x
    |      rocks west (-5, -2)        rocks east (5.5, -1.5)
    |      slalom poles (x -2/0/2, y -3)
    |                                target board (5.5, -3.5)
```

| Link | Shape | Purpose |
|---|---|---|
| `seabed` | 18 x 18 m sand plateau, top at z = -3.5 | floor + 3 corner sand mounds |
| `gate_1` | yellow PVC frame, opening 1.30 x 1.85 m, faces +x | fly-through gate |
| `gate_2` | orange PVC frame, 60 deg rotation, slightly wider | angled fly-through gate |
| `slalom` | 3 white poles, 2 m apart, tips at z = -1.90 | steer around |
| `hurdle` | blue bar at 1.5 m above the sand | climb over or dive under |
| `pipeline` | 5.5 m orange pipe (r = 0.10 m) on 3 saddles | follow / cross |
| `blocks` | 4 concrete blocks, 0.26–0.50 m, various angles | debris field |
| `rocks_west` | 4 spheres, r = 0.22–0.45 m | natural clutter |
| `rocks_east` | 3 spheres, r = 0.20–0.50 m | natural clutter |
| `target_board` | 1.10 x 1.10 m white plate with painted bullseye | aiming / docking target |
| `marker_buoy` | orange float at the surface + cable + sinker | depth reference |

## Editing the course

Move a piece by editing the `<pose>` of its `<link>`:

```xml
<link name="gate_1">
  <pose>3.5 0.0 -3.5 0 0 0</pose>   <!-- x y z roll pitch yaw -->
```

Add a new gate by copying the `gate_1` link and changing `name` and `pose`.
All names within the model must stay unique.

## Removing the course

Delete or comment out this block in the world file:

```xml
<include>
  <uri>model://sim_course</uri>
  <pose>0 0 0 0 0 0</pose>
</include>
```

The sea will then only contain `sand_heightmap`, the ROV, and the axes
marker, exactly as before.

## Adding the course to your own world

```xml
<include>
  <uri>model://sim_course</uri>
  <pose>0 0 0 0 0 0</pose>
</include>
```

Then start Gazebo with the model directory on the resource path:

```bash
cd ~/ROV-Simulation
./scripts/start_sim.sh            # sets GZ_SIM_RESOURCE_PATH for you
```

## Piloting note

The BlueROV2 model is slightly positively buoyant (about 0.14 kg of extra
displacement), so it drifts up to the surface when the thrusters are idle.
This is pre-existing model behaviour, not something the course introduced.
To work the course, dive down and hold depth with `heave` or `ALT_HOLD`.

## Validation

```bash
# syntax + semantic check
SDF_PATH=$HOME/ROV-Simulation/models gz sdf -k models/sim_course/model.sdf

# expand the include and list the resolved links
SDF_PATH=$HOME/ROV-Simulation/models:$HOME/ROV-Simulation/worlds \
  gz sdf -p worlds/bluerov2_heavy_underwater.world | grep "<link name="
```
