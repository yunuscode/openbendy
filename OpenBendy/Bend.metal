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

// A bowed sheet fills the display vertically. The top strip and bottom hinge
// are pinned; curvature and diffusion develop through the body as the lid closes.
float4 arcEffect(float2 position, texture2d<float> desktop, constant Parameters &u) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);
    float p = saturate(u.effect.x);
    float strength = p * saturate(u.effect.y);
    float bodyY = saturate((position.y - 0.04) / 0.88);
    float envelope = pow(sin(M_PI_F * bodyY), 2.0);
    float width = 1.0 - 0.28 * strength * envelope;
    float left = (1.0 - width) * 0.5;
    float2 uv = float2((position.x - 0.5) / width + 0.5, position.y);
    float2 dimensions = max(float2(1), u.surface.yz);
    float blurResponse = (1.0 - exp(-5.5 * p)) / (1.0 - exp(-5.5));
    float diffusion = smoothstep(0.035, 0.16, position.y) * (1.0 - smoothstep(0.60, 0.94, position.y));
    float sigma = 0.034 * saturate(u.effect.z) * blurResponse * diffusion;
    float sigmaPixels = sigma * dimensions.y;
    float coverage = 1.0;
    if (left > 0.00001) {
        float slope = 0.14 * strength * M_PI_F / 0.88 * sin(2.0 * M_PI_F * bodyY) * dimensions.x / dimensions.y;
        float normalScale = rsqrt(1.0 + slope * slope);
        float edgeSigma = max(0.35, sigmaPixels);
        coverage = gaussianCoverage((position.x - left) * dimensions.x * normalScale, edgeSigma)
                 * gaussianCoverage((1.0 - left - position.x) * dimensions.x * normalScale, edgeSigma);
    }
    if (coverage < 0.00001) return float4(0, 0, 0, 1);
    float3 color;
    if (sigmaPixels < 0.35) {
        color = desktop.sample(s, uv, level(0)).rgb;
    } else {
        float2 sourceSigma = sigma * float2(dimensions.y / dimensions.x / width, 1.0);
        float lod = max(0.0, log2(max(1.0, max(sourceSigma.x * dimensions.x, sourceSigma.y * dimensions.y) * 1.25)));
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
    color *= 1.0 - 0.30 * p * saturate(u.effect.w) * envelope;
    return float4(color * coverage, 1);
}

// Two leaves share a vertical spine. The left leaf swings toward the viewer
// and over the right one. Fit the nearest edge inside the display throughout.
float4 bookEffect(float2 position, texture2d<float> desktop, constant Parameters &u) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);
    float angle = saturate(u.effect.x) * saturate(u.effect.y) * M_PI_F * 0.96;
    float c = cos(angle), bend = sin(angle);
    float q = 0.22 * bend, fit = 1.0 - q;
    float2 size = max(float2(1), u.surface.yz);
    float2 d = position - 0.5;
    float3 result = float3(0);

    // Stationary leaf, with a contact shadow that widens as the cover lifts.
    float2 rightUV = d / fit + 0.5;
    float rightCoverage = saturate((fit * 0.5 - d.x) * size.x + 0.5)
                        * saturate((fit * 0.5 - abs(d.y)) * size.y + 0.5);
    if (d.x >= 0.0 && rightCoverage > 0.0) {
        float shadow = 0.42 * saturate(u.effect.w) * bend * exp(-max(0.0, rightUV.x - 0.5) / (0.015 + 0.12 * bend));
        result = desktop.sample(s, rightUV, level(0)).rgb * (1.0 - shadow) * rightCoverage;
    }

    // Projected edge-to-spine interval. Its coverage vanishes continuously at
    // edge-on; avoid dividing by the singular homography at ninety degrees.
    float outer = -0.5 * c;
    float leafWidthPixels = abs(outer) * size.x;
    if (leafWidthPixels > 0.001) {
        float horizontal = saturate((d.x - min(0.0, outer)) * size.x + 0.5)
                         * saturate((max(0.0, outer) - d.x) * size.x + 0.5);
        horizontal *= min(1.0, leafWidthPixels);
        float denominator = fit * c - 2.0 * q * d.x;
        if (horizontal > 0.0 && abs(denominator) > 0.000001) {
            float t = saturate(-2.0 * d.x / denominator);
            float depth = 1.0 - q * t;
            float halfHeight = 0.5 * fit / depth;
            float coverage = horizontal * saturate((halfHeight - abs(d.y)) * size.y + 0.5);
            float2 uv = float2(0.5 - 0.5 * t, d.y * depth / fit + 0.5);
            // Mips stabilize detail during foreshortening. Optional diffusion
            // stays close to the crease, leaving the broad faces readable.
            float compression = depth * depth / max(0.00001, fit * abs(c));
            float crease = exp(-t / 0.065);
            float diffusion = 0.003 * size.y * saturate(u.effect.z) * bend * crease;
            float lod = max(0.0, log2(max(compression, max(1.0, diffusion))));
            float shade = 1.0 - saturate(u.effect.w) * bend * (0.35 + 0.30 * crease);
            float3 face = desktop.sample(s, uv, level(lod)).rgb * shade;
            result = mix(result, face, coverage);
        }
    }
    return float4(result, 1);
}

fragment float4 bendFragment(Varying in [[stage_in]], texture2d<float> desktop [[texture(0)]], constant Parameters &u [[buffer(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);
    float p = saturate(u.effect.x);
    if (p <= 0.00001) return float4(desktop.sample(s, in.uv, level(0)).rgb, 1);
    if (u.surface.x > 3.5) return bookEffect(in.uv, desktop, u);
    if (u.surface.x > 2.5) return arcEffect(in.uv, desktop, u);

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
