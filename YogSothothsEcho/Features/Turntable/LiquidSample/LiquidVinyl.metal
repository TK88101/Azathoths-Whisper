#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// CR-038 液態黑膠小樣（yse-liquid-vinyl-sample.md v0.4 §4.3）：只在 Debug 建置（Release 以 EXCLUDED_SOURCE_FILE_NAMES 排除）。
// 每幀都跑：環帶外早退，8 顆染料團的高斯濃度＋2 階低頻起伏＋液面亮邊。
// 座標：盤半徑＝1、y 向下；角度以度計、順時針為正（與 SwiftUI rotationEffect 同向）。
// blobs：floatArray，每顆 4 個 float（核心半徑基準、角位置°、角向寬度°、濃度）

constant float kInner = 0.452;
constant float kOuter = 0.97;
constant float kFlingReach = 0.12;
constant float kRadialSigma = 0.025;   // 2σ＝0.05＝核心向內外延伸的寬度
constant float kMeniscusRadius = 0.965;
constant float kMeniscusWidth = 0.006;

static float wrapDegrees(float d) { return d - 360.0 * floor((d + 180.0) / 360.0); }

[[ stitchable ]] half4 liquidVinyl(float2 position, half4 color, float2 size,
                                   float discAngle, float lag, float fling, float gain,
                                   device const float *blobs, int floatCount) {
    float2 q = (position - size * 0.5) / (size.x * 0.5);
    float r = length(q);
    if (r < kInner || r > kOuter) { return half4(0.0); }

    float u = (r - kInner) / (kOuter - kInner);
    float theta = atan2(q.y, q.x) * 57.29578;
    // 液體座標：內圈跟盤（w＝0）、外圈落後最多（w＝1）
    float local = theta - discAngle + lag * u * u;

    float density = 0.0;
    // floatArray 傳的是 float 個數；最多 8 顆
    for (int i = 0; i + 3 < min(floatCount, 32); i += 4) {
        float rb = clamp(blobs[i] + kFlingReach * fling * gain, 0.51, 0.90);
        float dTheta = wrapDegrees(local - blobs[i + 1]) / blobs[i + 2];
        float dR = (r - rb) / kRadialSigma;
        density += blobs[i + 3] * exp(-0.5 * (dTheta * dTheta + dR * dR));
    }
    float rad = local * 0.01745329;
    float swell = 0.5 + 0.25 * sin(2.0 * rad + 3.0 * r) + 0.25 * sin(3.0 * rad - 5.0 * r + 1.3);
    density = clamp(density + 0.10 * swell, 0.0, 1.0);

    // 液面亮邊：外甩越大越粗
    float width = (1.0 + 2.0 * fling) * kMeniscusWidth;
    float edge = exp(-0.5 * pow((r - (kMeniscusRadius - width)) / width, 2.0)) * clamp(0.35 + 0.5 * fling, 0.0, 1.0);

    // 濃處深藍紫、淡處近透明（對比拉開，染料團要能逐格追蹤）
    float3 deep = float3(0.09, 0.03, 0.40);
    float3 pale = float3(0.45, 0.38, 0.90);
    float3 rgb = mix(pale, deep, smoothstep(0.1, 0.8, density));
    float alpha = smoothstep(0.04, 0.75, density) * 0.95;
    rgb = mix(rgb, float3(0.92, 0.90, 1.0), edge);
    alpha = max(alpha, edge * 0.8);
    return half4(half3(rgb * alpha), half(alpha));
}
