#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <optional>
#include <string_view>

namespace thoughtform {

// Presence modes — keep in lockstep with web/js/presence.js and docs/protocol.md.
enum class Mode : std::uint8_t { Idle = 0, Listen = 1, Think = 2, Speak = 3 };

inline constexpr std::array<std::string_view, 4> kModeNames = {
    "idle", "listen", "think", "speak"};

// GPU uniform block (WebGL uses individual uniforms; Metal packs float4s).
struct Frame {
  float time = 0.f;
  float weights[4] = {1.f, 0.f, 0.f, 0.f};
  float amplitude = 0.f;
  float bands[3] = {0.f, 0.f, 0.f};
  float progress = 0.f;
  float attention = 0.15f;
  float chaos = 0.f;
  float quality = 1.f;
  float color_a[3] = {1.000f, 0.392f, 0.078f};  // PLATO plasma #ff6414
  float color_b[3] = {1.000f, 0.706f, 0.353f};  // #ffb45a
  float color_c[3] = {1.000f, 0.863f, 0.627f};  // #ffdca0
  float background[3] = {0.020f, 0.008f, 0.000f};  // #050200
};

inline float clamp01(float x) { return std::min(1.f, std::max(0.f, x)); }

inline Mode mode_from_name(std::string_view name) {
  if (name == "listen") return Mode::Listen;
  if (name == "think") return Mode::Think;
  if (name == "speak") return Mode::Speak;
  return Mode::Idle;
}

// Alfred client-side turn phases (see docs/protocol.md).
inline std::optional<Mode> mode_from_alfred_phase(std::string_view phase) {
  if (phase == "idle" || phase == "done") return Mode::Idle;
  if (phase == "recording" || phase == "cancelled") return Mode::Listen;
  if (phase == "stt" || phase == "thinking") return Mode::Think;
  if (phase == "speaking") return Mode::Speak;
  return std::nullopt;
}

inline const char* alfred_phase_from_mode(Mode m) {
  switch (m) {
    case Mode::Listen:
      return "recording";
    case Mode::Think:
      return "thinking";
    case Mode::Speak:
      return "speaking";
    case Mode::Idle:
    default:
      return "idle";
  }
}

// Cheap RMS of Alfred's s16le mono PCM (one sink chunk is enough for amplitude).
inline float rms_s16le(const std::uint8_t* data, std::size_t len) {
  if (data == nullptr || len < 2) return 0.f;
  const std::size_t n = len / 2;
  double acc = 0.0;
  for (std::size_t i = 0; i < n; ++i) {
    std::int16_t s;
    std::memcpy(&s, data + i * 2, 2);
    const double v = static_cast<double>(s) / 32768.0;
    acc += v * v;
  }
  return clamp01(static_cast<float>(std::sqrt(acc / static_cast<double>(n)) * 2.4));
}

}  // namespace thoughtform
