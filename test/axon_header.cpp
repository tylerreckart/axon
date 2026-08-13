#include "axon.hpp"

#include <cassert>
#include <cstdint>
#include <cstring>
#include <vector>

int main() {
  using namespace axon;

  assert(mode_from_name("listen") == Mode::Listen);
  assert(mode_from_alfred_phase("thinking") == Mode::Think);
  assert(mode_from_alfred_phase("recording") == Mode::Listen);
  assert(mode_from_alfred_phase("speaking") == Mode::Speak);
  assert(mode_from_alfred_phase("done") == Mode::Idle);
  assert(!mode_from_alfred_phase("nope").has_value());

  std::vector<std::uint8_t> silence(256, 0);
  assert(rms_s16le(silence.data(), silence.size()) == 0.f);

  std::int16_t peak = 16000;
  std::uint8_t bytes[2];
  std::memcpy(bytes, &peak, 2);
  const float rms = rms_s16le(bytes, 2);
  assert(rms > 0.4f && rms <= 1.f);

  Frame frame;
  assert(frame.weights[0] == 1.f);
  return 0;
}
