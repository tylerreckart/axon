#version 300 es
precision highp float;

// thoughtform — Alfred presence shader (GLSL ES 3.00 / WebGL 2)
// Canonical visual. Keep math in lockstep with shaders/thoughtform.metal.

layout(location = 0) out vec4 fragColor;

uniform vec2 u_resolution;
uniform float u_time;
uniform vec4 u_weights;   // idle, listen, think, speak (should sum ~1)
uniform float u_amplitude; // 0..1 RMS of mic (listen) or TTS (speak)
uniform vec3 u_bands;      // low, mid, high
uniform float u_progress;  // 0..1 within the current turn
uniform float u_attention; // 0..1 lock-on to the user
uniform float u_chaos;     // thinking turbulence / tool activity
uniform float u_quality;   // 0.5 mobile .. 1.0 desktop (octave count)
uniform vec3 u_color_a;    // primary (Gotham teal)
uniform vec3 u_color_b;    // secondary (pale cyan)
uniform vec3 u_color_c;    // accent (amber, speech)
uniform vec3 u_bg;         // void

float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p, int octaves) {
  float v = 0.0;
  float a = 0.5;
  mat2 m = mat2(1.6, 1.2, -1.2, 1.6);
  for (int i = 0; i < 6; i++) {
    if (i >= octaves) break;
    v += a * vnoise(p);
    p = m * p;
    a *= 0.5;
  }
  return v;
}

float saturate(float x) { return clamp(x, 0.0, 1.0); }

void main() {
  vec2 fragCoord = gl_FragCoord.xy;
  vec2 res = max(u_resolution, vec2(1.0));
  vec2 uv = (fragCoord - 0.5 * res) / min(res.x, res.y);

  float idleW = saturate(u_weights.x);
  float listenW = saturate(u_weights.y);
  float thinkW = saturate(u_weights.z);
  float speakW = saturate(u_weights.w);

  float t = u_time;
  float amp = saturate(u_amplitude);
  float low = saturate(u_bands.x);
  float mid = saturate(u_bands.y);
  float high = saturate(u_bands.z);
  float chaos = saturate(u_chaos);
  float attn = saturate(u_attention);
  float prog = saturate(u_progress);

  int octaves = u_quality > 0.75 ? 5 : (u_quality > 0.4 ? 4 : 3);

  // Breath: slow idle, quicker when listening, held while thinking, pulsed while speaking.
  float breathHz = mix(0.35, 0.85, listenW) + speakW * (1.4 + amp * 2.2);
  float breath = sin(t * breathHz * 6.28318);
  float breathAmt = 0.018 * idleW + 0.04 * listenW + 0.012 * thinkW + 0.055 * speakW * (0.35 + amp);

  // Listening pulls energy inward; speaking pushes it out; thinking folds space.
  float radiusScale = 1.0
    + breath * breathAmt
    + 0.12 * amp * (listenW + speakW)
    + 0.08 * low
    + 0.06 * attn
    - 0.04 * thinkW;

  vec2 p = uv / max(radiusScale, 0.25);

  // Domain warp — strongest while thinking, nudged by mid band.
  float warp = 0.04 * idleW + 0.07 * listenW + (0.16 + 0.22 * chaos) * thinkW + 0.05 * speakW;
  warp += 0.06 * mid;
  float wt = t * (0.11 + thinkW * 0.18);
  vec2 warpVec = vec2(
    fbm(p * 2.15 + vec2(wt, 0.0), octaves),
    fbm(p * 2.15 + vec2(8.1, -wt), octaves)
  ) * 2.0 - 1.0;
  p += warpVec * warp;

  // Thinking adds a slow spiral fold.
  float r0 = length(p);
  float a0 = atan(p.y, p.x);
  float spiral = thinkW * (0.35 + 0.65 * chaos) * (0.55 + 0.45 * sin(t * 0.7));
  a0 += r0 * spiral * 1.8 + t * (0.08 * idleW - 0.22 * listenW + 0.14 * thinkW + 0.18 * speakW);
  p = vec2(cos(a0), sin(a0)) * r0;

  float r = length(p);
  float ang = atan(p.y, p.x);

  // Nucleus — soft core that blooms with amplitude.
  float coreR = 0.16 + 0.05 * amp + 0.03 * listenW + 0.04 * speakW - 0.02 * thinkW;
  float nucleus = exp(-pow(r / max(coreR, 0.04), 2.2));
  float inner = exp(-pow(r / max(coreR * 0.45, 0.02), 2.8));

  // Iris rings: listening = inbound, speaking = outbound, thinking = standing interference.
  float waveDir = mix(1.0, -1.0, speakW) * mix(1.0, 0.15, thinkW);
  float waveSpeed = mix(0.55, 1.35, listenW + speakW) + thinkW * 0.25;
  float rings = 0.0;
  rings += 0.55 * saturate(1.0 - abs(sin(r * 18.0 + t * waveSpeed * 4.0 * waveDir)) * 3.2);
  rings += 0.35 * saturate(1.0 - abs(sin(r * 11.0 - t * waveSpeed * 2.4 * waveDir + ang * 2.0)) * 2.6);
  rings *= smoothstep(0.85, 0.12, r) * smoothstep(0.02, 0.14, r);
  rings *= 0.25 + 0.75 * (listenW + speakW) + 0.35 * thinkW + 0.15 * idleW;
  rings *= 0.55 + amp * 0.9 + high * 0.35;

  // Filaments — polar FBM spokes. Tangled when thinking, radial when speaking.
  vec2 polar = vec2(ang * 0.55, r * 3.4 - t * (0.22 + speakW * 0.45 - listenW * 0.35));
  polar.x += thinkW * fbm(vec2(ang, t * 0.15), 3) * (1.2 + chaos);
  float fil = fbm(polar * (1.6 + mid * 0.8), octaves);
  float filaments = pow(saturate(fil * 1.15), mix(2.8, 1.6, speakW + listenW));
  filaments *= smoothstep(1.15, 0.08, r) * (0.35 + 0.65 * smoothstep(0.0, 0.55, r));
  filaments *= 0.4 + 0.6 * idleW + 0.85 * listenW + (0.7 + chaos) * thinkW + (0.9 + amp) * speakW;

  // Inward (listen) / outward (speak) shockwave fronts.
  float frontPhase = fract(t * mix(0.35, 0.9, amp) * (listenW + speakW + 0.0001));
  float listenFront = abs(r - (0.85 - frontPhase * 0.85));
  float speakFront = abs(r - frontPhase * 0.9);
  float fronts = 0.0;
  fronts += listenW * (0.35 + amp) * exp(-listenFront * 28.0) * smoothstep(0.02, 0.1, r);
  fronts += speakW * (0.45 + amp) * exp(-speakFront * 22.0) * smoothstep(0.05, 0.18, r);

  // Thinking orbiters — two faint satellites tracing the corona.
  float orb = 0.0;
  for (int i = 0; i < 2; i++) {
    float fi = float(i);
    float oa = t * (0.7 + fi * 0.35) + fi * 2.2 + prog * 6.28318;
    float orad = 0.28 + 0.08 * sin(t * 0.9 + fi) + 0.05 * chaos;
    vec2 op = vec2(cos(oa), sin(oa)) * orad;
    orb += exp(-length(p - op) * 38.0);
  }
  orb *= thinkW * (0.55 + 0.45 * chaos);

  // Palette: idle teal, listen cooler cyan, think deeper indigo fold, speak warmer amber lift.
  vec3 idleCol = mix(u_color_a, u_color_b, 0.35 + 0.2 * breath);
  vec3 listenCol = mix(u_color_b, u_color_a, 0.25 - amp * 0.15);
  vec3 thinkCol = mix(u_color_a * 0.65, vec3(0.28, 0.22, 0.55), 0.35 + chaos * 0.4);
  vec3 speakCol = mix(u_color_a, u_color_c, 0.25 + amp * 0.55);
  vec3 base = idleCol * idleW + listenCol * listenW + thinkCol * thinkW + speakCol * speakW;
  base /= max(idleW + listenW + thinkW + speakW, 0.001);

  vec3 col = u_bg;
  col += base * nucleus * (1.15 + amp * 0.8 + speakW * 0.35);
  col += mix(u_color_b, vec3(1.0), 0.35) * inner * (0.55 + speakW * 0.5);
  col += base * filaments * (0.55 + 0.45 * attn);
  col += mix(base, u_color_b, 0.4) * rings * 0.85;
  col += mix(u_color_b, u_color_c, speakW) * fronts * 1.4;
  col += mix(u_color_b, u_color_c, 0.3) * orb * 1.6;

  // Rim glow / corona falloff.
  float corona = pow(saturate(1.0 - r * 0.95), 2.4) * (0.18 + 0.22 * listenW + 0.28 * speakW + 0.12 * thinkW);
  col += base * corona;

  // Fine high-frequency sparkle (high band + speaking sibilance).
  float spark = hash21(fragCoord * 0.7 + t * 12.0);
  col += spark * spark * high * (0.08 + 0.12 * speakW + 0.06 * listenW);

  // Vignette + grain (hides banding on mobile).
  vec2 q = fragCoord / res;
  float vig = pow(16.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y), 0.35);
  col *= mix(0.55, 1.0, vig);
  float grain = (hash21(fragCoord + fract(t * 19.7)) - 0.5) * 0.035;
  col += grain;

  // Soft Reinhard tonemap so blooms don't clip to chalk.
  col = col / (1.0 + col * 0.65);
  col = mix(u_bg, col, 1.0);

  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
