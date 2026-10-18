import Metal
import SceneKit

/// Tilt-shift blur keeps a central sharp band and gradually blurs above/below for a miniature-photograph effect.
/// Compile shaders at runtime without the Metal toolchain; use horizontal/vertical Gaussian passes.
enum TiltShift {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct TiltVertexIn { float4 position [[attribute(0)]]; };
    struct TiltVertexOut { float4 position [[position]]; float2 uv; };

    vertex TiltVertexOut tilt_vertex(TiltVertexIn in [[stage_in]]) {
        TiltVertexOut out;
        out.position = in.position;
        out.uv = float2((in.position.x + 1.0) * 0.5, 1.0 - (in.position.y + 1.0) * 0.5);
        return out;
    }

    static half4 tilt_blur(TiltVertexOut in, texture2d<half, access::sample> tex, float2 axis) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        const float focus = 0.58;
        const float band = 0.26;
        float d = max(0.0, abs(in.uv.y - focus) - band);
        float radius = min(d * 18.0, 3.0);
        if (radius < 0.25) { return tex.sample(s, in.uv); }
        float2 texel = axis / float2(tex.get_width(), tex.get_height());
        half4 acc = half4(0.0);
        float wsum = 0.0;
        float sigma = max(radius * 0.5, 0.5);
        for (int i = -6; i <= 6; i++) {
            float x = float(i) * radius / 6.0;
            float w = exp(-(x * x) / (2.0 * sigma * sigma));
            acc += tex.sample(s, in.uv + texel * x) * half(w);
            wsum += w;
        }
        return acc / half(wsum);
    }

    fragment half4 tilt_fragment_h(TiltVertexOut in [[stage_in]], texture2d<half, access::sample> colorSampler [[texture(0)]]) {
        return tilt_blur(in, colorSampler, float2(1.0, 0.0));
    }

    fragment half4 tilt_fragment_v(TiltVertexOut in [[stage_in]], texture2d<half, access::sample> blurSampler [[texture(0)]]) {
        return tilt_blur(in, blurSampler, float2(0.0, 1.0));
    }
    """

    static func technique() -> SCNTechnique? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = try? device.makeLibrary(source: source, options: nil) else { return nil }
        let dict: [String: Any] = [
            "passes": [
                "tiltH": ["draw": "DRAW_QUAD", "metalVertexShader": "tilt_vertex", "metalFragmentShader": "tilt_fragment_h",
                          "inputs": ["colorSampler": "COLOR"], "outputs": ["color": "tiltTmp"]],
                "tiltV": ["draw": "DRAW_QUAD", "metalVertexShader": "tilt_vertex", "metalFragmentShader": "tilt_fragment_v",
                          "inputs": ["blurSampler": "tiltTmp"], "outputs": ["color": "COLOR"]],
            ],
            "sequence": ["tiltH", "tiltV"],
            "targets": ["tiltTmp": ["type": "color"]],
        ]
        let t = SCNTechnique(dictionary: dict)
        t?.library = library
        return t
    }
}
