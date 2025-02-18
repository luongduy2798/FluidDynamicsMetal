//#include <metal_stdlib>
//using namespace metal;
//
//struct VertexIn {
//    float2 position [[attribute(0)]];
//};
//
//struct VertexOut {
//    float4 position [[position]];
//    float2 uv;
//    float2 vL;
//    float2 vR;
//    float2 vT;
//    float2 vB;
//};
//
//vertex VertexOut baseVertexShader(VertexIn in [[stage_in]], constant float2 &texelSize [[buffer(0)]]) {
//    VertexOut out;
//    out.uv = in.position * 0.5 + 0.5;
//    out.vL = out.uv - float2(texelSize.x, 0.0);
//    out.vR = out.uv + float2(texelSize.x, 0.0);
//    out.vT = out.uv + float2(0.0, texelSize.y);
//    out.vB = out.uv - float2(0.0, texelSize.y);
//    out.position = float4(in.position, 0.0, 1.0);
//    return out;
//}
//
//
//vertex VertexOut blurVertexShader(VertexIn in [[stage_in]], constant float2 &texelSize [[buffer(0)]]) {
//    VertexOut out;
//    out.uv = in.position * 0.5 + 0.5;
//    float offset = 1.33333333;
//    out.vL = out.uv - texelSize * offset;
//    out.vR = out.uv + texelSize * offset;
//    out.position = float4(in.position, 0.0, 1.0);
//    return out;
//}
//
//fragment half4 blurShader(VertexOut in [[stage_in]], texture2d<float, access::sample> uTexture [[texture(0)]]) {
//    constexpr sampler sampler2d(filter::linear);
//    half4 sum = half4(uTexture.sample(sampler2d, in.uv)) * 0.29411764;
//    sum += half4(uTexture.sample(sampler2d, in.vL)) * 0.35294117;
//    sum += half4(uTexture.sample(sampler2d, in.vR)) * 0.35294117;
//    return sum;
//}
//
//fragment half4 copyShader(VertexOut in [[stage_in]], texture2d<float, access::sample> uTexture [[texture(0)]]) {
//    constexpr sampler sampler2d(filter::linear);
//    return half4(uTexture.sample(sampler2d, in.uv));
//}
//
//fragment half4 clearShader(VertexOut in [[stage_in]], texture2d<float, access::sample> uTexture [[texture(0)]], constant float &value [[buffer(0)]]) {
//    constexpr sampler sampler2d(filter::linear);
//    return half4(value * uTexture.sample(sampler2d, in.uv));
//}
//
//fragment half4 colorShader(VertexOut in [[stage_in]], constant float4 &color [[buffer(0)]]) {
//    return half4(color);
//}
//
//fragment half4 displayShader(VertexOut in [[stage_in]], texture2d<float, access::sample> uTexture [[texture(0)]], texture2d<float, access::sample> uBloom [[texture(1)]], texture2d<float, access::sample> uSunrays [[texture(2)]], texture2d<float, access::sample> uDithering [[texture(3)]], constant float2 &ditherScale [[buffer(0)]], constant float2 &texelSize [[buffer(1)]]) {
//    constexpr sampler sampler2d(filter::linear);
//    half3 c = half3(uTexture.sample(sampler2d, in.uv).rgb);
//    half3 bloom = half3(uBloom.sample(sampler2d, in.uv).rgb);
//    half sunrays = uSunrays.sample(sampler2d, in.uv).r;
//    c *= sunrays;
//    bloom *= sunrays;
//    half noise = uDithering.sample(sampler2d, in.uv * ditherScale).r * 2.0 - 1.0;
//    bloom += noise / 255.0;
//    c += bloom;
//    half a = max(c.r, max(c.g, c.b));
//    return half4(c, a);
//}
//
//fragment half4 splatShader(VertexOut in [[stage_in]], texture2d<float, access::sample> uTarget [[texture(0)]], constant float &aspectRatio [[buffer(0)]], constant float3 &color [[buffer(1)]], constant float2 &point [[buffer(2)]], constant float &radius [[buffer(3)]]) {
//    constexpr sampler sampler2d(filter::linear);
//    float2 p = in.uv - point;
//    p.x *= aspectRatio;
//    float falloff = exp(-dot(p, p) / radius);
//    half3 splat = half3(color * falloff);
//    half3 base = half3(uTarget.sample(sampler2d, in.uv).xyz);
//    return half4(base + splat, 1.0);
//}
//
//
//fragment half4 advectionShader(VertexOut in [[stage_in]], texture2d<float, access::sample> uVelocity [[texture(0)]], texture2d<float, access::sample> uSource [[texture(1)]], constant float2 &texelSize [[buffer(0)]], constant float2 &dyeTexelSize [[buffer(1)]], constant float &dt [[buffer(2)]], constant float &dissipation [[buffer(3)]]) {
//    constexpr sampler sampler2d(filter::linear);
//    float2 coord = in.uv - dt * uVelocity.sample(sampler2d, in.uv).xy * texelSize;
//    half4 result = half4(uSource.sample(sampler2d, coord));
//    float decay = 1.0 + dissipation * dt;
//    return result / decay;
//}
//
//fragment half4 divergenceShader(VertexOut in [[stage_in]], texture2d<float, access::sample> uVelocity [[texture(0)]], constant float2 &offsets [[buffer(0)]]) {
//    constexpr sampler sampler2d(filter::linear);
//    float vl = uVelocity.sample(sampler2d, in.vL).x;
//    float vr = uVelocity.sample(sampler2d, in.vR).x;
//    float vt = uVelocity.sample(sampler2d, in.vT).y;
//    float vb = uVelocity.sample(sampler2d, in.vB).y;
//    float divergence = 0.5 * (vr - vl + vt - vb);
//    return half4(divergence, 0.0, 0.0, 1.0);
//}
//
//fragment half4 curlShader(VertexOut in [[stage_in]], texture2d<float, access::sample> uVelocity [[texture(0)]]) {
//    constexpr sampler sampler2d(filter::linear);
//    float vl = uVelocity.sample(sampler2d, in.vL).y;
//    float vr = uVelocity.sample(sampler2d, in.vR).y;
//    float vt = uVelocity.sample(sampler2d, in.vT).x;
//    float vb = uVelocity.sample(sampler2d, in.vB).x;
//    float vorticity = vr - vl - vt + vb;
//    return half4(0.5 * vorticity, 0.0, 0.0, 1.0);
//}
//
//fragment half4 vorticityShader(VertexOut in [[stage_in]], texture2d<float, access::sample> uVelocity [[texture(0)]], texture2d<float, access::sample> uCurl [[texture(1)]], constant float &curl [[buffer(0)]], constant float &dt [[buffer(1)]]) {
//    constexpr sampler sampler2d(filter::linear);
//    float L = uCurl.sample(sampler2d, in.vL).x;
//    float R = uCurl.sample(sampler2d, in.vR).x;
//    float T = uCurl.sample(sampler2d, in.vT).x;
//    float B = uCurl.sample(sampler2d, in.vB).x;
//    float C = uCurl.sample(sampler2d, in.uv).x;
//    float2 force = 0.5 * float2(abs(T) - abs(B), abs(R) - abs(L));
//    force /= length(force) + 0.0001;
//    force *= curl * C;
//    force.y *= -1.0;
//    float2 velocity = uVelocity.sample(sampler2d, in.uv).xy;
//    velocity += force * dt;
//    velocity = clamp(velocity, -1000.0, 1000.0);
//    return half4(half2(velocity), 0.0h, 1.0h);
//}
//
//fragment half4 pressureShader(VertexOut in [[stage_in]], texture2d<float, access::sample> uPressure [[texture(0)]], texture2d<float, access::sample> uDivergence [[texture(1)]]) {
//    constexpr sampler sampler2d(filter::linear);
//    float pl = uPressure.sample(sampler2d, in.vL).x;
//    float pr = uPressure.sample(sampler2d, in.vR).x;
//    float pt = uPressure.sample(sampler2d, in.vT).x;
//    float pb = uPressure.sample(sampler2d, in.vB).x;
//    float div = uDivergence.sample(sampler2d, in.uv).x;
//    float pressure = (pl + pr + pt + pb - div) * 0.25;
//    return half4(pressure, 0.0, 0.0, 1.0);
//}
//
//fragment half4 gradientSubtractShader(VertexOut in [[stage_in]], texture2d<float, access::sample> uPressure [[texture(0)]], texture2d<float, access::sample> uVelocity [[texture(1)]]) {
//    constexpr sampler sampler2d(filter::linear);
//    float pl = uPressure.sample(sampler2d, in.vL).x;
//    float pr = uPressure.sample(sampler2d, in.vR).x;
//    float pt = uPressure.sample(sampler2d, in.vT).x;
//    float pb = uPressure.sample(sampler2d, in.vB).x;
//    float2 velocity = uVelocity.sample(sampler2d, in.uv).xy;
//    velocity -= float2(pr - pl, pt - pb);
//    return half4(half2(velocity), 0.0h, 1.0h);
//}

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 aPosition [[attribute(0)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 vUv;
    float2 vL;
    float2 vR;
    float2 vT;
    float2 vB;
};

struct Uniforms {
    float2 texelSize;
    float aspectRatio;
    float dt;
    float dissipation;
    float intensity;
    float threshold;
    float3 curve;
    float4 color;
    float2 point;
    float radius;
    float weight;
    float curl;
    float value;
    float2 ditherScale;
};

// Base Vertex Shader
vertex VertexOut baseVertexShader(constant VertexIn* vertexArray [[buffer(0)]], unsigned int vid [[vertex_id]], constant Uniforms &uniforms [[buffer(1)]]) {
    VertexIn vertexData = vertexArray[vid];
    VertexOut out;

    out.vUv = vertexData.aPosition * 0.5 + 0.5;
    out.vL = out.vUv - float2(uniforms.texelSize.x, 0.0);
    out.vR = out.vUv + float2(uniforms.texelSize.x, 0.0);
    out.vT = out.vUv + float2(0.0, uniforms.texelSize.y);
    out.vB = out.vUv - float2(0.0, uniforms.texelSize.y);
    
    out.position = float4(vertexData.aPosition, 0.0, 1.0);
    return out;
}
// Advection Fragment Shader
fragment float4 advectionShader(VertexOut in [[stage_in]], constant Uniforms &uniforms [[buffer(1)]],
                          texture2d<float> uVelocity [[texture(0)]], texture2d<float> uSource [[texture(1)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float2 coord = in.vUv - uniforms.dt * uVelocity.sample(textureSampler, in.vUv).xy * uniforms.texelSize;
    float4 result = uSource.sample(textureSampler, coord);
    float decay = 1.0 + uniforms.dissipation * uniforms.dt;
    return result / decay;
}

// Bloom Blur Fragment Shader
fragment float4 bloomBlur(VertexOut in [[stage_in]], texture2d<float> uTexture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float4 sum = uTexture.sample(textureSampler, in.vL) +
                 uTexture.sample(textureSampler, in.vR) +
                 uTexture.sample(textureSampler, in.vT) +
                 uTexture.sample(textureSampler, in.vB);
    return sum * 0.25;
}

// Bloom Final Fragment Shader
fragment float4 bloomFinal(VertexOut in [[stage_in]], constant Uniforms &uniforms [[buffer(1)]],
                           texture2d<float> uTexture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float4 sum = uTexture.sample(textureSampler, in.vL) +
                 uTexture.sample(textureSampler, in.vR) +
                 uTexture.sample(textureSampler, in.vT) +
                 uTexture.sample(textureSampler, in.vB);
    return sum * 0.25 * uniforms.intensity;
}

// Bloom Prefilter Fragment Shader
fragment float4 bloomPrefilter(VertexOut in [[stage_in]], constant Uniforms &uniforms [[buffer(1)]],
                               texture2d<float> uTexture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float3 c = uTexture.sample(textureSampler, in.vUv).rgb;
    float br = max(c.r, max(c.g, c.b));
    float rq = clamp(br - uniforms.curve.x, 0.0, uniforms.curve.y);
    rq = uniforms.curve.z * rq * rq;
    c *= max(rq, br - uniforms.threshold) / max(br, 0.0001);
    return float4(c, 0.0);
}

// Blur Fragment Shader
fragment float4 blur(VertexOut in [[stage_in]], texture2d<float> uTexture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float4 sum = uTexture.sample(textureSampler, in.vUv) * 0.29411764;
    sum += uTexture.sample(textureSampler, in.vL) * 0.35294117;
    sum += uTexture.sample(textureSampler, in.vR) * 0.35294117;
    return sum;
}

// Blur Vertex Shader
vertex VertexOut blurVertex(VertexIn in [[stage_in]], constant Uniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    out.vUv = in.aPosition * 0.5 + 0.5;
    float offset = 1.33333333;
    out.vL = out.vUv - uniforms.texelSize * offset;
    out.vR = out.vUv + uniforms.texelSize * offset;
    out.position = float4(in.aPosition, 0.0, 1.0);
    return out;
}

// Checkerboard Fragment Shader
fragment float4 checkerboard(VertexOut in [[stage_in]], constant Uniforms &uniforms [[buffer(1)]],
                             texture2d<float> uTexture [[texture(0)]]) {
    float2 uv = floor(in.vUv * 25.0 * float2(uniforms.aspectRatio, 1.0));
    float v = fmod(uv.x + uv.y, 2.0);
    v = v * 0.1 + 0.8;
    return float4(float3(v), 1.0);
}

// Clear Fragment Shader
fragment float4 clearShader(VertexOut in [[stage_in]], constant Uniforms &uniforms [[buffer(1)]],
                      texture2d<float> uTexture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    return uniforms.value * uTexture.sample(textureSampler, in.vUv);
}

// Color Fragment Shader
fragment float4 colorShader(VertexOut in [[stage_in]], constant Uniforms &uniforms [[buffer(1)]]) {
    return uniforms.color;
}

// Copy Fragment Shader
fragment float4 copyShader(VertexOut in [[stage_in]], texture2d<float> uTexture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    return uTexture.sample(textureSampler, in.vUv);
}

// Curl Fragment Shader
fragment float4 curlShader(VertexOut in [[stage_in]], texture2d<float> uVelocity [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float L = uVelocity.sample(textureSampler, in.vL).y;
    float R = uVelocity.sample(textureSampler, in.vR).y;
    float T = uVelocity.sample(textureSampler, in.vT).x;
    float B = uVelocity.sample(textureSampler, in.vB).x;
    float vorticity = R - L - T + B;
    return float4(0.5 * vorticity, 0.0, 0.0, 1.0);
}

// Display Fragment Shader
fragment float4 displayShader(VertexOut in [[stage_in]], constant Uniforms &uniforms [[buffer(1)]],
                        texture2d<float> uTexture [[texture(0)]], texture2d<float> uBloom [[texture(1)]],
                        texture2d<float> uSunrays [[texture(2)]], texture2d<float> uDithering [[texture(3)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float3 c = uTexture.sample(textureSampler, in.vUv).rgb;
    
#ifdef SHADING
    float3 lc = uTexture.sample(textureSampler, in.vL).rgb;
    float3 rc = uTexture.sample(textureSampler, in.vR).rgb;
    float3 tc = uTexture.sample(textureSampler, in.vT).rgb;
    float3 bc = uTexture.sample(textureSampler, in.vB).rgb;
    
    float dx = length(rc) - length(lc);
    float dy = length(tc) - length(bc);
    
    float3 n = normalize(float3(dx, dy, length(uniforms.texelSize)));
    float3 l = float3(0.0, 0.0, 1.0);
    
    float diffuse = clamp(dot(n, l) + 0.7, 0.7, 1.0);
    c *= diffuse;
#endif
    
#ifdef BLOOM
    float3 bloom = uBloom.sample(textureSampler, in.vUv).rgb;
#endif
    
#ifdef SUNRAYS
    float sunrays = uSunrays.sample(textureSampler, in.vUv).r;
    c *= sunrays;
#ifdef BLOOM
    bloom *= sunrays;
#endif
#endif
    
#ifdef BLOOM
    float noise = uDithering.sample(textureSampler, in.vUv * uniforms.ditherScale).r;
    noise = noise * 2.0 - 1.0;
    bloom += noise / 255.0;
    bloom = max(1.055 * pow(bloom, float3(0.416666667)) - 0.055, float3(0));
    c += bloom;
#endif
    
    float a = max(c.r, max(c.g, c.b));
    return float4(c, a);
}

// Divergence Fragment Shader
fragment float4 divergenceShader(VertexOut in [[stage_in]], texture2d<float> uVelocity [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float L = uVelocity.sample(textureSampler, in.vL).x;
    float R = uVelocity.sample(textureSampler, in.vR).x;
    float T = uVelocity.sample(textureSampler, in.vT).y;
    float B = uVelocity.sample(textureSampler, in.vB).y;
    
    float2 C = uVelocity.sample(textureSampler, in.vUv).xy;
    if (in.vL.x < 0.0) { L = -C.x; }
    if (in.vR.x > 1.0) { R = -C.x; }
    if (in.vT.y > 1.0) { T = -C.y; }
    if (in.vB.y < 0.0) { B = -C.y; }
    
    float div = 0.5 * (R - L + T - B);
    return float4(div, 0.0, 0.0, 1.0);
}

// Gradient Subtract Fragment Shader
fragment float4 gradientSubtractShader(VertexOut in [[stage_in]], texture2d<float> uPressure [[texture(0)]],
                                 texture2d<float> uVelocity [[texture(1)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float L = uPressure.sample(textureSampler, in.vL).x;
    float R = uPressure.sample(textureSampler, in.vR).x;
    float T = uPressure.sample(textureSampler, in.vT).x;
    float B = uPressure.sample(textureSampler, in.vB).x;
    float2 velocity = uVelocity.sample(textureSampler, in.vUv).xy;
    velocity.xy -= float2(R - L, T - B);
    return float4(velocity, 0.0, 1.0);
}

// Pressure Fragment Shader
fragment float4 pressureShader(VertexOut in [[stage_in]], texture2d<float> uPressure [[texture(0)]],
                         texture2d<float> uDivergence [[texture(1)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float L = uPressure.sample(textureSampler, in.vL).x;
    float R = uPressure.sample(textureSampler, in.vR).x;
    float T = uPressure.sample(textureSampler, in.vT).x;
    float B = uPressure.sample(textureSampler, in.vB).x;
    float C = uPressure.sample(textureSampler, in.vUv).x;
    float divergence = uDivergence.sample(textureSampler, in.vUv).x;
    float pressure = (L + R + B + T - divergence) * 0.25;
    return float4(pressure, 0.0, 0.0, 1.0);
}

// Splat Fragment Shader
fragment float4 splatShader(VertexOut in [[stage_in]], constant Uniforms &uniforms [[buffer(1)]],
                      texture2d<float> uTarget [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);

    float2 p = in.vUv - uniforms.point;
    p.x *= uniforms.aspectRatio;
    float3 splat = exp(-dot(p, p) / uniforms.radius) * uniforms.color.rgb;
    float3 base = uTarget.sample(textureSampler, in.vUv).xyz;
    return float4(base + splat, 1.0);
}

// Sunrays Mask Fragment Shader
fragment float4 sunraysMask(VertexOut in [[stage_in]], texture2d<float> uTexture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float4 c = uTexture.sample(textureSampler, in.vUv);
    float br = max(c.r, max(c.g, c.b));
    c.a = 1.0 - min(max(br * 20.0, 0.0), 0.8);
    return c;
}

// Sunrays Fragment Shader
fragment float4 sunrays(VertexOut in [[stage_in]], constant Uniforms &uniforms [[buffer(1)]],
                        texture2d<float> uTexture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float Density = 0.3;
    float Decay = 0.95;
    float Exposure = 0.7;
    
    float2 coord = in.vUv;
    float2 dir = in.vUv - 0.5;
    
    dir *= 1.0 / 16.0 * Density;
    float illuminationDecay = 1.0;
    
    float color = uTexture.sample(textureSampler, in.vUv).a;
    
    for (int i = 0; i < 16; i++) {
        coord -= dir;
        float col = uTexture.sample(textureSampler, coord).a;
        color += col * illuminationDecay * uniforms.weight;
        illuminationDecay *= Decay;
    }
    
    return float4(color * Exposure, 0.0, 0.0, 1.0);
}

// Vorticity Fragment Shader
fragment float4 vorticityShader(VertexOut in [[stage_in]], constant Uniforms &uniforms [[buffer(1)]],
                          texture2d<float> uVelocity [[texture(0)]], texture2d<float> uCurl [[texture(1)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float L = uCurl.sample(textureSampler, in.vL).x;
    float R = uCurl.sample(textureSampler, in.vR).x;
    float T = uCurl.sample(textureSampler, in.vT).x;
    float B = uCurl.sample(textureSampler, in.vB).x;
    float C = uCurl.sample(textureSampler, in.vUv).x;
    
    float2 force = 0.5 * float2(abs(T) - abs(B), abs(R) - abs(L));
    force /= length(force) + 0.0001;
    force *= uniforms.curl * C;
    force.y *= -1.0;
    
    float2 velocity = uVelocity.sample(textureSampler, in.vUv).xy;
    velocity += force * uniforms.dt;
    velocity = clamp(velocity, -1000.0, 1000.0);
    return float4(velocity, 0.0, 1.0);
}
