#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <vector>

constexpr int WIDTH = 320;
constexpr int HEIGHT = 240;
constexpr int SCALE = 2;
constexpr int OUTPUT_WIDTH = WIDTH * SCALE;
constexpr int OUTPUT_HEIGHT = HEIGHT * SCALE;
constexpr int CHANNELS = 4;

constexpr int FRAMES_MEASURED = 300;
constexpr int WARMUP_FRAMES = 30;
constexpr int STEPS_PER_FRAME = 1;

constexpr int BORDER = 50;
constexpr float C = 0.5f;
constexpr float K = C * C;
constexpr float FREQ = 0.01f;
constexpr float GAIN = 0.8f;
constexpr float PI = 3.14159265358979323846f;
constexpr float PRESSURE_LIMIT = 0.5f;
constexpr int PULSE_DURATION = static_cast<int>(1.0f / FREQ);

constexpr int SOURCE_X = 80;
constexpr int SOURCE_Y = 120;
constexpr int OBJECT_X = 200;
constexpr int OBJECT_Y = 120;
constexpr int OBJECT_HALF_W = 10;
constexpr int OBJECT_HALF_H = 10;

int idx(int x, int y) {
    return y * WIDTH + x;
}

std::vector<float> make_damping() {
    std::vector<float> damping(WIDTH * HEIGHT, 1.0f);

    for (int i = 0; i < BORDER; ++i) {
        const float v = std::pow(std::sin(0.5f * PI * (i + 1) / BORDER), 2.0f);

        for (int x = 0; x < WIDTH; ++x) {
            damping[idx(x, i)] = std::min(damping[idx(x, i)], v);
            damping[idx(x, HEIGHT - 1 - i)] = std::min(damping[idx(x, HEIGHT - 1 - i)], v);
        }
        for (int y = 0; y < HEIGHT; ++y) {
            damping[idx(i, y)] = std::min(damping[idx(i, y)], v);
            damping[idx(WIDTH - 1 - i, y)] = std::min(damping[idx(WIDTH - 1 - i, y)], v);
        }
    }

    return damping;
}

std::vector<uint8_t> make_object_mask() {
    std::vector<uint8_t> mask(WIDTH * HEIGHT, 0);
    const int x0 = std::max(OBJECT_X - OBJECT_HALF_W, 0);
    const int x1 = std::min(OBJECT_X + OBJECT_HALF_W, WIDTH - 1);
    const int y0 = std::max(OBJECT_Y - OBJECT_HALF_H, 0);
    const int y1 = std::min(OBJECT_Y + OBJECT_HALF_H, HEIGHT - 1);

    for (int y = y0; y <= y1; ++y) {
        for (int x = x0; x <= x1; ++x) {
            mask[idx(x, y)] = 1;
        }
    }

    return mask;
}

void add_source(std::vector<float>& next, int timestep, int fire_step) {
    const int age = timestep - fire_step;
    if (age < 0 || age >= PULSE_DURATION) {
        return;
    }

    const float stencil[3][3] = {
        {0.05f, 0.10f, 0.05f},
        {0.10f, 1.00f, 0.10f},
        {0.05f, 0.10f, 0.05f},
    };
    const float stencil_sum = 1.60f;
    const float amplitude = GAIN * std::sin(2.0f * PI * FREQ * age);

    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            const int x = SOURCE_X + dx;
            const int y = SOURCE_Y + dy;
            if (x >= 0 && x < WIDTH && y >= 0 && y < HEIGHT) {
                next[idx(x, y)] += amplitude * stencil[dy + 1][dx + 1] / stencil_sum;
            }
        }
    }
}

void step_wave(
    std::vector<float>& previous,
    std::vector<float>& current,
    std::vector<float>& next,
    const std::vector<float>& damping,
    const std::vector<uint8_t>& object_mask,
    int timestep,
    int fire_step
) {
    std::fill(next.begin(), next.end(), 0.0f);

    for (int y = 1; y < HEIGHT - 1; ++y) {
        for (int x = 1; x < WIDTH - 1; ++x) {
            const int center_idx = idx(x, y);
            if (object_mask[center_idx]) {
                continue;
            }

            const float center = current[center_idx];
            const float up = object_mask[idx(x, y - 1)] ? center : current[idx(x, y - 1)];
            const float down = object_mask[idx(x, y + 1)] ? center : current[idx(x, y + 1)];
            const float left = object_mask[idx(x - 1, y)] ? center : current[idx(x - 1, y)];
            const float right = object_mask[idx(x + 1, y)] ? center : current[idx(x + 1, y)];
            const float laplacian = up + down + left + right - 4.0f * center;

            next[center_idx] = 2.0f * center - previous[center_idx] + K * laplacian;
        }
    }

    for (int x = 0; x < WIDTH; ++x) {
        next[idx(x, 0)] = next[idx(x, 1)];
        next[idx(x, HEIGHT - 1)] = next[idx(x, HEIGHT - 2)];
    }
    for (int y = 0; y < HEIGHT; ++y) {
        next[idx(0, y)] = next[idx(1, y)];
        next[idx(WIDTH - 1, y)] = next[idx(WIDTH - 2, y)];
    }

    for (int i = 0; i < WIDTH * HEIGHT; ++i) {
        next[i] *= damping[i];
        current[i] *= damping[i];
        if (object_mask[i]) {
            next[i] = 0.0f;
            current[i] = 0.0f;
        }
    }

    add_source(next, timestep, fire_step);
    previous.swap(current);
    current.swap(next);
}

void render_rgba(const std::vector<float>& wave, std::vector<uint8_t>& frame) {
    for (int y = 0; y < HEIGHT; ++y) {
        for (int x = 0; x < WIDTH; ++x) {
            const float pressure = wave[idx(x, y)];
            const int visibility = static_cast<int>(
                std::min(std::abs(pressure) / PRESSURE_LIMIT * 255.0f, 255.0f)
            );

            uint8_t red = 255;
            uint8_t green = 255;
            uint8_t blue = 255;
            if (pressure > 0.0f) {
                green = blue = static_cast<uint8_t>(255 - visibility);
            } else if (pressure < 0.0f) {
                red = green = static_cast<uint8_t>(255 - visibility);
            }

            const int out_x = x * SCALE;
            const int out_y = y * SCALE;
            for (int dy = 0; dy < SCALE; ++dy) {
                for (int dx = 0; dx < SCALE; ++dx) {
                    const int out_idx = ((out_y + dy) * OUTPUT_WIDTH + out_x + dx) * CHANNELS;
                    frame[out_idx + 0] = red;
                    frame[out_idx + 1] = green;
                    frame[out_idx + 2] = blue;
                    frame[out_idx + 3] = 255;
                }
            }
        }
    }
}

double median(std::vector<double> values) {
    std::sort(values.begin(), values.end());
    const size_t mid = values.size() / 2;
    if (values.size() % 2 == 0) {
        return 0.5 * (values[mid - 1] + values[mid]);
    }
    return values[mid];
}

double mean(const std::vector<double>& values) {
    return std::accumulate(values.begin(), values.end(), 0.0) / values.size();
}

double standard_deviation(const std::vector<double>& values, double avg) {
    double variance = 0.0;
    for (double value : values) {
        variance += (value - avg) * (value - avg);
    }
    return std::sqrt(variance / values.size());
}

int main() {
    const std::vector<float> damping = make_damping();
    const std::vector<uint8_t> object_mask = make_object_mask();

    std::vector<float> previous(WIDTH * HEIGHT, 0.0f);
    std::vector<float> current(WIDTH * HEIGHT, 0.0f);
    std::vector<float> next(WIDTH * HEIGHT, 0.0f);
    std::vector<uint8_t> frame(OUTPUT_WIDTH * OUTPUT_HEIGHT * CHANNELS, 0);

    int timestep = 0;
    for (int frame_n = 0; frame_n < WARMUP_FRAMES; ++frame_n) {
        for (int step_n = 0; step_n < STEPS_PER_FRAME; ++step_n) {
            step_wave(previous, current, next, damping, object_mask, timestep++, 0);
        }
        render_rgba(current, frame);
    }

    std::vector<double> solver_times;
    std::vector<double> render_times;
    std::vector<double> loop_times;
    solver_times.reserve(FRAMES_MEASURED);
    render_times.reserve(FRAMES_MEASURED);
    loop_times.reserve(FRAMES_MEASURED);

    const auto benchmark_start = std::chrono::steady_clock::now();
    for (int frame_n = 0; frame_n < FRAMES_MEASURED; ++frame_n) {
        const auto loop_start = std::chrono::steady_clock::now();

        const auto solver_start = std::chrono::steady_clock::now();
        for (int step_n = 0; step_n < STEPS_PER_FRAME; ++step_n) {
            step_wave(previous, current, next, damping, object_mask, timestep++, 0);
        }
        const auto solver_end = std::chrono::steady_clock::now();

        render_rgba(current, frame);
        const auto render_end = std::chrono::steady_clock::now();

        solver_times.push_back(std::chrono::duration<double>(solver_end - solver_start).count());
        render_times.push_back(std::chrono::duration<double>(render_end - solver_end).count());
        loop_times.push_back(std::chrono::duration<double>(render_end - loop_start).count());
    }
    const auto benchmark_end = std::chrono::steady_clock::now();

    const double total_time = std::chrono::duration<double>(benchmark_end - benchmark_start).count();
    const double fps = FRAMES_MEASURED / total_time;
    const double loop_avg = mean(loop_times);
    const double loop_std = standard_deviation(loop_times, loop_avg);

    double pressure_checksum = 0.0;
    double max_pressure = 0.0;
    for (float value : current) {
        pressure_checksum += value;
        max_pressure = std::max(max_pressure, static_cast<double>(std::abs(value)));
    }
    const long long frame_checksum = std::accumulate(frame.begin(), frame.end(), 0LL);

    const double display_pixel_throughput = static_cast<double>(OUTPUT_WIDTH) * OUTPUT_HEIGHT * fps;
    const double sim_cell_throughput = static_cast<double>(WIDTH) * HEIGHT * STEPS_PER_FRAME * fps;

    std::cout << std::fixed << std::setprecision(3);
    std::cout << "cpu c++ software benchmark\n";
    std::cout << "----------------------------------------\n";
    std::cout << "frames measured              : " << FRAMES_MEASURED << "\n";
    std::cout << "warmup frames                : " << WARMUP_FRAMES << "\n";
    std::cout << "solver steps per frame       : " << STEPS_PER_FRAME << "\n";
    std::cout << "last frame shape             : (" << OUTPUT_HEIGHT << ", " << OUTPUT_WIDTH << ", " << CHANNELS << ")\n";
    std::cout << "total time                   : " << total_time << " s\n";
    std::cout << "fps                          : " << fps << "\n";
    std::cout << "ms per displayed frame       : " << loop_avg * 1000.0 << " ms\n";
    std::cout << "display pixel throughput     : " << static_cast<long long>(display_pixel_throughput) << " px/s\n";
    std::cout << "sim cell throughput          : " << static_cast<long long>(sim_cell_throughput) << " cells/s\n";
    std::cout << "solver avg / median          : " << mean(solver_times) * 1000.0 << " / "
              << median(solver_times) * 1000.0 << " ms\n";
    std::cout << "render avg / median          : " << mean(render_times) * 1000.0 << " / "
              << median(render_times) * 1000.0 << " ms\n";
    std::cout << "loop min / max               : " << (*std::min_element(loop_times.begin(), loop_times.end())) * 1000.0
              << " / " << (*std::max_element(loop_times.begin(), loop_times.end())) * 1000.0 << " ms\n";
    std::cout << "loop std dev                 : " << loop_std * 1000.0 << " ms\n";
    std::cout << "pressure checksum            : " << pressure_checksum << "\n";
    std::cout << "max |pressure|               : " << max_pressure << "\n";
    std::cout << "frame checksum               : " << frame_checksum << "\n";
}
