#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float contourHash(float2 point) {
    point = fract(point * float2(123.34, 456.21));
    point += dot(point, point + 45.32);
    return fract(point.x * point.y);
}

static float contourNoise(float2 point) {
    float2 cell = floor(point);
    float2 local = fract(point);
    float2 blend = local * local * (3.0 - 2.0 * local);
    float lowerLeft = contourHash(cell);
    float lowerRight = contourHash(cell + float2(1.0, 0.0));
    float upperLeft = contourHash(cell + float2(0.0, 1.0));
    float upperRight = contourHash(cell + float2(1.0, 1.0));
    return mix(
        mix(lowerLeft, lowerRight, blend.x),
        mix(upperLeft, upperRight, blend.x),
        blend.y
    );
}

static float contourFBM(float2 point, float detailScale) {
    float value = contourNoise(point) * 0.67;
    if (detailScale > 0.5) {
        value += contourNoise(point * 2.03 + 7.17) * 0.33;
    }
    return value * 2.0 - 1.0;
}

static float2 contourRotate(float2 point, float angle) {
    float sine = sin(angle);
    float cosine = cos(angle);
    return float2(
        cosine * point.x - sine * point.y,
        sine * point.x + cosine * point.y
    );
}

[[ stitchable ]]
half4 livingContours(
    float2 position,
    float2 canvasSize,
    float elapsedTime,
    float4 bandsLow,
    float4 bandsHigh,
    float rms,
    float peak,
    float audioResponseScale,
    float motionScale,
    float detailScale,
    half4 accent
) {
    if (canvasSize.x <= 0.0 || canvasSize.y <= 0.0) {
        return half4(0.0h);
    }
    float shortestSide = max(min(canvasSize.x, canvasSize.y), 1.0);
    float2 point = (position - canvasSize * 0.5) / shortestSide;
    float time = max(elapsedTime, 0.0);
    float response = clamp(audioResponseScale, 0.0, 1.0);

    float bass60 = bandsLow.x;
    float bass125 = bandsLow.y;
    float bass250 = bandsLow.z;
    float mid500 = bandsLow.w;
    float mid1k = bandsHigh.x;
    float mid2k = bandsHigh.y;
    float high4k = bandsHigh.z;
    float high8k = bandsHigh.w;
    float totalEnergy = clamp(rms * response, 0.0, 1.0);
    float peakEnergy = clamp(peak * response, 0.0, 1.0);
    float audioMotion = totalEnergy * clamp(motionScale, 0.0, 1.0);

    float preservedDrift = mix(
        0.35,
        1.0,
        clamp(motionScale, 0.0, 1.0)
    );
    float2 drift = float2(
        sin(time * (2.0 * M_PI_F / 11.0) + mid2k * audioMotion * 0.7),
        cos(time * (2.0 * M_PI_F / 13.0) - mid2k * audioMotion * 0.5)
    ) * (0.035 + mid2k * audioMotion * 0.020) * preservedDrift;
    point -= drift;

    float rotation = (
        sin(time * (2.0 * M_PI_F / 14.0)) * 0.22 * motionScale
        + mid1k * audioMotion * 0.14
        - mid2k * audioMotion * 0.08
    );
    point = contourRotate(point, rotation);

    float lineMask = 0.0;
    float glowMask = 0.0;
    for (int index = 0; index < 4; ++index) {
        float contourIndex = float(index);
        float radius = 0.26
            + contourIndex * (0.16 + bass125 * audioMotion * 0.012);
        radius += bass60 * audioMotion
            * (0.022 + contourIndex * 0.005);

        float angle = atan2(point.y, point.x);
        float lobe = sin(
            angle * (2.0 + contourIndex)
            + time * (0.18 + contourIndex * 0.025)
            + mid500 * audioMotion * 1.2
            + mid1k * audioMotion * 0.8
        );
        float breathing = sin(
            time * (2.0 * M_PI_F / (8.0 + contourIndex * 1.7))
            + contourIndex * 1.4
        );
        float2 noisePoint = point * (3.1 + contourIndex * 0.55);
        noisePoint += float2(time * 0.018, -time * 0.014);
        float noise = contourFBM(noisePoint, detailScale);

        float baselineDeformation = (
            lobe * 0.018 + breathing * 0.014 + noise * 0.022
        ) * motionScale;
        float audioDeformation = audioMotion * (
            bass250 * breathing * 0.032
            + mid500 * lobe * 0.018
            + mid1k * sin(angle * 3.0 - time * 0.13) * 0.018
            + mid2k * cos(angle * 5.0 + time * 0.17) * 0.014
            + high4k * noise * 0.016
        );

        float signedDistance = abs(
            length(point) - radius
            - baselineDeformation
            - audioDeformation
        );
        float antialias = max(fwidth(signedDistance), 0.001);
        float lineWidth = 0.0055 + high4k * totalEnergy * 0.0025;
        float glowWidth = lineWidth + 0.020
            + high8k * totalEnergy * 0.012;
        float contourLine = 1.0 - smoothstep(
            lineWidth,
            lineWidth + antialias,
            signedDistance
        );
        float contourGlow = 1.0 - smoothstep(
            lineWidth,
            glowWidth + antialias,
            signedDistance
        );
        lineMask = max(lineMask, contourLine);
        glowMask = max(glowMask, contourGlow);
    }

    float lineAlpha = clamp(
        0.10 + totalEnergy * 0.16 + peakEnergy * 0.04,
        0.10,
        0.30
    );
    float glowAlpha = clamp(
        totalEnergy * (0.10 + high4k * 0.03 + high8k * 0.05),
        0.0,
        0.18
    );
    float alpha = max(lineMask * lineAlpha, glowMask * glowAlpha);
    half outputAlpha = half(clamp(alpha, 0.0, 0.30));
    return half4(accent.rgb * outputAlpha, outputAlpha);
}
