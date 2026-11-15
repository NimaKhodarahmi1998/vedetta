/// Compiled at launch, so the project needs no offline Metal toolchain.
nonisolated enum SplatShader {
    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    // Must match SplatVertex: 9 floats, 36 bytes.
    struct SplatIn {
        packed_float3 pos;
        packed_float3 color;
        float conf;      // map splats: certainty 0...1; overlays: alpha
        float size;      // world size in metres
        float mode;      // 0 = map splat, 1 = solid overlay, 2 = ring (hidden, remembered)
    };

    // Must match SplatUniforms: 116 bytes, padded to 128.
    struct Uniforms {
        float4x4 viewProj;
        float scale;
        float frozen;
        float waveR;
        float waveA;
        packed_float3 walker;
        packed_float3 groundColor;
        packed_float3 inkColor;
    };

    struct VOut {
        float4 position [[position]];
        float pointSize [[point_size]];
        float3 color;
        float alpha;
        float sharpness;
        float mode;
    };

    vertex VOut splatVertex(const device SplatIn* v [[buffer(0)]],
                            constant Uniforms& u [[buffer(1)]],
                            uint vid [[vertex_id]]) {
        SplatIn s = v[vid];
        float3 p = float3(s.pos);
        float3 ground = float3(u.groundColor);
        float3 ink = float3(u.inkColor);
        VOut o;
        float4 clip = u.viewProj * float4(p, 1.0);
        o.position = clip;
        float depth = max(clip.w, 0.1);
        bool isMap = s.mode < 0.5;
        // Uncertain map splats blur larger and softer until seen enough
        float sz = isMap ? s.size * (1.0 + (1.0 - s.conf) * 1.6) : s.size;
        o.pointSize = clamp(sz * u.scale / depth, 1.0, 48.0);
        float d = distance(p.xz, float3(u.walker).xz);
        float wave = isMap ? u.waveA * exp(-pow((d - u.waveR) * 0.9, 2.0)) : 0.0;
        // One grey for the whole map, with a hint of the real brightness as texture
        float brightness = dot(float3(s.color), float3(0.3, 0.55, 0.15));
        float3 mapColor = mix(mix(ground, ink, 0.26 + 0.14 * brightness), ink, wave * 0.35);
        float3 color = isMap ? mapColor : float3(s.color);
        float alpha = isMap ? (pow(s.conf, 0.75) * 0.9 * (1.0 - 0.45 * u.frozen) + wave * 0.2) : s.conf;
        // Distance fades into the ground colour, like fog
        float fog = smoothstep(8.0, 26.0, d);
        o.color = mix(color, ground, fog * 0.85);
        o.alpha = alpha * (1.0 - 0.6 * fog);
        o.sharpness = isMap ? mix(3.0, 6.0, s.conf) : 4.5;
        o.mode = s.mode;
        return o;
    }

    fragment float4 splatFragment(VOut in [[stage_in]], float2 pc [[point_coord]]) {
        float2 q = pc * 2.0 - 1.0;
        float r2 = dot(q, q);
        if (r2 > 1.0) discard_fragment();
        float g = exp(-r2 * in.sharpness);
        float ring = smoothstep(0.3, 0.55, r2) * (1.0 - smoothstep(0.75, 1.0, r2));
        float a = (in.mode > 1.5 ? ring * 1.3 : g) * in.alpha;
        if (a < 0.01) discard_fragment();
        return float4(in.color * a, a);   // premultiplied alpha
    }
    """#
}
