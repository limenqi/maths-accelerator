import argparse
import time

import numpy as np


DEFAULT_WIDTH = 320
DEFAULT_HEIGHT = 240
DEFAULT_SCALE = 2
DEFAULT_PRESSURE_LIMIT = 0.5 # how strong a pressure value has to be before it becomes a fully saturated colour


def make_pressure_field(width, height):
    yy, xx = np.mgrid[0:height, 0:width]
    cx = width * 0.32
    cy = height * 0.50
    radius = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)

    wave = 0.45 * np.sin(radius * 0.18) * np.exp(-radius * 0.018)
    wave += 0.18 * np.sin((xx + yy) * 0.05)
    return wave.astype(np.float32)


def render_wave_pixel_by_pixel(wave, frame, pressure_limit, scale):
    height, width = wave.shape

    for y in range(height):
        for x in range(width):
            pressure = wave[y, x]
            visibility = int(min(abs(pressure) / pressure_limit * 255.0, 255.0))

            if pressure > 0:
                red = 255
                green = 255 - visibility
                blue = 255 - visibility
            elif pressure < 0:
                red = 255 - visibility
                green = 255 - visibility
                blue = 255
            else:
                red = 255
                green = 255
                blue = 255

            out_y = y * scale
            out_x = x * scale
            for dy in range(scale):
                for dx in range(scale):
                    frame[out_y + dy, out_x + dx, 0] = red
                    frame[out_y + dy, out_x + dx, 1] = green
                    frame[out_y + dy, out_x + dx, 2] = blue

    return frame


def run_benchmark(width, height, scale, warmup_frames, measured_frames, pressure_limit):
    if measured_frames <= 0:
        raise ValueError("measured_frames must be greater than 0")
    if scale <= 0:
        raise ValueError("scale must be greater than 0")

    wave = make_pressure_field(width, height)
    frame = np.zeros((height * scale, width * scale, 3), dtype=np.uint8)

    for _ in range(warmup_frames):
        render_wave_pixel_by_pixel(wave, frame, pressure_limit, scale)

    frame_times = []
    for _ in range(measured_frames):
        start = time.perf_counter()
        render_wave_pixel_by_pixel(wave, frame, pressure_limit, scale)
        end = time.perf_counter()
        frame_times.append(end - start)

    print_results(width, height, scale, warmup_frames, measured_frames, wave, frame, frame_times)


def print_results(width, height, scale, warmup_frames, measured_frames, wave, frame, frame_times):
    frame_times = np.asarray(frame_times, dtype=np.float64)
    total_time = float(np.sum(frame_times))
    average_time = total_time / measured_frames
    median_time = float(np.median(frame_times))
    min_time = float(np.min(frame_times))
    max_time = float(np.max(frame_times))
    std_time = float(np.std(frame_times))

    output_width = width * scale
    output_height = height * scale
    pressure_cells_per_frame = width * height
    pixels_per_frame = output_width * output_height
    frames_per_second = measured_frames / total_time
    pixels_per_second = pixels_per_frame * frames_per_second

    print("CPU pixel renderer benchmark:")
    print("workload:")
    print(f"  pressure grid            : {width} x {height}")
    print(f"  output frame             : {output_width} x {output_height} ({scale} x scaling)")
    print(f"  pressure cells/frame     : {pressure_cells_per_frame:,}")
    print(f"  output pixels/frame      : {pixels_per_frame:,}")
    print(f"  measured frames          : {measured_frames:,} (+{warmup_frames:,} warmup)")
    print()
    print("performance:")
    print(f"  total render time        : {total_time:.6f} s")
    print(f"  average frame time       : {average_time * 1e3:.6f} ms")
    print(f"  median frame time        : {median_time * 1e3:.6f} ms")
    print(f"  min / max frame time     : {min_time * 1e3:.6f} / {max_time * 1e3:.6f} ms")
    print(f"  frame time std dev       : {std_time * 1e3:.6f} ms")
    print(f"  render throughput        : {frames_per_second:,.2f} frames/sec")
    print(f"  pixel throughput         : {pixels_per_second / 1e6:,.2f} million pixels/sec")
    print()
    print("sanity check:")
    print(f"  input checksum           : {float(np.sum(wave)):.9f}")
    print(f"  output checksum          : {int(np.sum(frame))}")


def main():
    parser = argparse.ArgumentParser(description="benchmark the CPU pixel renderer")
    parser.add_argument("--width", type=int, default=DEFAULT_WIDTH, help="pressure grid width")
    parser.add_argument("--height", type=int, default=DEFAULT_HEIGHT, help="pressure grid height")
    parser.add_argument("--scale", type=int, default=DEFAULT_SCALE, help="integer display scaling factor")
    parser.add_argument("--warmup", type=int, default=10, help="warmup frames")
    parser.add_argument("--frames", type=int, default=100, help="measured frames")
    parser.add_argument(
        "--pressure-limit",
        type=float,
        default=DEFAULT_PRESSURE_LIMIT,
        help="pressure magnitude that maps to full colour",
    )
    args = parser.parse_args()

    run_benchmark(
        width=args.width,
        height=args.height,
        scale=args.scale,
        warmup_frames=args.warmup,
        measured_frames=args.frames,
        pressure_limit=args.pressure_limit,
    )


if __name__ == "__main__":
    main()
