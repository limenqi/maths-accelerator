# EE2 Mathematics Accelerator

Interactive real-time FPGA wave visualisation system for the PYNQ-Z1.

This project models a two-dimensional pressure wave on a `320 x 240` solver grid and displays it as a `640 x 480` HDMI output using `2 x 2` pixel scaling. The wave update, boundary damping, source injection, object interaction, and colour mapping are implemented in FPGA logic. The ARM processor on the PYNQ-Z1 loads the overlay and controls runtime parameters through AXI-Lite registers.

## What It Does

- Simulates a 2D acoustic pressure field using a finite-difference Laplacian update.
- Streams the generated visualisation to HDMI through the PYNQ video pipeline.
- Allows runtime control of source position, object position, object size, gain, pulse duration, and fire trigger.
- Uses a rectangular penetrable object with reflection and transmission at its boundary.
- Includes a Python software simulator, Verilator unit tests, and CPU benchmark programs for comparison.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `overlay/ip/pixel_generator_1.0/` | Main FPGA IP. Contains `pixel_generator.v`, Laplacian/object/damping modules, and lookup-table files. |
| `overlay/` | Vivado overlay scripts and base design files. |
| `demo/` | Final PYNQ overlay files: `finalv17.bit` and `finalv17.hwh`. |
| `wave_simulator_ui_v2.ipynb` | Notebook/user interface for running the hardware demo on the PYNQ-Z1. |
| `software_sim/` | Python software reference wave simulations. |
| `tb/` | Verilator and GoogleTest-based RTL unit/integration tests. |
| `benchmark/` | CPU solver, renderer, and full-frame benchmark programs. |
| `doc/` | Design notes, build notes, screenshots, and timing/resource documentation. |

## Final Hardware Design

The accelerator is centred on the `pixel_generator` IP. It:

1. Reads pressure values from ping-pong BRAM buffers.
2. Builds the five-point stencil using line buffers and shift registers.
3. Applies object-boundary reflection/transmission logic.
4. Applies boundary damping near the simulation edges.
5. Adds a pulse source when triggered.
6. Converts pressure values to RGB pixels and streams them over AXI4-Stream.

The final design targets the PYNQ-Z1's Zynq-7020 device (`xc7z020clg400-1`).

## Running the Demo on PYNQ-Z1

1. Upload the files to the PYNQ board.
   
demo/finalv17.bit
demo/finalv17.hwh
wave_simulator_ui_v2.ipynb

2. Open wave_simulator_ui_v2.ipynb in Jupyter  browser.
3. Update BIT_PATH in cell 0
4. In the address bar, change 'notebooks' to 'voila/render'.

http://<board-ip>:9090/notebooks/path/to/wave_simulator_ui_v2.ipynb
http://<board-ip>:9090/voila/render/path/to/wave_simulator_ui_v2.ipynb

Runtime controls include:

| Control | Action |
| --- | --- |
| `Space` | Fire a wave pulse |
| `W A S D` | Move the source |
| Arrow keys | Move the object |
| Scroll | Resize the object |
| `g` / `f` | Increase/decrease gain |
| `]` / `[` | Increase/decrease pulse duration |
| `e` | Toggle object mode |
| `r` | Reset source/object positions |

## Running RTL Tests

The RTL tests use Verilator and GoogleTest.

List available tests:

```bash
./tb/doit.sh list
```

Run all tests:

```bash
./tb/doit.sh
```

Run one test:

```bash
./tb/doit.sh object_laplacian
```

Current test groups cover:

- `object_laplacian`
- `object_classification`
- `apply_damping`
- `boundary_damping_coeff`
- `pixel_generator`

## CPU Benchmarks

The `benchmark/` directory contains C++ and Python benchmark code for the software baseline:

- `solver_benchmark.cpp`
- `renderer_benchmark.cpp`
- `full_benchmark.cpp`

These were used to compare the CPU-only wave solver/render path against the FPGA implementation.

## Building the Overlay

Vivado project generation scripts are in `overlay/`:

```tcl
source build_ip.tcl
source base.tcl
```

The design is based on the PYNQ base overlay with the custom `pixel_generator` IP connected to the BRAM, AXI-Lite, VDMA, and HDMI pipeline. Building requires a Vivado installation with Zynq-7000 support.

## Key Results

- CPU full-frame baseline: `6.30 fps`
- FPGA hardware output: `59.52 fps`
- Approximate full-frame speed-up: `9.4x`
- Final display frame time: `16.80 ms`
- Solver grid: `320 x 240`
- HDMI output: `640 x 480`

Full-system implementation met timing after post-route physical optimisation. The final design uses all available BRAM tiles on the PYNQ-Z1, so higher-resolution simulation would require off-chip memory or a redesigned memory architecture.

## Notes

This repository contains both final project files and development artefacts. The important entry points are:

- Hardware RTL: `overlay/ip/pixel_generator_1.0/pixel_generator.v`
- Final overlay: `demo/finalv17.bit`, `demo/finalv17.hwh`
- UI notebook: `wave_simulator_ui_v2.ipynb`
- RTL tests: `tb/doit.sh`
- Software reference: `software_sim/wave_simulation_pix.py`
