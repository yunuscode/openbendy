#include <metal_stdlib>
using namespace metal;

struct Varying { float4 position [[position]]; float2 uv; };
struct Parameters { float4 effect; float4 surface; };

vertex Varying bendVertex(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    Varying o; o.uv = p;
    o.position = float4(p.x * 2 - 1, 1 - p.y * 2, 0, 1);
    return o;
}

// Smooth Gaussian coverage of a blurred silhouette, including pixels outside it.
// Keeping coverage separate avoids sparse blur taps leaving stripes along an edge.
float gaussianCoverage(float distance, float sigma) {
    float x = distance / max(sigma, 0.0001);
    float t = 1.0 / (1.0 + 0.2316419 * abs(x));
    float tail = 0.39894228 * exp(-0.5 * x * x) * t *
        (0.31938153 + t * (-0.35656378 + t * (1.78147794 + t * (-1.82125598 + t * 1.33027443))));
    return x >= 0.0 ? 1.0 - tail : tail;
}

fragment float4 bendFragment(Varying in [[stage_in]], texture2d<float> desktop [[texture(0)]], constant Parameters &u [[buffer(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);
    float p = saturate(u.effect.x);
    if (p <= 0.00001) return float4(desktop.sample(s, in.uv, level(0)).rgb, 1);

    // Project a plane rotating away from a fixed bottom hinge. Blur has a separate,
    // earlier response; compression develops gradually instead of appearing with it.
    float angle = pow(p, 1.12) * saturate(u.effect.y) * 1.40;
    float c = cos(angle), q = 0.12 * sin(angle);
    float top = 1.0 - c / (1.0 + q);
    float heightFromHinge = 1.0 - in.uv.y;
    float sourceHeight = heightFromHinge / max(0.02, c - q * heightFromHinge);
    float w = 1.0 + q * sourceHeight;
    float2 uv = float2((in.uv.x - 0.5) * w + 0.5, 1.0 - sourceHeight);
    float upper = pow(saturate(sourceHeight), 1.25);
    float blurResponse = (1.0 - exp(-5.5 * p)) / (1.0 - exp(-5.5));
    float style = u.surface.x;
    float styleBlur = style > 1.5 ? 1.25 : 1.0;
    // Relative to display height, so Retina resolution does not change the material.
    float sigma = 0.022 * saturate(u.effect.z) * blurResponse * upper * styleBlur;
    float2 dimensions = max(float2(1), u.surface.yz);
    float sigmaPixels = sigma * dimensions.y;
    float projectedWidth = max(0.05, 1.0 - q * heightFromHinge / c);
    float left = (1.0 - projectedWidth) * 0.5;
    float edgeSigma = max(0.35, sigmaPixels);
    float coverage = gaussianCoverage((in.uv.y - top) * dimensions.y, edgeSigma);
    // Do not fade the physical screen sides for a zero-perspective, blur-only effect.
    if (q > 0.00001) {
        float slope = q * dimensions.x / (2.0 * c * dimensions.y);
        float normalScale = rsqrt(1.0 + slope * slope);
        coverage *= gaussianCoverage((in.uv.x - left) * dimensions.x * normalScale, edgeSigma);
        coverage *= gaussianCoverage((1.0 - left - in.uv.x) * dimensions.x * normalScale, edgeSigma);
    }
    if (coverage < 0.00001) return float4(0, 0, 0, 1);

    float3 color;
    if (sigmaPixels < 0.35) {
        color = desktop.sample(s, uv, level(0)).rgb;
    } else {
        // The inverse projective Jacobian preserves a screen-space blur footprint.
        float2 sourceSigma = sigma * float2(dimensions.y / dimensions.x * w, w * w / c);
        float lod = max(0.0, log2(max(1.0, max(sourceSigma.x * dimensions.x, sourceSigma.y * dimensions.y) * 0.65)));
        float3 sum = float3(0); float weight = 0;
        for (int i = 0; i < 24; i++) {
            float a = float(i) * 2.39996323;
            float r = sqrt((float(i) + 0.5) / 24.0) * 2.5;
            float tapWeight = exp(-0.5 * r * r);
            sum += desktop.sample(s, uv + float2(cos(a), sin(a)) * r * sourceSigma, level(lod)).rgb * tapWeight;
            weight += tapWeight;
        }
        color = sum / weight;
    }
    float shadeStrength = style > 0.5 && style < 1.5 ? 0.65 : (style > 1.5 ? 0.07 : 0.14);
    color *= 1.0 - p * saturate(u.effect.w) * upper * shadeStrength;
    // Frost changes diffusion, not the desktop's color with a milky overlay.
    return float4(color * coverage, 1);
}
