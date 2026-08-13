#include <metal_stdlib>
using namespace metal;

// thoughtform — Alfred presence shader (Metal)
// Keep math in lockstep with shaders/thoughtform.frag.glsl.

// Packed as float4 so Swift SIMD4 layout matches Metal (no float3 padding traps).
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

float fbm(float2 p, int octaves) {
  float v = 0.0;
  float a = 0.5;
  float2x2 m = float2x2(1.6, 1.2, -1.2, 1.6);
  for (int i = 0; i < 6; i++) {
    if (i >= octaves) break;
    v += a * vnoise(p);
    p = m * p;
    a *= 0.5;
  }
  return v;
}

fragment float4 thoughtform_fragment(VertexOut in [[stage_in]],
                                    constant ThoughtformUniforms &u [[buffer(0)]]) {
  float2 fragCoord = in.position.xy;
  float2 res = max(u.resolutionTimeAmplitude.xy, float2(1.0));
  float2 uv = (fragCoord - 0.5 * res) / min(res.x, res.y);
  uv.y *= -1.0; // Metal origin is top-left; match GLSL y-up.

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

  int octaves = u.attentionChaosQuality.z > 0.75 ? 5 : (u.attentionChaosQuality.z > 0.4 ? 4 : 3);

  float breathHz = mix(0.35, 0.85, listenW) + speakW * (1.4 + amp * 2.2);
  float breath = sin(t * breathHz * 6.28318);
  float breathAmt = 0.018 * idleW + 0.04 * listenW + 0.012 * thinkW + 0.055 * speakW * (0.35 + amp);

  float radiusScale = 1.0
    + breath * breathAmt
    + 0.12 * amp * (listenW + speakW)
    + 0.08 * low
    + 0.06 * attn
    - 0.04 * thinkW;

  float2 p = uv / max(radiusScale, 0.25);

  float warp = 0.04 * idleW + 0.07 * listenW + (0.16 + 0.22 * chaos) * thinkW + 0.05 * speakW;
  warp += 0.06 * mid;
  float wt = t * (0.11 + thinkW * 0.18);
  float2 warpVec = float2(
    fbm(p * 2.15 + float2(wt, 0.0), octaves),
    fbm(p * 2.15 + float2(8.1, -wt), octaves)
  ) * 2.0 - 1.0;
  p += warpVec * warp;

  float r0 = length(p);
  float a0 = atan2(p.y, p.x);
  float spiral = thinkW * (0.35 + 0.65 * chaos) * (0.55 + 0.45 * sin(t * 0.7));
  a0 += r0 * spiral * 1.8 + t * (0.08 * idleW - 0.22 * listenW + 0.14 * thinkW + 0.18 * speakW);
  p = float2(cos(a0), sin(a0)) * r0;

  float r = length(p);
  float ang = atan2(p.y, p.x);

  float coreR = 0.16 + 0.05 * amp + 0.03 * listenW + 0.04 * speakW - 0.02 * thinkW;
  float nucleus = exp(-pow(r / max(coreR, 0.04), 2.2));
  float inner = exp(-pow(r / max(coreR * 0.45, 0.02), 2.8));

  float waveDir = mix(1.0, -1.0, speakW) * mix(1.0, 0.15, thinkW);
  float waveSpeed = mix(0.55, 1.35, listenW + speakW) + thinkW * 0.25;
  float rings = 0.0;
  rings += 0.55 * saturate(1.0 - abs(sin(r * 18.0 + t * waveSpeed * 4.0 * waveDir)) * 3.2);
  rings += 0.35 * saturate(1.0 - abs(sin(r * 11.0 - t * waveSpeed * 2.4 * waveDir + ang * 2.0)) * 2.6);
  rings *= smoothstep(0.85, 0.12, r) * smoothstep(0.02, 0.14, r);
  rings *= 0.25 + 0.75 * (listenW + speakW) + 0.35 * thinkW + 0.15 * idleW;
  rings *= 0.55 + amp * 0.9 + high * 0.35;

  float2 polar = float2(ang * 0.55, r * 3.4 - t * (0.22 + speakW * 0.45 - listenW * 0.35));
  polar.x += thinkW * fbm(float2(ang, t * 0.15), 3) * (1.2 + chaos);
  float fil = fbm(polar * (1.6 + mid * 0.8), octaves);
  float filaments = pow(saturate(fil * 1.15), mix(2.8, 1.6, speakW + listenW));
  filaments *= smoothstep(1.15, 0.08, r) * (0.35 + 0.65 * smoothstep(0.0, 0.55, r));
  filaments *= 0.4 + 0.6 * idleW + 0.85 * listenW + (0.7 + chaos) * thinkW + (0.9 + amp) * speakW;

  float frontPhase = fract(t * mix(0.35, 0.9, amp) * (listenW + speakW + 0.0001));
  float listenFront = abs(r - (0.85 - frontPhase * 0.85));
  float speakFront = abs(r - frontPhase * 0.9);
  float fronts = 0.0;
  fronts += listenW * (0.35 + amp) * exp(-listenFront * 28.0) * smoothstep(0.02, 0.1, r);
  fronts += speakW * (0.45 + amp) * exp(-speakFront * 22.0) * smoothstep(0.05, 0.18, r);

  float orb = 0.0;
  for (int i = 0; i < 2; i++) {
    float fi = float(i);
    float oa = t * (0.7 + fi * 0.35) + fi * 2.2 + prog * 6.28318;
    float orad = 0.28 + 0.08 * sin(t * 0.9 + fi) + 0.05 * chaos;
    float2 op = float2(cos(oa), sin(oa)) * orad;
    orb += exp(-length(p - op) * 38.0);
  }
  orb *= thinkW * (0.55 + 0.45 * chaos);

  float3 colorA = u.colorA.xyz;
  float3 colorB = u.colorB.xyz;
  float3 colorC = u.colorC.xyz;
  float3 background = u.background.xyz;

  float3 idleCol = mix(colorA, colorB, 0.35 + 0.2 * breath);
  float3 listenCol = mix(colorB, colorA, 0.25 - amp * 0.15);
  float3 thinkCol = mix(colorA * 0.65, float3(0.28, 0.22, 0.55), 0.35 + chaos * 0.4);
  float3 speakCol = mix(colorA, colorC, 0.25 + amp * 0.55);
  float3 base = idleCol * idleW + listenCol * listenW + thinkCol * thinkW + speakCol * speakW;
  base /= max(idleW + listenW + thinkW + speakW, 0.001);

  float3 col = background;
  col += base * nucleus * (1.15 + amp * 0.8 + speakW * 0.35);
  col += mix(colorB, float3(1.0), 0.35) * inner * (0.55 + speakW * 0.5);
  col += base * filaments * (0.55 + 0.45 * attn);
  col += mix(base, colorB, 0.4) * rings * 0.85;
  col += mix(colorB, colorC, speakW) * fronts * 1.4;
  col += mix(colorB, colorC, 0.3) * orb * 1.6;

  float corona = pow(saturate(1.0 - r * 0.95), 2.4) * (0.18 + 0.22 * listenW + 0.28 * speakW + 0.12 * thinkW);
  col += base * corona;

  float spark = hash21(fragCoord * 0.7 + t * 12.0);
  col += spark * spark * high * (0.08 + 0.12 * speakW + 0.06 * listenW);

  float2 q = fragCoord / res;
  float vig = pow(16.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y), 0.35);
  col *= mix(0.55, 1.0, vig);
  float grain = (hash21(fragCoord + fract(t * 19.7)) - 0.5) * 0.035;
  col += grain;

  col = col / (1.0 + col * 0.65);
  return float4(saturate(col), 1.0);
}
