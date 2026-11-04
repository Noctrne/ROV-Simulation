# BlueROV2 Heavy

A Gazebo model of the BlueROV2 Heavy configuration.

![BlueROV2 Heavy Gazebo](/images/bluerov2_heavy.png)

## Usage

Gazebo and all other requirements documented in the project [README](/README.md) should
be installed.

Update the `GZ_SIM_RESOURCE_PATH` to include the BlueROV2 models:

~~~bash
export GZ_SIM_RESOURCE_PATH=$GZ_SIM_RESOURCE_PATH:\
~/colcon_ws/src/bluerov2_gz/models:\
~/colcon_ws/src/bluerov2_gz/worlds
~~~

### Start Gazebo

~~~bash
gz sim -v 3 -r bluerov2_heavy_underwater.world
~~~

### FPV camera

This model has a forward-looking camera on the nose (`fpv_camera` on
`base_link`, 640x480, 15 Hz). It is rendered by the `gz-sim-sensors-system`
plugin in `bluerov2_heavy_underwater.world`.

To see its image in a Gazebo panel:

~~~bash
~/ROV-Simulation/scripts/start_sim.sh --fpv
~~~

Image topic:

~~~text
/world/bluerov2_heavy_underwater/model/bluerov2_heavy/link/base_link/sensor/fpv_camera/image
~~~

The 3D view is still a free camera, so **Entity Tree → right click on
`bluerov2_heavy` → Follow** (TPP) works at the same time as the FPV panel.

### Editing this model

`model.sdf` is generated — do not edit it by hand. The camera, thrusters and
plugin parameters live in `model.sdf.in`, where `@name` tokens are substituted
from `configs.yaml`. After editing, regenerate:

~~~bash
cd ~/ROV-Simulation
python3 scripts/generate_model.py \
  models/bluerov2_heavy/model.sdf.in \
  models/bluerov2_heavy/model.sdf \
  models/bluerov2_heavy/configs.yaml
~~~

> If you only edit `model.sdf`, the next regeneration silently drops your
> change (including the FPV camera).

### Run ArduPilot SITL

~~~bash
Tools/autotest/sim_vehicle.py -L RATBeach -v ArduSub -f vectored_6dof --model=JSON --out=udp:0.0.0.0:14550 --console
~~~

### Send commands to the ROV

~~~
arm throttle
rc 3 1450     
rc 3 1500
mode alt_hold
rc 5 1550
disarm
~~~

## Credits

All meshes have been obtained from [Blue Robotics](https://bluerobotics.com/) at the
following sources:

- [BlueROV2 Mesh](https://grabcad.com/library/bluerov2-1)
- [T200 Propeller Mesh](https://grabcad.com/library/bluerobotics-t200-thruster-1)

The hydrodynamic parameters used for the model have been obtained from the following
source:

- [An Open-Source Benchmark Simulator: Control of a BlueROV2 Underwater Robot](https://github.com/ROV-Simulator/ROV-Simulator)