#version 300 es
precision highp float;

// axon — Alfred presence shader (GLSL ES 3.00 / WebGL 2)
// A small, friendly presence. Soft PLATO orb that reads on a phone
// or a tiny OLED. Keep math in lockstep with shaders/axon.metal.

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

  // Slow, living breath — rate is stable so amplitude never FM-jitters it.
  float breathHz = mix(0.14, 0.22, listenW) + speakW * 0.18;
  float breath = 0.55 * sin(t * breathHz * 6.28318)
    + 0.30 * sin(t * breathHz * 2.15 + 1.1)
    + 0.15 * sin(t * breathHz * 0.73 + 2.4);

  float radius = 0.34
    + 0.018 * breath
    + 0.016 * amp * (0.55 * listenW + speakW)
    + 0.012 * attn
    + 0.008 * low
    - 0.018 * thinkW;

  vec2 p = uv / max(radius, 0.04);
  // Gentle swim so the whole presence feels fluid, not pinned.
  p += 0.018 * vec2(sin(t * 0.27 + 0.4), cos(t * 0.23 + 1.2));
  float ang = atan(p.y, p.x);
  float rd = length(p);

  // Soft rolling silhouette. Speak is a slow squash, not a twitch.
  float warp = 0.038 * sin(ang * 2.0 + t * 0.20)
    + 0.024 * sin(ang * 3.0 - t * 0.15 + breath)
    + 0.014 * sin(ang * 5.0 + t * 0.11 + prog * 6.28318)
    + speakW * (0.028 + 0.045 * amp) * sin(ang * 2.0 + t * 1.05)
    + thinkW * (0.04 + 0.05 * chaos) * (vnoise(p * 1.7 + t * 0.06) - 0.5);
  float sd = rd / max(1.0 + warp, 0.72);

  float halo = exp(-sd * sd * 3.4);
  float body = exp(-sd * sd * mix(5.4, 6.4, thinkW));
  float core = exp(-sd * sd * 9.5);

  // Idle stays visible. Ready, not asleep.
  float lum = idleW * 0.62 + listenW * 0.90 + thinkW * 0.72 + speakW * 1.04;
  lum += (0.14 * listenW + 0.18 * speakW) * amp;
  lum += 0.08 * breath;

  // Listening: a smooth inward swell. Speaking: a soft brightness follow.
  float attend = listenW * (0.07 + 0.16 * amp)
    * exp(-abs(sd - (0.55 + 0.18 * sin(t * 1.35))) * 6.5);
  float voice = speakW * amp * body * 0.18;

  float swirl = 0.5 + 0.5 * sin(ang + t * 0.19);
  float mottling = vnoise(p * 1.6 + vec2(t * 0.06, 0.3));
  float ab = saturate(0.28 + 0.40 * sd + 0.18 * swirl + 0.14 * mottling);
  float bc = saturate(0.15 + 0.70 * core + 0.15 * sin(ang * 2.0 - t * 0.23));
  vec3 plasma = mix(u_color_a, u_color_b, ab);
  vec3 hot = mix(u_color_b, u_color_c, bc);

  vec3 col = u_bg;
  col += mix(u_color_a, plasma, 0.55) * halo * 0.05 * lum;
  col += plasma * body * 0.82 * lum;
  col += hot * core * 0.55 * lum;
  col += u_color_b * attend;
  col += hot * voice;

  vec2 glintP = p - vec2(-0.16, 0.20);
  col += u_color_c * exp(-dot(glintP, glintP) * 16.0) * 0.20 * lum;

  float lit = saturate(dot(col - u_bg, vec3(0.33)));
  float g1 = hash21(fragCoord * 0.91 + vec2(t * 1.6, 2.1)) - 0.5;
  float g2 = hash21(fragCoord * 1.73 + vec2(t * 2.2, 8.4)) - 0.5;
  float grain = g1 * 0.65 + g2 * 0.35;
  col += grain * mix(0.045, 0.075, quality) * mix(0.4, 1.0, lit) * plasma;

  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
