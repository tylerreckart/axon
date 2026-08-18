#version 300 es
precision highp float;

// axon — Alfred presence shader (GLSL ES 3.00 / WebGL 2)
// Particle blob: Fibonacci sphere of soft point sprites, noise-displaced.
// Inspired by Eli Fitch's #3December blob (codepen.io/elifitch/pen/opNeMW).
// Keep math in lockstep with shaders/axon.metal.

layout(location = 0) out vec4 fragColor;

uniform vec2 u_resolution;
uniform float u_time;
uniform vec4 u_weights;    // idle, listen, think, speak
uniform float u_amplitude;
uniform vec3 u_bands;
uniform float u_progress;
uniform float u_attention;
uniform float u_chaos;
uniform float u_quality;
uniform vec3 u_color_a;
uniform vec3 u_color_b;
uniform vec3 u_color_c;
uniform vec3 u_bg;

const int MAX_N = 240;
const float GOLDEN_ANGLE = 2.399963229728653;

float hash31(vec3 p) {
  p = fract(p * vec3(123.34, 456.21, 789.13));
  p += dot(p, p.yzx + 45.32);
  return fract(p.x * p.y * p.z);
}

float vnoise3(vec3 p) {
  vec3 i = floor(p);
  vec3 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float n000 = hash31(i);
  float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
  float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
  float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
  float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
  float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
  float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
  float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
  return mix(
    mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
    mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
    f.z);
}

vec3 rotY(vec3 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

vec3 rotX(vec3 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec3(p.x, c * p.y - s * p.z, s * p.y + c * p.z);
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
  float quality = saturate(u_quality);

  float breathHz = mix(0.08, 0.13, listenW) + speakW * 0.10;
  float breath = 0.55 * sin(t * breathHz * 6.28318)
    + 0.30 * sin(t * breathHz * 2.15 + 1.1)
    + 0.15 * sin(t * breathHz * 0.73 + 2.4);

  float jaw = speakW * amp;
  float vowel = speakW * low;
  float sibilant = speakW * high;

  float radius = 0.44
    + 0.020 * breath * (1.0 - 0.7 * speakW)
    + 0.022 * amp * listenW
    + 0.048 * jaw
    + 0.016 * vowel
    + 0.010 * attn
    + 0.006 * low
    - 0.026 * thinkW;

  float disp = 0.36
    + thinkW * (0.16 + 0.20 * chaos)
    + speakW * (0.04 + 0.26 * amp + 0.10 * low)
    - listenW * 0.09;

  float lum = idleW * 0.78 + listenW * 0.98 + thinkW * 0.82
    + speakW * (0.68 + 0.88 * amp + 0.20 * high);
  lum += 0.10 * listenW * amp;
  lum += 0.05 * breath * (1.0 - 0.8 * speakW);

  float spin = t * (0.10 + thinkW * 0.05 + speakW * 0.025);
  float tilt = 0.42 + 0.05 * sin(t * 0.07 + prog);

  int N = int(mix(140.0, 240.0, quality) + 0.5);
  float nCount = float(N);
  float bound = radius * (1.0 + disp) * mix(1.55, 1.82, speakW);
  if (length(uv) > bound) {
    fragColor = vec4(u_bg, 1.0);
    return;
  }

  float sprite = mix(0.0072, 0.0048, quality);
  sprite *= 1.0 + 0.28 * jaw + 0.14 * sibilant;

  vec3 col = u_bg;
  for (int i = 0; i < MAX_N; i++) {
    if (i >= N) break;
    float fi = float(i) + 0.5;
    float y = 1.0 - (fi * 2.0) / nCount;
    float rxy = sqrt(max(1.0 - y * y, 0.0));
    float phi = fi * GOLDEN_ANGLE;
    vec3 p = vec3(cos(phi) * rxy, y, sin(phi) * rxy);

    float n = vnoise3(p * 1.65 + vec3(t * mix(0.08, 0.16, jaw), t * 0.05, prog * 0.5));
    float n2 = vnoise3(p * 3.05 + vec3(8.1, t * 0.04, 2.4));
    float field = n * 0.72 + n2 * 0.28;
    float bump = field * 2.0 - 0.92;
    float stray = hash31(vec3(fi, 4.2, 9.1));
    float mouth = saturate(1.0 - abs(y) * 1.65);
    float rad = radius * (1.0 + disp * bump + thinkW * chaos * 0.18 * stray
      + speakW * (0.10 * amp + 0.06 * low) * mouth);
    p *= rad;
    p = rotY(rotX(p, tilt), spin);
    p.x *= 1.0 + 0.18 * jaw + 0.10 * vowel;
    p.y *= 1.0 - 0.22 * jaw;
    p.z *= 1.0 - 0.05 * jaw;

    float persp = 1.15 / (1.55 - 0.42 * p.z);
    vec2 q = p.xy * persp;
    float d = length(uv - q);
    float sz = sprite * persp;
    float core = exp(-d * d / max(sz * sz * 0.55, 1e-6));
    float glow = exp(-d * d / max(sz * sz * 3.6, 1e-6));
    float halo = exp(-d * d / max(sz * sz * 9.0, 1e-6));
    float s = core + glow * 0.16 + halo * 0.05;

    float shade = 0.28 + 0.72 * saturate(0.5 + 0.55 * p.z);
    vec3 tint = mix(mix(u_color_a, u_color_b, 0.35), u_color_c, saturate(field));

    float phase = stray * 6.28318;
    float sparkIdle = 0.5 + 0.5 * sin(t * (0.85 + listenW * 0.55) + phase);
    float sparkVoice = saturate(0.12 + amp * 0.95 + high * (0.35 + 0.85 * stray)
      + 0.08 * sin(t * 8.5 + phase));
    float spark = mix(sparkIdle, sparkVoice, speakW);
    spark = mix(spark, spark * spark, speakW * 0.22);
    float band = mix(low, mix(mid, high, stray), stray);
    float live = listenW * (0.58 + 0.32 * amp) + speakW * (0.40 + 0.60 * amp);
    float bright = mix(0.62, 1.18, stray) * mix(0.88, 1.16, saturate(field));
    bright *= mix(1.0, mix(0.28, 1.65, spark), live);
    bright *= 1.0 + live * band * mix(-0.08, 0.42, spark);
    bright *= 1.0 + speakW * amp * 0.38 * mouth;

    col += tint * s * shade * lum * 0.52 * bright;
  }

  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
