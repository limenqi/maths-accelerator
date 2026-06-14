import argparse
import time

import numpy as np


# simulation space
WIDTH, HEIGHT = 320, 240
BORDER = 50

# emission
C = 0.5
K = C * C
frequency = [0.01]
CYCLES = 1
pulse_duration = [int(CYCLES / frequency[0])]

# object is always an axis-aligned rectangle
source_position    = [80, 120]
object_position    = [200, 120]
object_half_width  = [10]
object_half_height = [10]

gain = [0.8]
pulse_fired_time = [None]

# grid
yy, xx = np.mgrid[0:HEIGHT, 0:WIDTH]

# damping
damping = np.ones((HEIGHT, WIDTH), np.float32)
for i in range(BORDER):
    v = np.sin(0.5 * np.pi * (i + 1) / BORDER) ** 2
    damping[i, :] = np.minimum(damping[i, :], v)
    damping[HEIGHT - 1 - i, :] = np.minimum(damping[HEIGHT - 1 - i, :], v)
    damping[:, i] = np.minimum(damping[:, i], v)
    damping[:, WIDTH - 1 - i] = np.minimum(damping[:, WIDTH - 1 - i], v)


def make_object_mask(centre_x, centre_y, hw, hh):
    # axis-aligned rectangle
    x0 = max(centre_x - hw, 0);  x1 = min(centre_x + hw, WIDTH - 1)
    y0 = max(centre_y - hh, 0);  y1 = min(centre_y + hh, HEIGHT - 1)
    return (xx >= x0) & (xx <= x1) & (yy >= y0) & (yy <= y1)


source_stencil = np.array(
    [
        [0.05, 0.10, 0.05],
        [0.10, 1.00, 0.10],
        [0.05, 0.10, 0.05],
    ],
    dtype=np.float32,
)
source_stencil /= source_stencil.sum()


def fire_pulse(timestep):
    pulse_fired_time[0] = timestep


def add_source_pulse(next_wave, timestep):
    if pulse_fired_time[0] is None:
        return

    age = timestep - pulse_fired_time[0]
    if age >= pulse_duration[0]:
        pulse_fired_time[0] = None
        return

    amplitude = gain[0] * np.sin(2 * np.pi * frequency[0] * age)
    x0 = max(source_position[0] - 1, 0)
    x1 = min(source_position[0] + 2, WIDTH)
    y0 = max(source_position[1] - 1, 0)
    y1 = min(source_position[1] + 2, HEIGHT)
    sx0 = x0 - (source_position[0] - 1)
    sx1 = 3 - ((source_position[0] + 2) - x1)
    sy0 = y0 - (source_position[1] - 1)
    sy1 = 3 - ((source_position[1] + 2) - y1)
    next_wave[y0:y1, x0:x1] += amplitude * source_stencil[sy0:sy1, sx0:sx1]


def simulation_step(previous_wave, current_wave, object_mask, timestep):
    next_wave = np.empty_like(current_wave)
    centre = current_wave[1:-1, 1:-1]

    # rigid boundary calculation 
    up = np.where(object_mask[:-2, 1:-1], centre, current_wave[:-2, 1:-1])
    down = np.where(object_mask[2:, 1:-1], centre, current_wave[2:, 1:-1])
    left = np.where(object_mask[1:-1, :-2], centre, current_wave[1:-1, :-2])
    right = np.where(object_mask[1:-1, 2:], centre, current_wave[1:-1, 2:])
    laplacian = up + down + left + right - 4.0 * centre

    next_wave[1:-1, 1:-1] = 0.0
    fluid = ~object_mask[1:-1, 1:-1]
    next_wave[1:-1, 1:-1][fluid] = (
        2 * centre[fluid]
        - previous_wave[1:-1, 1:-1][fluid]
        + K * laplacian[fluid]
    )

    next_wave[0, :] = next_wave[1, :]
    next_wave[-1, :] = next_wave[-2, :]
    next_wave[:, 0] = next_wave[:, 1]
    next_wave[:, -1] = next_wave[:, -2]

    next_wave *= damping
    current_wave *= damping
    next_wave[object_mask] = 0.0
    current_wave[object_mask] = 0.0

    add_source_pulse(next_wave, timestep)
    return current_wave, next_wave


def reset_benchmark_state():
    pulse_fired_time[0] = None


def run_benchmark(warmup_steps=0, measured_steps=5000, fire_step=0):
    if measured_steps <= 0:
        raise ValueError("measured_steps must be greater than 0")

    object_mask = make_object_mask(
        object_position[0],
        object_position[1],
        object_half_width[0],
        object_half_height[0],
    )

    reset_benchmark_state()
    previous_wave = np.zeros((HEIGHT, WIDTH), np.float32)
    current_wave = np.zeros((HEIGHT, WIDTH), np.float32)

    for timestep in range(warmup_steps):
        if timestep == fire_step:
            fire_pulse(timestep)

        previous_wave, current_wave = simulation_step(
            previous_wave,
            current_wave,
            object_mask,
            timestep,
        )

    reset_benchmark_state()
    previous_wave = np.zeros((HEIGHT, WIDTH), np.float32)
    current_wave = np.zeros((HEIGHT, WIDTH), np.float32)
    kernel_times = []

    for timestep in range(measured_steps):
        if timestep == fire_step:
            fire_pulse(timestep)

        kernel_start = time.perf_counter()
        previous_wave, current_wave = simulation_step(
            previous_wave,
            current_wave,
            object_mask,
            timestep,
        )
        kernel_end = time.perf_counter()

        kernel_times.append(kernel_end - kernel_start)

    print_results(
        warmup_steps,
        measured_steps,
        fire_step,
        object_mask,
        current_wave,
        kernel_times,
    )


def print_results(
    warmup_steps,
    measured_steps,
    fire_step,
    object_mask,
    current_wave,
    kernel_times,
):
    kernel_times = np.asarray(kernel_times, dtype=np.float64)
    total_kernel_time = float(np.sum(kernel_times))
    kernel_avg = total_kernel_time / measured_steps
    kernel_median = float(np.median(kernel_times))
    kernel_min = float(np.min(kernel_times))
    kernel_max = float(np.max(kernel_times))
    kernel_std = float(np.std(kernel_times))

    interior_cells = (WIDTH - 2) * (HEIGHT - 2)
    fluid_cells = int(np.count_nonzero(~object_mask[1:-1, 1:-1]))
    steps_per_second = measured_steps / total_kernel_time
    cell_updates_per_second = fluid_cells * steps_per_second

    print("CPU baseline benchmark:")
    print("workload:")
    print(f"  grid                     : {WIDTH} x {HEIGHT}")
    print(f"  measured steps           : {measured_steps:,} (+{warmup_steps:,} warmup)")
    print(f"  fluid cells updated      : {fluid_cells:,} of {interior_cells:,}")
    print(f"  object                   : rectangle {object_half_width[0]*2}x{object_half_height[0]*2} px")
    print(f"  source position          : {tuple(source_position)}")
    print(f"  frequency / gain         : {frequency[0]:.4f} / {gain[0]:.2f}")
    print(f"  pulse fired at timestep  : {fire_step:,}")
    print()
    print("performance:")
    print(f"  total timed kernel time  : {total_kernel_time:.6f} s")
    print(f"  average step time        : {kernel_avg * 1e3:.6f} ms")
    print(f"  median step time         : {kernel_median * 1e3:.6f} ms")
    print(f"  min / max step time      : {kernel_min * 1e3:.6f} / {kernel_max * 1e3:.6f} ms")
    print(f"  step time std dev        : {kernel_std * 1e3:.6f} ms")
    print(f"  simulation throughput    : {steps_per_second:,.2f} steps/sec")
    print(f"  cell update throughput   : {cell_updates_per_second / 1e6:,.2f} million cells/sec")
    print()
    print("sanity check:")
    print(f"  final checksum           : {float(np.sum(current_wave)):.9f}")
    print(f"  final max |pressure|     : {float(np.max(np.abs(current_wave))):.9f}")

    if K > 0.5:
        print()
        print("K is above the stability limit")


def parse_position(value):
    try:
        x, y = value.split(",", maxsplit=1)
        return [int(x), int(y)]
    except ValueError as exc:
        raise argparse.ArgumentTypeError("position must be formatted as x,y") from exc


def main():
    parser = argparse.ArgumentParser(
        description="benchmark for wave simulation"
    )
    parser.add_argument("--warmup", type=int, default=100, help="warmup timesteps")
    parser.add_argument("--steps", type=int, default=1000, help="measured timesteps")
    parser.add_argument("--half-width",  type=int, default=10, help="object half-width in pixels")
    parser.add_argument("--half-height", type=int, default=10, help="object half-height in pixels")
    parser.add_argument("--freq", type=float, default=0.01, help="source pulse frequency")
    parser.add_argument("--gain", type=float, default=0.8, help="source pulse gain")
    parser.add_argument("--fire-step", type=int, default=0, help="timestep to fire pulse")
    parser.add_argument("--source", type=parse_position, default=[80, 120], help="source x,y")
    parser.add_argument("--object", type=parse_position, default=[200, 120], help="object x,y")
    args = parser.parse_args()

    frequency[0] = args.freq
    pulse_duration[0] = int(CYCLES / frequency[0])
    gain[0] = args.gain
    source_position[:] = args.source
    object_position[:] = args.object
    object_half_width[0]  = args.half_width
    object_half_height[0] = args.half_height

    run_benchmark(
        warmup_steps=args.warmup,
        measured_steps=args.steps,
        fire_step=args.fire_step,
    )


if __name__ == "__main__":
    main()
