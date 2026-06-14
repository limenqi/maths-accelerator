#include <algorithm>
#include <chrono>
#include <cmath>
#include <iostream>
#include <numeric>
#include <vector>

constexpr int WIDTH = 320;
constexpr int HEIGHT = 240;
constexpr int BORDER = 50;
constexpr int WARMUP_STEPS = 30;
constexpr int MEASURED_STEPS = 300;

constexpr float C = 0.5f;
constexpr float K = C * C;
constexpr float FREQ = 0.01f;
constexpr float GAIN = 0.8f;
constexpr float PI = 3.14159265358979323846f;
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

void step(
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

int main() {
    const std::vector<float> damping = make_damping();
    const std::vector<uint8_t> object_mask = make_object_mask();

    std::vector<float> previous(WIDTH * HEIGHT, 0.0f);
    std::vector<float> current(WIDTH * HEIGHT, 0.0f);
    std::vector<float> next(WIDTH * HEIGHT, 0.0f);

    for (int t = 0; t < WARMUP_STEPS; ++t) {
        step(previous, current, next, damping, object_mask, t, 0);
    }

    std::fill(previous.begin(), previous.end(), 0.0f);
    std::fill(current.begin(), current.end(), 0.0f);
    std::fill(next.begin(), next.end(), 0.0f);

    std::vector<double> times;
    times.reserve(MEASURED_STEPS);
    for (int t = 0; t < MEASURED_STEPS; ++t) {
        const auto start = std::chrono::steady_clock::now();
        step(previous, current, next, damping, object_mask, t, 0);
        const auto end = std::chrono::steady_clock::now();
        times.push_back(std::chrono::duration<double>(end - start).count());
    }

    const double total_time = std::accumulate(times.begin(), times.end(), 0.0);
    const double avg_step = total_time / MEASURED_STEPS;
    const double steps_per_second = MEASURED_STEPS / total_time;

    const int interior_cells = (WIDTH - 2) * (HEIGHT - 2);
    int object_cells = 0;
    for (int y = 1; y < HEIGHT - 1; ++y) {
        for (int x = 1; x < WIDTH - 1; ++x) {
            object_cells += object_mask[idx(x, y)] ? 1 : 0;
        }
    }
    const int fluid_cells = interior_cells - object_cells;
    const double cell_updates_per_second = fluid_cells * steps_per_second;

    double checksum = 0.0;
    double max_pressure = 0.0;
    for (float value : current) {
        checksum += value;
        max_pressure = std::max(max_pressure, static_cast<double>(std::abs(value)));
    }

    std::cout << "C++ solver benchmark\n";
    std::cout << "grid: " << WIDTH << "x" << HEIGHT << "\n";
    std::cout << "steps: " << MEASURED_STEPS << " (+" << WARMUP_STEPS << " warmup)\n";
    std::cout << "fluid cells: " << fluid_cells << " of " << interior_cells << "\n";
    std::cout << "avg step time: " << avg_step * 1000.0 << " ms\n";
    std::cout << "steps/s: " << steps_per_second << "\n";
    std::cout << "cell updates/s: " << cell_updates_per_second / 1e6 << " million\n";
    std::cout << "checksum: " << checksum << "\n";
    std::cout << "max |pressure|: " << max_pressure << "\n";
}
