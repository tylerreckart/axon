#include <metal_stdlib>
using namespace metal;

// thoughtform — Alfred presence shader (Metal)
// Contained Siri-like blob, rendered as a PLATO plasma-cell particle field.
// Keep math in lockstep with shaders/thoughtform.frag.glsl.

struct ThoughtformUniforms {
  float4 resolutionTimeAmplitude; // xy = resolution, z = time, w = amplitude
  float4 weights;                 // idle, listen, think, speak
  float4 bandsProgress;           // xyz = low/mid/high, w = progress
  float4 attentionChaosQuality;   // x = attention, y = chaos, z = quality
  float4 colorA;
  float4 colorB;
  float4 colorC;
  float4 background;
};

struct VertexOut {
  float4 position [[position]];
};

vertex VertexOut thoughtform_vertex(uint vertexID [[vertex_id]]) {
  float2 pos = float2(float((vertexID << 1) & 2), float(vertexID & 2));
  VertexOut out;
  out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
  return out;
}

float hash21(float2 p) {
  p = fract(p * float2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float vnoise(float2 p) {
  float2 i = floor(p);
  float2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash21(i);
  float b = hash21(i + float2(1.0, 0.0));
  float c = hash21(i + float2(0.0, 1.0));
  float d = hash21(i + float2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

fragment float4 thoughtform_fragment(VertexOut in [[stage_in]],
                                    constant ThoughtformUniforms &u [[buffer(0)]]) {
  float2 fragCoord = in.position.xy;
  float2 res = max(u.resolutionTimeAmplitude.xy, float2(1.0));
  float2 uv = (fragCoord - 0.5 * res) / min(res.x, res.y);
  uv.y *= -1.0;

  float idleW = saturate(u.weights.x);
  float listenW = saturate(u.weights.y);
  float thinkW = saturate(u.weights.z);
  float speakW = saturate(u.weights.w);

  float t = u.resolutionTimeAmplitude.z;
  float amp = saturate(u.resolutionTimeAmplitude.w);
  float low = saturate(u.bandsProgress.x);
  float mid = saturate(u.bandsProgress.y);
  float high = saturate(u.bandsProgress.z);
  float chaos = saturate(u.attentionChaosQuality.y);
  float attn = saturate(u.attentionChaosQuality.x);
  float prog = saturate(u.bandsProgress.w);

  float breathHz = mix(0.28, 0.7, listenW) + speakW * (1.15 + amp * 1.8);
  float breath = sin(t * breathHz * 6.28318);

  float radius = 0.33
    + 0.018 * breath * (0.7 * idleW + listenW + 0.4 * thinkW + speakW)
    + 0.05 * amp * (listenW + speakW)
    + 0.03 * low
    + 0.02 * attn
    - 0.025 * thinkW;

  float cells = mix(96.0, 148.0, saturate(u.attentionChaosQuality.z));
  float2 grid = uv * cells;
  float2 cellId = floor(grid);
  float2 cellF = fract(grid);
  float2 cellUV = (cellId + 0.5) / cells;

  float id = hash21(cellId);
  float id2 = hash21(cellId + 19.7);

  float dist0 = length(cellUV);
  float scatter = pow(saturate(dist0 / max(radius, 0.05)), 2.2);
  float scatterAmt = scatter * (0.045 + 0.16 * thinkW + 0.10 * chaos + 0.05 * speakW);
  scatterAmt *= mix(1.0, 0.35, listenW);
  float2 dir = cellUV / max(dist0, 1e-4);
  float spin = thinkW * (0.55 + chaos) * (t * 0.35 + id * 6.28318);
  float csp = cos(spin);
  float ssp = sin(spin);
  float2 scatterDir = float2(dir.x * csp - dir.y * ssp, dir.x * ssp + dir.y * csp);
  float2 sampleUV = cellUV + scatterDir * scatterAmt * (id - 0.32);

  float pa = atan2(sampleUV.y, sampleUV.x);
  float pr = length(sampleUV);
  pa += t * (0.05 * idleW + 0.18 * thinkW * (0.4 + chaos) - 0.12 * listenW);
  pr += listenW * (-0.025 * fract(t * 0.45 + id));
  sampleUV = float2(cos(pa), sin(pa)) * pr;

  float dist = length(sampleUV);
  float a = atan2(sampleUV.y, sampleUV.x);

  float blob = radius
    * (1.0
      + 0.045 * sin(a * 3.0 + t * 0.55)
      + 0.025 * sin(a * 5.0 - t * 0.4 + prog * 6.28318)
      + 0.04 * thinkW * (vnoise(sampleUV * 3.2 + t * 0.2) - 0.5));

  float core = saturate(1.0 - dist / max(blob, 0.04));
  float fill = mix(0.72, 0.95, listenW)
    * mix(1.0, 0.62 + 0.28 * chaos, thinkW)
    * mix(1.0, 0.88 + 0.28 * amp, speakW)
    * mix(1.0, 0.82, idleW * (1.0 - attn));
  float density = pow(core, mix(0.65, 1.15, thinkW)) * fill;
  density *= 0.78 + 0.22 * vnoise(sampleUV * 5.0 + float2(t * 0.15, mid));

  float wave = abs(fract(dist / max(blob, 0.04) - t * (0.55 + amp * 0.7)) - 0.12);
  float speakShell = speakW * (0.22 + 0.55 * amp) * step(wave, 1.6 / cells * 8.0) * core;
  density += speakShell;

  float inWave = abs(fract((blob - dist) / max(blob, 0.04) + t * 0.5) - 0.15);
  density += listenW * (0.12 + 0.35 * amp) * step(inWave, 2.2 / cells * 8.0) * core;

  float halo = smoothstep(blob * 1.75, blob * 0.95, dist) * smoothstep(blob * 0.7, blob * 1.05, dist);
  float stray = (0.018 + 0.07 * thinkW + 0.045 * chaos + 0.03 * speakW * amp) * halo;
  density = max(density, stray);

  float flickRate = mix(7.0, 16.0, high);
  float flick = 0.78 + 0.22 * hash21(cellId + floor(t * flickRate));
  density *= flick;

  float lit = step(id, saturate(density));
  float halfLit = step(id2, saturate(density * 0.45)) * (1.0 - lit);
  float intensity = lit * (0.42 + 0.58 * pow(core, 0.55))
    + halfLit * 0.22 * core;
  intensity *= 0.55 + 0.45 * (idleW * 0.75 + listenW + thinkW * 0.85 + speakW);
  intensity += lit * speakW * amp * 0.35 * core;
  intensity += lit * listenW * amp * 0.2 * core;

  float levels = 5.0;
  intensity = floor(intensity * levels + 0.0001) / levels;

  float2 cf = cellF - 0.5;
  float box = max(abs(cf.x), abs(cf.y));
  float pixel = 1.0 - step(0.36, box);
  float glow = exp(-box * 8.5) * 0.55;
  float cellMask = mix(glow, pixel + glow * 0.35, 0.85);

  float dust = step(hash21(cellId + 91.0), 0.0035) * 0.12;

  float3 colorA = u.colorA.xyz;
  float3 colorB = u.colorB.xyz;
  float3 colorC = u.colorC.xyz;
  float3 background = u.background.xyz;

  float3 plasma = mix(colorA, colorB, saturate(intensity * 1.15 + speakW * amp * 0.25));
  plasma = mix(plasma, colorC, speakW * amp * lit * core * 0.45);
  plasma *= 1.0 - thinkW * 0.12 * (1.0 - core);

  float3 col = background;
  col += plasma * intensity * cellMask;
  col += plasma * dust;
  col += colorB * lit * pixel * pow(core, 4.0) * 0.35;

  return float4(saturate(col), 1.0);
}
