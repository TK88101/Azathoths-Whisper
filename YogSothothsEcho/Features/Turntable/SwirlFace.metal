#include <metal_stdlib>
using namespace metal;

// CR-037 SWIRL 系列的盤面烘焙（yse-swirl-style.md §4.4）：小樣 swirl-preview.html／swirl-color-preview.html 的片段著色器逐式移植
// （value noise＋5 階 fBm＋domain warp）。每首歌只烘一次（M1 成品圖），播放時只旋轉圖片
static float h3(float3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
static float n3(float3 x) {
    float3 i = floor(x), f = fract(x); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(h3(i), h3(i + float3(1,0,0)), f.x), mix(h3(i + float3(0,1,0)), h3(i + float3(1,1,0)), f.x), f.y),
               mix(mix(h3(i + float3(0,0,1)), h3(i + float3(1,0,1)), f.x), mix(h3(i + float3(0,1,1)), h3(i + float3(1,1,1)), f.x), f.y), f.z);
}
static float fbm(float3 p) { float a = 0.5, s = 0.0; for (int i = 0; i < 5; i++) { s += a * n3(p); p = p * 2.03 + float3(1.7, 9.2, 3.1); a *= 0.5; } return s; }

// q：盤面座標（半徑 1，y 向下）；type 0 smoke／1 pull／2 flake／3 chunk；回傳 (ink, accent) 覆蓋度
static float2 swirlMasks(float2 q, float seed, float type, float body, float depthFloor, float waterGain) {
    float r = length(q); if (r > 1.0) return float2(0);
    float th = atan2(q.y, q.x); float3 off = float3(seed * 13.1, seed * 7.7, seed * 3.3); float ink = 0, acc = 0;
    if (type < 0.5) {
        float tw = 1.6 * fbm(float3(q * 1.4, 1.0) + off); float t = th + tw; float3 P = float3(cos(t) * 1.3, sin(t) * 1.3, r * 3.2) + off;
        float3 w = float3(fbm(P), fbm(P + float3(5.2, 1.3, 2.8)), fbm(P + float3(2.1, 7.4, 4.6))); float f = fbm(P + 2.2 * w);
        float fil = pow(1.0 - abs(2.0 * f - 1.0), 3.5); float cloud = smoothstep(0.62 - body * 0.25, 0.82, f);
        ink = clamp(fil * 0.55 + cloud * (0.35 + body), 0.0, 1.0);
        float depth = smoothstep(0.35, 0.65, fbm(P * 0.55 + w * 1.3 + float3(31.0))); ink = clamp(ink * mix(depthFloor, 1.9, depth), 0.0, 1.0);
        if (waterGain > 0.0) { float e = (1.0 - smoothstep(0.0, 0.01, abs(f - 0.62))) * smoothstep(0.55, 0.8, depth); ink = clamp(ink + e * waterGain, 0.0, 1.0); }
    } else if (type < 1.5) {
        float tw = 0.35 * fbm(float3(q * 2.0, 3.0) + off); float t = th + tw; float3 P = float3(cos(t) * 7.0, sin(t) * 7.0, r * 1.1) + off;
        float f = fbm(P + 1.2 * float3(fbm(P * 0.5), fbm(P * 0.5 + 4.0), 0.0)); float fine = fbm(float3(cos(t) * 28.0, sin(t) * 28.0, r * 2.0) + off);
        ink = clamp(smoothstep(0.55 - body * 0.2, 0.8, f) * 0.45 + smoothstep(0.62, 0.8, fine) * 0.2, 0.0, 1.0);
    } else if (type < 2.5) {
        float tw = 0.25 * fbm(float3(q * 3.0, 5.0) + off); float t = th + tw; float hair = fbm(float3(cos(t) * 45.0, sin(t) * 45.0, r * 2.5) + off);
        float3 F = float3(cos(t) * 11.0, sin(t) * 11.0, r * 5.0) + off; F += 0.8 * float3(fbm(F * 0.7), fbm(F * 0.7 + 3.0), 0.0);
        float fl = smoothstep(0.6, 0.7, fbm(F)) * smoothstep(0.35, 0.95, r);
        float dk = pow(1.0 - abs(2.0 * fbm(float3(cos(t) * 9.0, sin(t) * 9.0, r * 0.9) + off + float3(17.0)) - 1.0), 70.0);
        float haze = (1.0 - smoothstep(0.45, 0.8, r)) * 0.22;
        ink = clamp(max(fl * 0.95, smoothstep(0.55, 0.75, hair) * 0.18 + haze), 0.0, 1.0); acc = clamp(dk * 1.5, 0.0, 1.0) * 0.6;
    } else {
        float tw = 0.35 * fbm(float3(q * 1.8, 7.0) + off); float t = th + tw; float3 P = float3(cos(t) * 6.0, sin(t) * 6.0, r * 3.0) + off;
        float3 w = float3(fbm(P * 1.3), fbm(P * 1.3 + float3(4.1, 2.2, 6.3)), 0.0); float f = fbm(P * 1.6 + 1.6 * w);
        float cluster = smoothstep(0.6, 0.66, fbm(P * 0.45 + float3(41.0))); float chunk = smoothstep(0.66, 0.71, f) * cluster;
        float tail = pow(1.0 - abs(2.0 * f - 1.0), 9.0) * cluster * 0.45;
        float3 Q = float3(q * 2.0, 13.0) + off;
        acc = pow(1.0 - abs(2.0 * fbm(Q + 1.5 * float3(fbm(Q), fbm(Q + float3(3.7)), 0.0)) - 1.0), 8.0) * 0.12;
        ink = clamp((chunk + tail) * 1.7, 0.0, 1.0);
    }
    float rim = smoothstep(1.0, 0.985, r);
    return float2(ink, acc) * rim;
}

// 欄位順序與 SwirlBaker.Params 一致（12 個 float＋4 個 float4）
struct FaceParams { float seed, type, body, water, opacity, hasGrad, hasAcc, side, depthFloor, waterGain, pad0, pad1; float4 base, base2, ink, acc; };

// M1 成品：底色（或斜向漸變）＋花紋上色，整張乘不透明度，premultiplied
static float4 face(float2 px, constant FaceParams &u) {
    float2 q = (px / u.side) * 2.0 - 1.0; float r = length(q);
    if (r > 1.0) return float4(0);
    float3 col = u.hasGrad > 0.5 ? mix(u.base.rgb, u.base2.rgb, clamp((q.x + q.y + 2.0) / 4.0, 0.0, 1.0)) : u.base.rgb;
    float2 m = swirlMasks(q, u.seed, u.type, u.body, u.depthFloor, u.waterGain);
    if (u.type > 2.5) { if (u.hasAcc > 0.5) col = mix(col, u.acc.rgb, m.y); col = mix(col, u.ink.rgb, m.x); }
    else { col = mix(col, u.ink.rgb, m.x); if (u.hasAcc > 0.5) col = mix(col, u.acc.rgb, m.y); }
    float a = u.opacity * clamp((1.0 - r) * u.side * 0.5 + 0.5, 0.0, 1.0);
    return float4(col * a, a);
}

kernel void swirlFaceKernel(texture2d<float, access::write> out [[texture(0)]], constant FaceParams &u [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
    out.write(face(float2(gid) + 0.5, u), gid);
}
