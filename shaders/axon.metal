#include <metal_stdlib>
using namespace metal;

// axon — Alfred presence shader (Metal)
// A small, friendly presence. Soft PLATO orb that reads on a phone
// or a tiny OLED. Keep math in lockstep with shaders/axon.frag.glsl.

struct AxonUniforms {
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

vertex VertexOut axon_vertex(uint vertexID [[vertex_id]]) {
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

fragment float4 axon_fragment(VertexOut in [[stage_in]],
                                    constant AxonUniforms &u [[buffer(0)]]) {
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
  float quality = saturate(u.attentionChaosQuality.z);

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

  float2 p = uv / max(radius, 0.04);
  p += 0.018 * float2(sin(t * 0.27 + 0.4), cos(t * 0.23 + 1.2));
  float ang = atan2(p.y, p.x);
  float rd = length(p);

  float warp = 0.038 * sin(ang * 2.0 + t * 0.20)
    + 0.024 * sin(ang * 3.0 - t * 0.15 + breath)
    + 0.014 * sin(ang * 5.0 + t * 0.11 + prog * 6.28318)
    + speakW * (0.028 + 0.045 * amp) * sin(ang * 2.0 + t * 1.05)
    + thinkW * (0.04 + 0.05 * chaos) * (vnoise(p * 1.7 + t * 0.06) - 0.5);
  float sd = rd / max(1.0 + warp, 0.72);

  float halo = exp(-sd * sd * 3.4);
  float body = exp(-sd * sd * mix(5.4, 6.4, thinkW));
  float core = exp(-sd * sd * 9.5);

  float lum = idleW * 0.62 + listenW * 0.90 + thinkW * 0.72 + speakW * 1.04;
  lum += (0.14 * listenW + 0.18 * speakW) * amp;
  lum += 0.08 * breath;

  float attend = listenW * (0.07 + 0.16 * amp)
    * exp(-abs(sd - (0.55 + 0.18 * sin(t * 1.35))) * 6.5);
  float voice = speakW * amp * body * 0.18;

  float3 colorA = u.colorA.xyz;
  float3 colorB = u.colorB.xyz;
  float3 colorC = u.colorC.xyz;
  float3 background = u.background.xyz;

  float swirl = 0.5 + 0.5 * sin(ang + t * 0.19);
  float mottling = vnoise(p * 1.6 + float2(t * 0.06, 0.3));
  float ab = saturate(0.28 + 0.40 * sd + 0.18 * swirl + 0.14 * mottling);
  float bc = saturate(0.15 + 0.70 * core + 0.15 * sin(ang * 2.0 - t * 0.23));
  float3 plasma = mix(colorA, colorB, ab);
  float3 hot = mix(colorB, colorC, bc);

  float3 col = background;
  col += mix(colorA, plasma, 0.55) * halo * 0.05 * lum;
  col += plasma * body * 0.82 * lum;
  col += hot * core * 0.55 * lum;
  col += colorB * attend;
  col += hot * voice;

  float2 glintP = p - float2(-0.16, 0.20);
  col += colorC * exp(-dot(glintP, glintP) * 16.0) * 0.20 * lum;

  float lit = saturate(dot(col - background, float3(0.33)));
  float g1 = hash21(fragCoord * 0.91 + float2(t * 1.6, 2.1)) - 0.5;
  float g2 = hash21(fragCoord * 1.73 + float2(t * 2.2, 8.4)) - 0.5;
  float grain = g1 * 0.65 + g2 * 0.35;
  col += grain * mix(0.045, 0.075, quality) * mix(0.4, 1.0, lit) * plasma;

  return float4(saturate(col), 1.0);
}
