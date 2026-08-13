#version 300 es
precision highp float;

// thoughtform — Alfred presence shader (GLSL ES 3.00 / WebGL 2)
// Contained Siri-like blob, rendered as a PLATO plasma-cell particle field.
// Keep math in lockstep with shaders/thoughtform.metal.

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

  float breathHz = mix(0.28, 0.7, listenW) + speakW * (1.15 + amp * 1.8);
  float breath = sin(t * breathHz * 6.28318);

  // Contained orb — Siri-sized, slightly irregular, never a ring.
  float radius = 0.33
    + 0.018 * breath * (0.7 * idleW + listenW + 0.4 * thinkW + speakW)
    + 0.05 * amp * (listenW + speakW)
    + 0.03 * low
    + 0.02 * attn
    - 0.025 * thinkW;

  // Plasma panel: discrete cells with visible gutters (PLATO 512-ish feel).
  float cells = mix(96.0, 148.0, saturate(u_quality));
  vec2 grid = uv * cells;
  vec2 cellId = floor(grid);
  vec2 cellF = fract(grid);
  vec2 cellUV = (cellId + 0.5) / cells;

  float id = hash21(cellId);
  float id2 = hash21(cellId + 19.7);

  // Particle degradation: edge cells scatter off the body.
  float dist0 = length(cellUV);
  float scatter = pow(saturate(dist0 / max(radius, 0.05)), 2.2);
  float scatterAmt = scatter * (0.045 + 0.16 * thinkW + 0.10 * chaos + 0.05 * speakW);
  scatterAmt *= mix(1.0, 0.35, listenW); // listening holds together
  vec2 dir = cellUV / max(dist0, 1e-4);
  // Thinking twists the debris field; speaking throws it radially with the pulse.
  float spin = thinkW * (0.55 + chaos) * (t * 0.35 + id * 6.28318);
  float csp = cos(spin);
  float ssp = sin(spin);
  vec2 scatterDir = vec2(dir.x * csp - dir.y * ssp, dir.x * ssp + dir.y * csp);
  vec2 sampleUV = cellUV + scatterDir * scatterAmt * (id - 0.32);

  // Inward drift while listening; slow orbit while idle/think.
  float pa = atan(sampleUV.y, sampleUV.x);
  float pr = length(sampleUV);
  pa += t * (0.05 * idleW + 0.18 * thinkW * (0.4 + chaos) - 0.12 * listenW);
  pr += listenW * (-0.025 * fract(t * 0.45 + id));
  sampleUV = vec2(cos(pa), sin(pa)) * pr;

  float dist = length(sampleUV);
  float a = atan(sampleUV.y, sampleUV.x);

  // Soft Siri blob radius (still evaluated per-cell, so the silhouette stays crunchy).
  float blob = radius
    * (1.0
      + 0.045 * sin(a * 3.0 + t * 0.55)
      + 0.025 * sin(a * 5.0 - t * 0.4 + prog * 6.28318)
      + 0.04 * thinkW * (vnoise(sampleUV * 3.2 + t * 0.2) - 0.5));

  float core = saturate(1.0 - dist / max(blob, 0.04));
  // Filled presence, not a torus: high density in the interior, dithered decay at the rim.
  float fill = mix(0.72, 0.95, listenW)
    * mix(1.0, 0.62 + 0.28 * chaos, thinkW)
    * mix(1.0, 0.88 + 0.28 * amp, speakW)
    * mix(1.0, 0.82, idleW * (1.0 - attn));
  float density = pow(core, mix(0.65, 1.15, thinkW)) * fill;
  density *= 0.78 + 0.22 * vnoise(sampleUV * 5.0 + vec2(t * 0.15, mid));

  // Speech: discrete concentric particle shells (not a smooth shockwave).
  float wave = abs(fract(dist / max(blob, 0.04) - t * (0.55 + amp * 0.7)) - 0.12);
  float speakShell = speakW * (0.22 + 0.55 * amp) * step(wave, 1.6 / cells * 8.0) * core;
  density += speakShell;

  // Listen: inbound dotted ripples.
  float inWave = abs(fract((blob - dist) / max(blob, 0.04) + t * 0.5) - 0.15);
  density += listenW * (0.12 + 0.35 * amp) * step(inWave, 2.2 / cells * 8.0) * core;

  // Halo debris — particles that have already left the body.
  float halo = smoothstep(blob * 1.75, blob * 0.95, dist) * smoothstep(blob * 0.7, blob * 1.05, dist);
  float stray = (0.018 + 0.07 * thinkW + 0.045 * chaos + 0.03 * speakW * amp) * halo;
  density = max(density, stray);

  // Phosphor flicker (plasma cells never sit still).
  float flickRate = mix(7.0, 16.0, high);
  float flick = 0.78 + 0.22 * hash21(cellId + floor(t * flickRate));
  density *= flick;

  // Dithered particle gate — this is the degradation.
  float lit = step(id, saturate(density));

  // Dimmer secondary particles (half-lit cells) for volume.
  float halfLit = step(id2, saturate(density * 0.45)) * (1.0 - lit);
  float intensity = lit * (0.42 + 0.58 * pow(core, 0.55))
    + halfLit * 0.22 * core;
  intensity *= 0.55 + 0.45 * (idleW * 0.75 + listenW + thinkW * 0.85 + speakW);
  intensity += lit * speakW * amp * 0.35 * core;
  intensity += lit * listenW * amp * 0.2 * core;

  // Quantize to a handful of plasma brightness steps.
  float levels = 5.0;
  intensity = floor(intensity * levels + 0.0001) / levels;

  // Cell geometry: square plasma pixel with a gutter, plus a short bloom.
  vec2 cf = cellF - 0.5;
  float box = max(abs(cf.x), abs(cf.y));
  float pixel = 1.0 - step(0.36, box);
  float glow = exp(-box * 8.5) * 0.55;
  float cellMask = mix(glow, pixel + glow * 0.35, 0.85);

  // Sparse void dust — a few dead/warm pixels on the panel.
  float dust = step(hash21(cellId + 91.0), 0.0035) * 0.12;

  vec3 plasma = mix(u_color_a, u_color_b, saturate(intensity * 1.15 + speakW * amp * 0.25));
  plasma = mix(plasma, u_color_c, speakW * amp * lit * core * 0.45);
  // Thinking runs a hair dimmer / browner, like the panel is working.
  plasma *= 1.0 - thinkW * 0.12 * (1.0 - core);

  vec3 col = u_bg;
  col += plasma * intensity * cellMask;
  col += plasma * dust;

  // Tiny hot core highlight so the presence reads as a body, not a cloud.
  col += u_color_b * lit * pixel * pow(core, 4.0) * 0.35;

  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
