#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <numeric>
#include <vector>

constexpr int WIDTH = 320;
constexpr int HEIGHT = 240;
constexpr int SCALE = 2;
constexpr int WARMUP_FRAMES = 30;
constexpr int MEASURED_FRAMES = 300;
constexpr float PRESSURE_LIMIT = 0.5f;

std::vector<float> make_pressure_field() {
    std::vector<float> wave(WIDTH * HEIGHT);
    const float cx = WIDTH * 0.32f;
    const float cy = HEIGHT * 0.50f;

    for (int y = 0; y < HEIGHT; ++y) {
        for (int x = 0; x < WIDTH; ++x) {
            const float dx = x - cx;
            const float dy = y - cy;
            const float radius = std::sqrt(dx * dx + dy * dy);
            wave[y * WIDTH + x] =
                0.45f * std::sin(radius * 0.18f) * std::exp(-radius * 0.018f) +
                0.18f * std::sin((x + y) * 0.05f);
        }
    }

    return wave;
}

void render_frame(const std::vector<float>& wave, std::vector<uint8_t>& frame) {
    constexpr int output_width = WIDTH * SCALE;

    for (int y = 0; y < HEIGHT; ++y) {
        for (int x = 0; x < WIDTH; ++x) {
            const float pressure = wave[y * WIDTH + x];
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
                    const int index = ((out_y + dy) * output_width + out_x + dx) * 3;
                    frame[index + 0] = red;
                    frame[index + 1] = green;
                    frame[index + 2] = blue;
                }
            }
        }
    }
}

int main() {
    constexpr int output_width = WIDTH * SCALE;
    constexpr int output_height = HEIGHT * SCALE;
    constexpr int output_pixels = output_width * output_height;

    const std::vector<float> wave = make_pressure_field();
    std::vector<uint8_t> frame(output_pixels * 3);

    for (int i = 0; i < WARMUP_FRAMES; ++i) {
        render_frame(wave, frame);
    }

    std::vector<double> times;
    times.reserve(MEASURED_FRAMES);
    for (int i = 0; i < MEASURED_FRAMES; ++i) {
        const auto start = std::chrono::steady_clock::now();
        render_frame(wave, frame);
        const auto end = std::chrono::steady_clock::now();
        times.push_back(std::chrono::duration<double>(end - start).count());
    }

    const double total_time = std::accumulate(times.begin(), times.end(), 0.0);
    const double average_time = total_time / MEASURED_FRAMES;
    const double fps = MEASURED_FRAMES / total_time;
    const double pixel_throughput = output_pixels * fps;
    const long long checksum = std::accumulate(frame.begin(), frame.end(), 0LL);

    std::cout << "C++ renderer benchmark\n";
    std::cout << "grid: " << WIDTH << "x" << HEIGHT << "\n";
    std::cout << "output: " << output_width << "x" << output_height << "\n";
    std::cout << "frames: " << MEASURED_FRAMES << " (+" << WARMUP_FRAMES << " warmup)\n";
    std::cout << "avg frame time: " << average_time * 1000.0 << " ms\n";
    std::cout << "fps: " << fps << "\n";
    std::cout << "pixel throughput: " << pixel_throughput / 1e6 << " million pixels/s\n";
    std::cout << "checksum: " << checksum << "\n";
}
