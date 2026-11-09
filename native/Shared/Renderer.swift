// Metal port of @shadergradient/react 2.4.20 (MIT, © ruucm): same meshes, noise, color formulas,
// camera and halftone "grain" pass. Shaders compile at runtime so building needs no Metal toolchain.
import AppKit
import MetalKit
import simd

private let shaderSource = #"""
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
  float4x4 mvp;
  float4x4 model;
  float4 c1, c2, c3;
  float4 a;      // time, speed, density, strength
  float4 b;      // frequency, amplitude, brightness, reflection
  float4 c;      // type (0 plane, 1 waterPlane, 2 sphere), env light, env preset, color pattern scale
  float4 camPos;
  float4 d;      // shape pattern, shape sharpness, color pattern (0 = position gradient), color sharpness
};

// GLSL mix() extrapolates outside [0,1] and the gradient formulas rely on it; Metal's mix() doesn't promise to.
template <typename T> T lerp(T x, T y, float a) { return x + (y - x) * a; }
float3 gmod(float3 x, float3 y) { return x - y * floor(x / y); }
float3 mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
float4 mod289(float4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
float4 permute(float4 x) { return mod289(((x * 34.0) + 1.0) * x); }
float4 taylorInvSqrt(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }
float3 fade(float3 t) { return t * t * t * (t * (t * 6.0 - 15.0) + 10.0); }

float perlin(float3 Pi0, float3 Pi1, float3 Pf0) {
  Pi0 = mod289(Pi0); Pi1 = mod289(Pi1);
  float3 Pf1 = Pf0 - float3(1.0);
  float4 ix = float4(Pi0.x, Pi1.x, Pi0.x, Pi1.x);
  float4 iy = float4(Pi0.yy, Pi1.yy);
  float4 iz0 = Pi0.zzzz, iz1 = Pi1.zzzz;
  float4 ixy = permute(permute(ix) + iy);
  float4 ixy0 = permute(ixy + iz0), ixy1 = permute(ixy + iz1);
  float4 gx0 = ixy0 * (1.0 / 7.0);
  float4 gy0 = fract(floor(gx0) * (1.0 / 7.0)) - 0.5;
  gx0 = fract(gx0);
  float4 gz0 = float4(0.5) - abs(gx0) - abs(gy0);
  float4 sz0 = step(gz0, float4(0.0));
  gx0 -= sz0 * (step(0.0, gx0) - 0.5);
  gy0 -= sz0 * (step(0.0, gy0) - 0.5);
  float4 gx1 = ixy1 * (1.0 / 7.0);
  float4 gy1 = fract(floor(gx1) * (1.0 / 7.0)) - 0.5;
  gx1 = fract(gx1);
  float4 gz1 = float4(0.5) - abs(gx1) - abs(gy1);
  float4 sz1 = step(gz1, float4(0.0));
  gx1 -= sz1 * (step(0.0, gx1) - 0.5);
  gy1 -= sz1 * (step(0.0, gy1) - 0.5);
  float3 g000 = float3(gx0.x, gy0.x, gz0.x), g100 = float3(gx0.y, gy0.y, gz0.y);
  float3 g010 = float3(gx0.z, gy0.z, gz0.z), g110 = float3(gx0.w, gy0.w, gz0.w);
  float3 g001 = float3(gx1.x, gy1.x, gz1.x), g101 = float3(gx1.y, gy1.y, gz1.y);
  float3 g011 = float3(gx1.z, gy1.z, gz1.z), g111 = float3(gx1.w, gy1.w, gz1.w);
  float4 norm0 = taylorInvSqrt(float4(dot(g000, g000), dot(g010, g010), dot(g100, g100), dot(g110, g110)));
  g000 *= norm0.x; g010 *= norm0.y; g100 *= norm0.z; g110 *= norm0.w;
  float4 norm1 = taylorInvSqrt(float4(dot(g001, g001), dot(g011, g011), dot(g101, g101), dot(g111, g111)));
  g001 *= norm1.x; g011 *= norm1.y; g101 *= norm1.z; g111 *= norm1.w;
  float n000 = dot(g000, Pf0);
  float n100 = dot(g100, float3(Pf1.x, Pf0.yz));
  float n010 = dot(g010, float3(Pf0.x, Pf1.y, Pf0.z));
  float n110 = dot(g110, float3(Pf1.xy, Pf0.z));
  float n001 = dot(g001, float3(Pf0.xy, Pf1.z));
  float n101 = dot(g101, float3(Pf1.x, Pf0.y, Pf1.z));
  float n011 = dot(g011, float3(Pf0.x, Pf1.yz));
  float n111 = dot(g111, Pf1);
  float3 f = fade(Pf0);
  float4 n_z = lerp(float4(n000, n100, n010, n110), float4(n001, n101, n011, n111), f.z);
  float2 n_yz = lerp(n_z.xy, n_z.zw, f.y);
  return 2.2 * lerp(n_yz.x, n_yz.y, f.x);
}
float cnoise(float3 P) { return perlin(floor(P), floor(P) + 1.0, fract(P)); }
float pnoise(float3 P, float3 rep) {
  float3 Pi0 = gmod(floor(P), rep);
  return perlin(Pi0, gmod(Pi0 + 1.0, rep), fract(P));
}

// ---- Patterns: 0 noise (Perlin), 1 warp, 2 cells (smooth Voronoi), 3 ridged, 4 waves. All return about [-1, 1]. ----
float3 hash3(float3 p) {
  p = float3(dot(p, float3(127.1, 311.7, 74.7)), dot(p, float3(269.5, 183.3, 246.1)), dot(p, float3(113.5, 271.9, 124.6)));
  return fract(sin(p) * 43758.5453);
}
// Noise that bends its own input: liquid marble.
float warpNoise(float3 p) {
  float3 q = float3(cnoise(p), cnoise(p + float3(5.2, 1.3, 2.8)), cnoise(p + float3(1.7, 9.2, 4.1)));
  return cnoise(p + 1.5 * q);
}
// Smooth minimum distance to jittered cell points; higher k = crisper cell borders.
float cells(float3 p, float k) {
  float3 i = floor(p), f = fract(p);
  float sum = 0.0;
  for (int z = -1; z <= 1; z++) for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
    float3 g = float3(x, y, z);
    sum += exp(-k * length(g + hash3(i + g) - f));
  }
  return 1.0 - 2.0 * saturate(-log(sum) / k + 0.25); // cell centers high, borders low
}
float ridged(float3 p) {
  float s = 0.0, a = 0.5;
  for (int i = 0; i < 3; i++) { float n = 1.0 - abs(cnoise(p)); s += n * n * a; p *= 2.0; a *= 0.5; }
  return s / 0.875 * 2.0 - 1.0;
}
float waves(float3 p) {
  return (sin(p.x * 2.0 + p.y * 0.7) + sin(p.y * 2.3 - p.z * 1.1 + 1.3) + sin(length(p.xz) * 3.0)) / 3.0;
}
// sharpness 0.5 leaves the pattern as is; lower softens, higher crisps.
float pattern(int kind, float3 p, float sharp) {
  float v = kind == 1 ? warpNoise(p) : kind == 2 ? cells(p, lerp(3.0, 24.0, sharp)) : kind == 3 ? ridged(p) : kind == 4 ? waves(p) : cnoise(p);
  if (kind == 2 || abs(sharp - 0.5) < 1e-3) return v; // cells take sharpness as border crispness
  return sign(v) * pow(abs(v), exp2((0.5 - sharp) * 3.0));
}

struct Vertex { packed_float3 pos; packed_float3 normal; packed_float2 uv; };
struct VOut { float4 position [[position]]; float3 vPos; float3 world; float3 normal; float3 rest; };

float3 displace(float3 position, float3 normal, float2 uv, constant Uniforms& u) {
  float t = u.a.x * u.a.y;
  int kind = int(u.d.x);
  if (u.c.x < 1.5) {
    float distortion = 0.75 * pattern(kind, 0.43 * position * u.a.z + t, u.d.y);
    return position + normal * distortion * u.a.w;
  }
  // pnoise keeps ShaderGradient's look for the default; other patterns are seamless on the sphere anyway.
  float distortion = (kind == 0 && abs(u.d.y - 0.5) < 1e-3 ? pnoise((normal + t) * u.a.z, float3(10.0))
                                                                : pattern(kind, (normal + t) * u.a.z, u.d.y)) * u.a.w;
  float angle = sin(uv.y * u.b.x + t) * u.b.y;
  float s = sin(angle), c = cos(angle);
  return float3x3(float3(c, 0, -s), float3(0, 1, 0), float3(s, 0, c)) * (position + normal * distortion);
}

// A unit-sphere point with the normal and uv.y (latitude) the sphere mesh gives it.
float3 spherePoint(float3 q, constant Uniforms& u) {
  q = normalize(q);
  return displace(q, q, float2(0, 1.0 - acos(clamp(q.y, -1.0, 1.0)) / 3.14159265), u);
}

vertex VOut sceneVertex(uint vid [[vertex_id]], const device Vertex* verts [[buffer(0)]], constant Uniforms& u [[buffer(1)]]) {
  float3 position = verts[vid].pos, normal = verts[vid].normal;
  float3 pos = displace(position, normal, verts[vid].uv, u);
  VOut o;
  o.position = u.mvp * float4(pos, 1.0);
  o.vPos = pos;
  o.world = (u.model * float4(pos, 1.0)).xyz;
  o.normal = float3(0, 0, 1);
  o.rest = position;
  if (u.c.y > 0.5 && u.c.x > 0.5) { // plane: per pixel in sceneFragment (its mesh is one column wide)
    // Smooth normal of the displaced surface from two nearby displaced points; per-pixel dfdx/dfdy normals were flat per
    // triangle, so environment reflections showed the mesh's facets.
    float3 a, b;
    if (u.c.x < 1.5) {
      a = displace(position + float3(0.01, 0, 0), normal, verts[vid].uv, u);
      b = displace(position + float3(0, 0.01, 0), normal, verts[vid].uv, u);
    } else {
      float3 tx = cross(float3(0, 1, 0), position);
      tx = length(tx) < 1e-3 ? float3(1, 0, 0) : normalize(tx); // poles
      a = spherePoint(position + tx * 0.002, u);
      b = spherePoint(position + cross(position, tx) * 0.002, u);
    }
    o.normal = (u.model * float4(cross(a - pos, b - pos), 0.0)).xyz;
  }
  return o;
}

// shortcut: "env" lighting uses a procedural sky per preset instead of the city/dawn/lobby HDRs; load the HDRs as
// cube maps if env presets need to match the site exactly.
float3 envColor(float3 d, int preset) {
  float h = d.y * 0.5 + 0.5;
  if (preset == 1) return lerp(float3(0.55, 0.35, 0.35), float3(1.25, 0.95, 0.8), h);
  if (preset == 2) return lerp(float3(0.45, 0.38, 0.3), float3(1.1, 1.0, 0.85), h);
  return lerp(float3(0.35, 0.34, 0.33), float3(1.15, 1.12, 1.1), h);
}

// Alpha carries the depth for bokeh: distance from the camera minus its distance to the target (0 = target plane).
fragment float4 sceneFragment(VOut in [[stage_in]], constant Uniforms& u [[buffer(1)]]) {
  float z = length(u.camPos.xyz - in.world) - u.camPos.w;
  float3 c1 = u.c1.rgb, c2 = u.c2.rgb, c3 = u.c3.rgb;
  float3 d = u.c.x < 1.5
    ? lerp(lerp(c1, c2, smoothstep(-3.0, 3.0, in.vPos.x)), c3, in.vPos.z)
    : lerp(c3, lerp(c2, c1, smoothstep(-1.0, 1.0, in.vPos.y)), length(in.vPos));
  if (u.d.z > 0.5) {
    // Color pattern: a three-stop ramp c1 -> c2 -> c3 over the pattern, drifting slower than the shape.
    float3 pp = (u.c.x < 1.5 ? in.vPos * 0.6 : in.vPos * 1.5) * u.c.w + u.a.x * u.a.y * 0.5;
    float f = saturate(pattern(int(u.d.z) - 1, pp, u.d.w) * 0.8 + 0.5); // noise rarely nears ±1: stretch to use all three colors
    d = lerp(lerp(c1, c2, smoothstep(0.0, 0.5, f)), c3, smoothstep(0.5, 1.0, f));
  }
  // MeshPhysicalMaterial (metalness 0.2) under an ambient light of brightness*PI: Lambert gives 0.8 * brightness.
  if (u.c.y < 0.5) return float4(d * 0.8 * u.b.z, z);
  float3 n = in.normal;
  if (u.c.x < 0.5) {
    float3 p0 = displace(in.rest, float3(0, 0, 1), 0, u);
    n = (u.model * float4(cross(displace(in.rest + float3(0.01, 0, 0), float3(0, 0, 1), 0, u) - p0,
                                displace(in.rest + float3(0, 0.01, 0), float3(0, 0, 1), 0, u) - p0), 0.0)).xyz;
  }
  n = normalize(n);
  float3 v = normalize(u.camPos.xyz - in.world);
  if (dot(n, v) < 0.0) n = -n;
  int preset = int(u.c.z);
  float rough = 1.0 - u.b.w;
  float3 f0 = lerp(float3(0.04), d, 0.2);
  float fres = pow(1.0 - saturate(dot(n, v)), 5.0);
  float3 spec = (f0 + (max(float3(1.0 - rough), f0) - f0) * fres) * lerp(envColor(reflect(-v, n), preset), envColor(n, preset), rough);
  return float4(d * 0.8 * envColor(n, preset) + spec, z);
}

// ---- three.js HalftonePass as configured by ShaderGradient's grain: dots, radius 2, scatter 1, linear blending ----
struct QOut { float4 position [[position]]; float2 uv; float2 qpos; };

vertex QOut quadVertex(uint vid [[vertex_id]]) {
  float2 p = float2(vid == 2 ? 3.0 : -1.0, vid == 0 ? 3.0 : -1.0);
  QOut o; o.position = float4(p, 0, 1); o.uv = p * 0.5 + 0.5; o.qpos = p; return o;
}

constant float PI2 = 6.28318531;

struct Cell { float2 normal, p1, p2, p3, p4; };

float rand(float2 seed) { return fract(sin(dot(seed, float2(12.9898, 78.233))) * 43758.5453); }

float4 sampleAt(texture2d<float> tex, float2 point, float2 size) {
  constexpr sampler s(filter::linear, address::clamp_to_edge);
  float2 uv = point / size;
  return tex.sample(s, float2(uv.x, 1.0 - uv.y)); // GL uv is bottom-up
}

float dotRadius(float channel, float2 coord, float2 p, float radius) {
  return pow(abs(channel), 1.125) * radius - length(coord - p);
}

Cell referenceCell(float2 p, float angle, float radius) {
  Cell c;
  float step = radius;
  float2 n = float2(cos(angle), sin(angle));
  float threshold = step * 0.5;
  float dot_normal = n.x * p.x + n.y * p.y;
  float dot_line = -n.y * p.x + n.x * p.y;
  float2 offset = n * dot_normal;
  float offset_normal = fmod(length(offset), step);
  float normal_dir = dot_normal < 0.0 ? 1.0 : -1.0;
  float normal_scale = (offset_normal < threshold ? -offset_normal : step - offset_normal) * normal_dir;
  float offset_line = fmod(length(p - offset), step);
  float line_dir = dot_line < 0.0 ? 1.0 : -1.0;
  float line_scale = (offset_line < threshold ? -offset_line : step - offset_line) * line_dir;
  c.normal = n;
  c.p1 = float2(p.x - n.x * normal_scale + n.y * line_scale, p.y - n.y * normal_scale - n.x * line_scale);
  float off_mag = threshold * 0.5;
  float off_angle = rand(floor(c.p1)) * PI2;
  c.p1 += float2(cos(off_angle), sin(off_angle)) * off_mag;
  float normal_step = normal_dir * (offset_normal < threshold ? step : -step);
  float line_step = line_dir * (offset_line < threshold ? step : -step);
  c.p2 = c.p1 - n * normal_step;
  c.p3 = float2(c.p1.x + n.y * line_step, c.p1.y - n.x * line_step);
  c.p4 = float2(c.p1.x - n.x * normal_step + n.y * line_step, c.p1.y - n.y * normal_step - n.x * line_step);
  return c;
}

float dotColour(texture2d<float> tex, float2 size, Cell c, float2 p, int ch, float radius) {
  float aa = radius * 0.5;
  float d1 = dotRadius(sampleAt(tex, c.p1, size)[ch], c.p1, p, radius);
  float d2 = dotRadius(sampleAt(tex, c.p2, size)[ch], c.p2, p, radius);
  float d3 = dotRadius(sampleAt(tex, c.p3, size)[ch], c.p3, p, radius);
  float d4 = dotRadius(sampleAt(tex, c.p4, size)[ch], c.p4, p, radius);
  float res = (d1 > 0.0 ? clamp(d1 / aa, 0.0, 1.0) : 0.0) + (d2 > 0.0 ? clamp(d2 / aa, 0.0, 1.0) : 0.0)
            + (d3 > 0.0 ? clamp(d3 / aa, 0.0, 1.0) : 0.0) + (d4 > 0.0 ? clamp(d4 / aa, 0.0, 1.0) : 0.0);
  return clamp(res, 0.0, 1.0);
}

// Bokeh: a gather blur of the scene whose radius grows with the distance from the focus plane. A tap only counts if
// its own blur reaches this pixel, and taps behind this pixel can't spread wider than it does, so a sharp object
// doesn't take on the blurred background. p.x = focus (depth units), p.y = largest radius (scene pixels).
float cocOf(float z, float4 p) { return min(abs(z - p.x) * 0.5, 1.0) * p.y; }

fragment float4 bokehFragment(QOut in [[stage_in]], texture2d<float> tex [[texture(0)]], constant float4& p [[buffer(0)]]) {
  constexpr sampler s(filter::linear, address::clamp_to_edge);
  float2 size = float2(tex.get_width(), tex.get_height()), uv = float2(in.uv.x, 1.0 - in.uv.y);
  float4 c = tex.sample(s, uv);
  float coc = cocOf(c.a, p);
  float3 sum = c.rgb;
  float wsum = 1.0;
  for (int i = 0; i < 16; i++) {
    float r = sqrt((float(i) + 0.5) / 16.0) * p.y, a = float(i) * 2.39996; // golden-angle disk
    float4 t = tex.sample(s, uv + r * float2(cos(a), sin(a)) / size);
    float tc = cocOf(t.a, p);
    if (t.a > c.a) tc = min(tc, coc);
    float w = saturate(tc - r + 1.0);
    sum += t.rgb * w; wsum += w;
  }
  return float4(sum / wsum, c.a);
}

// params[0]: width, height (points), grain amount (0 = off, 1 = dots only, as ShaderGradient), fade (0 = black)
// params[1]: grain dot radius (ShaderGradient uses 2)
fragment float4 finalFragment(QOut in [[stage_in]], texture2d<float> tex [[texture(0)]], constant float4* params [[buffer(0)]]) {
  float2 size = params[0].xy;
  float amount = params[0].z, radius = params[1].x;
  float4 colour = sampleAt(tex, in.uv * size, size);
  if (amount <= 0.0) return float4(colour.rgb * params[0].w, 1.0);
  float2 p = in.uv * size - in.qpos * 3.0;
  float rgb[3];
  float angles[3] = { M_PI_F / 12.0, M_PI_F / 12.0 * 2.0, M_PI_F / 12.0 * 3.0 };
  for (int ch = 0; ch < 3; ch++) {
    float v = dotColour(tex, size, referenceCell(p, angles[ch], radius), p, ch, radius);
    rgb[ch] = colour[ch] == 0.0 ? 0.0 : v; // linear blending at 1.0 keeps only the dot
  }
  return float4(lerp(colour.rgb, float3(rgb[0], rgb[1], rgb[2]), amount) * params[0].w, 1.0);
}
"""#

struct Uniforms {
    var mvp = matrix_identity_float4x4
    var model = matrix_identity_float4x4
    var c1 = SIMD4<Float>(), c2 = SIMD4<Float>(), c3 = SIMD4<Float>()
    var a = SIMD4<Float>(), b = SIMD4<Float>(), c = SIMD4<Float>()
    var camPos = SIMD4<Float>()
    var d = SIMD4<Float>()
}

/// Numeric form of the props, so changes can ease in like the web version's camera transitions.
struct GradientParams {
    var type = 0, env = false, envPreset = 0, grain = true, animate = true
    var uTime: Float = 0, speed: Float = 0.4, density: Float = 1.3, strength: Float = 4, frequency: Float = 5.5, amplitude: Float = 1
    var c1 = SIMD3<Float>(), c2 = SIMD3<Float>(), c3 = SIMD3<Float>()
    var brightness: Float = 1.2, reflection: Float = 0.1
    var subdivision = 0
    var shapePattern = 0, colorPattern = 0 // colorPattern 0 = position gradient, else pattern + 1
    var shapeSharpness: Float = 0.5, colorSharpness: Float = 0.5, colorScale: Float = 1
    var grainAmount: Float = 1, grainSize: Float = 2
    var bokeh = false, focus: Float = 0, blur: Float = 0.5
    var music = false, musicColor = false, musicIntensity: Float = 1
    var azimuth: Float = 180, polar: Float = 90, distance: Float = 3.6, zoom: Float = 1, fov: Float = 45
    var position = SIMD3<Float>(), rotation = SIMD3<Float>()
    var pixelDensity: Float = 1
    var rangeOn = false, rangeStart: Float = 0, rangeEnd: Float = 40

    init(_ p: Props) {
        type = ["plane": 0, "waterPlane": 1, "sphere": 2][p.str("type", "plane")] ?? 0
        env = p.str("lightType", "3d") == "env"
        envPreset = ["city": 0, "dawn": 1, "lobby": 2][p.str("envPreset", "city")] ?? 0
        grain = p.str("grain", "on") == "on"
        animate = p.str("animate", "on") == "on"
        func f(_ k: String, _ d: Double) -> Float { Float(p.num(k, d)) }
        uTime = f("uTime", 0); speed = f("uSpeed", 0.4); density = f("uDensity", 1.3); strength = f("uStrength", 4)
        frequency = f("uFrequency", 5.5); amplitude = f("uAmplitude", 1)
        c1 = hexColor(p.str("color1", "#ff5005")); c2 = hexColor(p.str("color2", "#dbba95")); c3 = hexColor(p.str("color3", "#d0bce1"))
        brightness = f("brightness", 1.2); reflection = f("reflection", 0.1)
        subdivision = Int(max(0, min(2, p.num("subdivision", 0)).rounded()))
        shapePattern = patternKinds[p.str("shapePattern", "noise")] ?? 0
        colorPattern = patternKinds[p.str("colorPattern", "position")].map { $0 + 1 } ?? 0
        shapeSharpness = max(0, min(1, f("shapeSharpness", 0.5))); colorSharpness = max(0, min(1, f("colorSharpness", 0.5)))
        colorScale = max(0.1, min(5, f("colorScale", 1)))
        // Hueflow extras; the defaults are ShaderGradient's fixed halftone.
        grainAmount = max(0, min(1, f("grainAmount", 1))); grainSize = max(1, min(8, f("grainSize", 2)))
        music = p.str("music", "off") == "on"; musicColor = p.str("musicTarget", "strength") == "color"; musicIntensity = max(0, min(3, f("musicIntensity", 1)))
        bokeh = p.str("bokeh", "off") == "on"; focus = max(-10, min(10, f("focus", 0))); blur = max(0, min(1, f("blur", 0.5)))
        azimuth = f("cAzimuthAngle", 180); polar = f("cPolarAngle", 90); distance = f("cDistance", 3.6); zoom = f("cameraZoom", 1)
        fov = f("fov", 45)
        position = [f("positionX", 0), f("positionY", 0), f("positionZ", 0)]
        rotation = [f("rotationX", 0), f("rotationY", 0), f("rotationZ", 0)]
        pixelDensity = max(0.25, min(2, f("pixelDensity", 1)))
        rangeOn = p.str("range", "disabled") == "enabled"; rangeStart = f("rangeStart", 0); rangeEnd = f("rangeEnd", 40)
    }

    /// Eases continuous values toward `t`; discrete ones switch immediately.
    mutating func approach(_ t: GradientParams, _ k: Float) {
        var n = t
        func l(_ a: Float, _ b: Float) -> Float { a + (b - a) * k }
        func l3(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> { a + (b - a) * k }
        if type == t.type {
            n.speed = l(speed, t.speed); n.density = l(density, t.density); n.strength = l(strength, t.strength)
            n.frequency = l(frequency, t.frequency); n.amplitude = l(amplitude, t.amplitude)
            n.c1 = l3(c1, t.c1); n.c2 = l3(c2, t.c2); n.c3 = l3(c3, t.c3)
            n.brightness = l(brightness, t.brightness); n.reflection = l(reflection, t.reflection)
            n.shapeSharpness = l(shapeSharpness, t.shapeSharpness); n.colorSharpness = l(colorSharpness, t.colorSharpness)
            n.colorScale = l(colorScale, t.colorScale)
            n.grainAmount = l(grainAmount, t.grainAmount); n.grainSize = l(grainSize, t.grainSize)
            n.focus = l(focus, t.focus); n.blur = l(blur, t.blur); n.musicIntensity = l(musicIntensity, t.musicIntensity)
            n.azimuth = l(azimuth, t.azimuth); n.polar = l(polar, t.polar); n.distance = l(distance, t.distance)
            n.zoom = l(zoom, t.zoom); n.fov = l(fov, t.fov)
            n.position = l3(position, t.position); n.rotation = l3(rotation, t.rotation)
        }
        self = n
    }

    /// Music reactivity for a beat `level` (0–1): Strength swells, or Color slides each color toward the next
    /// (1 → 2 → 3 → 1), up to a full step at the top intensity.
    mutating func react(to level: Float) {
        guard musicColor else { strength *= 1 + musicIntensity * level; return }
        let k = min(1, musicIntensity * level / 3)
        (c1, c2, c3) = (c1 + (c2 - c1) * k, c2 + (c3 - c2) * k, c3 + (c1 - c3) * k)
    }

    /// uTime the shader sees after `elapsed` seconds of playback, as the library's clock computes it.
    func time(elapsed: Double) -> Float {
        guard animate else { return uTime }
        if rangeOn && rangeEnd > rangeStart { return rangeStart + Float(elapsed.truncatingRemainder(dividingBy: Double(rangeEnd - rangeStart))) }
        return Float(elapsed)
    }
}

/// Pattern prop values, in the shader's order.
let patternKinds = ["noise": 0, "warp": 1, "cells": 2, "ridged": 3, "waves": 4]

/// ShaderGradient feeds hex/255 straight into the shader and writes the result without color management.
func hexColor(_ s: String) -> SIMD3<Float> {
    let h = s.hasPrefix("#") ? String(s.dropFirst()) : s
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return [0, 0, 0] }
    return [Float((v >> 16) & 255) / 255, Float((v >> 8) & 255) / 255, Float(v & 255) / 255]
}

private func perspective(fovY: Float, aspect: Float, zoom: Float, near: Float = 0.1, far: Float = 1000) -> simd_float4x4 {
    let ys = zoom / tan(fovY / 2), xs = ys / aspect, zs = far / (near - far)
    return simd_float4x4(columns: ([xs, 0, 0, 0], [0, ys, 0, 0], [0, 0, zs, -1], [0, 0, near * zs, 0]))
}

private func lookAt(eye: SIMD3<Float>, up: SIMD3<Float> = [0, 1, 0]) -> simd_float4x4 {
    let f = normalize(-eye), s = normalize(cross(f, up)), u = cross(s, f)
    return simd_float4x4(columns: ([s.x, u.x, -f.x, 0], [s.y, u.y, -f.y, 0], [s.z, u.z, -f.z, 0], [-dot(s, eye), -dot(u, eye), dot(f, eye), 1]))
}

private func rotation(_ axis: SIMD3<Float>, _ deg: Float) -> simd_float4x4 {
    simd_float4x4(simd_quatf(angle: deg * .pi / 180, axis: axis))
}

final class Renderer {
    static let shared = Renderer()
    let device: MTLDevice
    let queue: MTLCommandQueue
    private let scenePipelines: [Int: MTLRenderPipelineState] // by sample count
    /// 4× MSAA on the 3D scene pass: smooths mesh edges (sphere silhouette, plane folds) at some GPU cost.
    var antialias = false
    static let msaaSamples = 4
    /// Depth and MSAA buffers live only in on-chip tile memory (Apple GPUs; Intel falls back to .private):
    /// less memory and bandwidth, identical image, since neither is read after the pass.
    var tileMemory = true
    private lazy var memorylessOK = device.supportsFamily(.apple1)
    private let finalPipeline: MTLRenderPipelineState
    private let bokehPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private var meshes: [SIMD2<Int>: (vertices: MTLBuffer, indices: MTLBuffer, count: Int)] = [:]
    static let outputFormat = MTLPixelFormat.bgra8Unorm

    private init() {
        device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        let lib = try! device.makeLibrary(source: shaderSource, options: nil)
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = lib.makeFunction(name: "sceneVertex")
        d.fragmentFunction = lib.makeFunction(name: "sceneFragment")
        d.colorAttachments[0].pixelFormat = .rgba16Float
        d.depthAttachmentPixelFormat = .depth32Float
        var pipes: [Int: MTLRenderPipelineState] = [:]
        for n in [1, Renderer.msaaSamples] {
            d.rasterSampleCount = n
            pipes[n] = try! device.makeRenderPipelineState(descriptor: d)
        }
        scenePipelines = pipes
        let q = MTLRenderPipelineDescriptor()
        q.vertexFunction = lib.makeFunction(name: "quadVertex")
        q.fragmentFunction = lib.makeFunction(name: "finalFragment")
        q.colorAttachments[0].pixelFormat = Renderer.outputFormat
        finalPipeline = try! device.makeRenderPipelineState(descriptor: q)
        q.fragmentFunction = lib.makeFunction(name: "bokehFragment")
        q.colorAttachments[0].pixelFormat = .rgba16Float
        bokehPipeline = try! device.makeRenderPipelineState(descriptor: q)
        let ds = MTLDepthStencilDescriptor()
        ds.depthCompareFunction = .less
        ds.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: ds)!
    }

    /// `level` subdivides the library's segment counts by 2^level (0 = ShaderGradient's mesh).
    private func mesh(_ type: Int, _ level: Int) -> (vertices: MTLBuffer, indices: MTLBuffer, count: Int) {
        if let m = meshes[[type, level]] { return m }
        let k = 1 << level
        var v: [Float] = [], idx: [UInt32] = []
        func grid(_ ws: Int, _ hs: Int, _ vertex: (Float, Float) -> [Float]) {
            for iy in 0...hs { for ix in 0...ws { v += vertex(Float(ix) / Float(ws), Float(iy) / Float(hs)) } }
            for iy in 0..<hs { for ix in 0..<ws {
                let a = UInt32(ix + (ws + 1) * iy), b = UInt32(ix + (ws + 1) * (iy + 1))
                idx += [a, b, a + 1, b, b + 1, a + 1]
            } }
        }
        if type == 2 {
            // UV sphere instead of three's detail-64 icosahedron; uv.y = latitude matches its uv mapping, which drives the twist.
            grid(256 * k, 128 * k) { u, t in
                let th = u * 2 * .pi, ph = t * .pi
                let p: [Float] = [-cos(th) * sin(ph), cos(ph), sin(th) * sin(ph)]
                return p + p + [u, 1 - t]
            }
        } else {
            let ws = 1 + (type == 1 ? 191 : 0) // PlaneGeometry(10, 10, 1, 192) / waterPlane (10, 10, 192, 192)
            // The plane's single horizontal segment is its look (more would sample the noise into a different pattern).
            grid(type == 1 ? ws * k : ws, 192 * k) { u, t in [u * 10 - 5, 5 - t * 10, 0, 0, 0, 1, u, 1 - t] }
        }
        let m = (device.makeBuffer(bytes: v, length: v.count * 4)!, device.makeBuffer(bytes: idx, length: idx.count * 4)!, idx.count)
        meshes[[type, level]] = m
        return m
    }

    func uniforms(_ p: GradientParams, time: Float, aspect: Float) -> Uniforms {
        let sphere = p.type == 2
        let az = p.azimuth * .pi / 180, pol = max(1e-3, min(.pi - 1e-3, p.polar * .pi / 180))
        let r = sphere ? 14 : p.distance
        let eye = SIMD3<Float>(r * sin(pol) * sin(az), r * cos(pol), r * sin(pol) * cos(az))
        let model = simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], SIMD4(p.position, 1)))
            * rotation([1, 0, 0], p.rotation.x) * rotation([0, 1, 0], p.rotation.y) * rotation([0, 0, 1], p.rotation.z)
        let proj = perspective(fovY: p.fov * .pi / 180, aspect: aspect, zoom: sphere ? p.zoom : 1)
        var u = Uniforms()
        u.mvp = proj * lookAt(eye: eye) * model
        u.model = model
        u.c1 = SIMD4(p.c1, 1); u.c2 = SIMD4(p.c2, 1); u.c3 = SIMD4(p.c3, 1)
        u.a = [time, p.speed, p.density, p.strength]
        u.b = [p.frequency, p.amplitude, p.brightness, p.reflection]
        u.c = [Float(p.type), p.env ? 1 : 0, Float(p.envPreset), p.colorScale]
        u.d = [Float(p.shapePattern), p.shapeSharpness, Float(p.colorPattern), p.colorSharpness]
        u.camPos = SIMD4(eye, simd_length(eye - p.position))
        return u
    }

    /// Scene pass into `scene`/`depth`, then the grain (or plain copy) pass into `target`.
    func encode(_ cmd: MTLCommandBuffer, params p: GradientParams, time: Float, fade: Float,
                targets t: Targets, target: MTLTexture, pointSize: CGSize) {
        let scene = t.scene
        let s = MTLRenderPassDescriptor()
        s.colorAttachments[0].texture = t.msaa ?? scene
        s.colorAttachments[0].resolveTexture = t.msaa == nil ? nil : scene
        s.colorAttachments[0].loadAction = .clear
        s.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1000) // alpha = depth: far
        s.colorAttachments[0].storeAction = t.msaa == nil ? .store : .multisampleResolve
        s.depthAttachment.texture = t.depth
        s.depthAttachment.loadAction = .clear
        s.depthAttachment.clearDepth = 1
        s.depthAttachment.storeAction = .dontCare
        let m = mesh(p.type, p.subdivision)
        var u = uniforms(p, time: time, aspect: Float(scene.width) / Float(max(1, scene.height)))
        let e = cmd.makeRenderCommandEncoder(descriptor: s)!
        e.setRenderPipelineState(scenePipelines[t.msaa?.sampleCount ?? 1]!)
        e.setDepthStencilState(depthState)
        e.setCullMode(.none)
        e.setVertexBuffer(m.vertices, offset: 0, index: 0)
        e.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        e.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        e.drawIndexedPrimitives(type: .triangle, indexCount: m.count, indexType: .uint32, indexBuffer: m.indices, indexBufferOffset: 0)
        e.endEncoding()

        var source = scene
        if p.bokeh && p.blur > 0 {
            let b = MTLRenderPassDescriptor()
            b.colorAttachments[0].texture = t.blur
            b.colorAttachments[0].loadAction = .dontCare
            b.colorAttachments[0].storeAction = .store
            // Largest radius scales with the scene height, so it looks the same at any resolution or scene scale.
            var bp = SIMD4<Float>(p.focus, p.blur * 0.06 * Float(scene.height), 0, 0)
            let be = cmd.makeRenderCommandEncoder(descriptor: b)!
            be.setRenderPipelineState(bokehPipeline)
            be.setFragmentTexture(scene, index: 0)
            be.setFragmentBytes(&bp, length: 16, index: 0)
            be.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            be.endEncoding()
            source = t.blur
        }

        let f = MTLRenderPassDescriptor()
        f.colorAttachments[0].texture = target
        f.colorAttachments[0].loadAction = .dontCare
        f.colorAttachments[0].storeAction = .store
        var fp = [SIMD4<Float>(Float(pointSize.width), Float(pointSize.height), p.grain ? p.grainAmount : 0, fade), SIMD4<Float>(p.grainSize, 0, 0, 0)]
        let q = cmd.makeRenderCommandEncoder(descriptor: f)!
        q.setRenderPipelineState(finalPipeline)
        q.setFragmentTexture(source, index: 0)
        q.setFragmentBytes(&fp, length: 32, index: 0)
        q.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        q.endEncoding()
    }

    /// `msaa` is the multisampled color target resolved into `scene`; nil when antialiasing is off. `blur` holds the
    /// bokeh pass output.
    typealias Targets = (scene: MTLTexture, depth: MTLTexture, msaa: MTLTexture?, blur: MTLTexture)

    /// The scene pass resolution for a `width`×`height` output: `scale` < 1 renders the 3D scene smaller and the final
    /// pass scales it up (the gradient is smooth, so it barely shows); grain is always drawn at the full size.
    static func sceneSize(width: Int, height: Int, scale: Float) -> (Int, Int) {
        (max(1, Int((Float(width) * scale).rounded())), max(1, Int((Float(height) * scale).rounded())))
    }

    func makeTargets(width: Int, height: Int, scale: Float = 1) -> Targets {
        let (w, h) = Renderer.sceneSize(width: width, height: height, scale: scale)
        let n = antialias ? Renderer.msaaSamples : 1
        let transient: MTLStorageMode = tileMemory && memorylessOK ? .memoryless : .private
        func tex(_ f: MTLPixelFormat, _ usage: MTLTextureUsage, samples: Int, storage: MTLStorageMode = .private) -> MTLTexture {
            let t = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: f, width: w, height: h, mipmapped: false)
            if samples > 1 { t.textureType = .type2DMultisample; t.sampleCount = samples }
            t.usage = usage
            t.storageMode = storage
            return device.makeTexture(descriptor: t)!
        }
        return (tex(.rgba16Float, [.renderTarget, .shaderRead], samples: 1), tex(.depth32Float, .renderTarget, samples: n, storage: transient),
                n > 1 ? tex(.rgba16Float, .renderTarget, samples: n, storage: transient) : nil,
                tex(.rgba16Float, [.renderTarget, .shaderRead], samples: 1))
    }

    /// A still sized `pointSize` × `scale` pixels, with grain at the live views' scale. The grain's 2 pt dot grid aliases
    /// into moiré when resampled, so render 3× larger and filter down. Used by the gallery cards and the website.
    func thumbnail(_ props: Props, pointSize: CGSize, scale: Int = 2, elapsed: Double = 3.5) -> CGImage? {
        let w = Int(pointSize.width) * scale, h = Int(pointSize.height) * scale
        guard let big = snapshot(props, width: w * 3, height: h * 3, elapsed: elapsed, pointSize: pointSize),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(big, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Offscreen render for thumbnails (a couple of seconds into the animation).
    /// `pointSize` sets the grain's scale (dots are sized in points); default is one point per pixel.
    func snapshot(_ props: Props, width: Int, height: Int, elapsed: Double = 2, pointSize: CGSize? = nil) -> CGImage? {
        let p = GradientParams(props)
        let t = makeTargets(width: width, height: height)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: width, height: height, mipmapped: false)
        td.usage = .renderTarget
        td.storageMode = .private
        guard let target = device.makeTexture(descriptor: td),
              let buf = device.makeBuffer(length: width * height * 4, options: .storageModeShared),
              let cmd = queue.makeCommandBuffer() else { return nil }
        encode(cmd, params: p, time: p.time(elapsed: elapsed), fade: 1, targets: t, target: target,
               pointSize: pointSize ?? CGSize(width: width, height: height))
        let blit = cmd.makeBlitCommandEncoder()!
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: buf, destinationOffset: 0, destinationBytesPerRow: width * 4, destinationBytesPerImage: width * height * 4)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        guard let provider = CGDataProvider(data: Data(bytes: buf.contents(), count: width * height * 4) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// A live gradient. Set `props` any time; continuous values ease over ~0.4s.
class GradientView: MTKView, MTKViewDelegate {
    var props: Props = [:] { didSet { propsChanged() } }
    /// 0 = black, 1 = visible; the saver fades through black between gradients.
    var fade: Float = 1
    private var first = true
    private var current = GradientParams([:])
    private var target = GradientParams([:])
    private var elapsed = 0.0 // animation clock: advances only while drawing, so a resumed view continues where it paused
    private var last = CACurrentMediaTime()
    private var rampIn = 1.0
    private var targets: Renderer.Targets?
    private var targetsSpec = SIMD4<Int>() // drawable w, h, scene scale ‰, msaa | tile memory: rebuild targets when any changes
    /// Scene pass resolution relative to the 1× drawable (see Renderer.sceneSize).
    var sceneScale: Float = 1
    /// Draw the grain pass at the screen's Retina scale (scene size unchanged): silhouettes against black lose their
    /// 2 px stair steps, at about 3× the GPU time.
    /// The beat level (0–1) music-reactive gradients follow; the app sets it to its system audio tap.
    static var audioLevel: () -> Float = { 0 }
    var retina = false { didSet { if retina != oldValue { updateDrawableSize() } } }
    private var backing: CGFloat { retina ? (window?.backingScaleFactor ?? 2) : 1 }

    init(props: Props = [:]) {
        super.init(frame: .zero, device: Renderer.shared.device)
        colorPixelFormat = Renderer.outputFormat
        colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        autoResizeDrawable = false
        preferredFramesPerSecond = 60
        delegate = self
        self.props = props
        propsChanged() // didSet doesn't run inside init
    }

    private func propsChanged() {
        let t = GradientParams(props)
        if first { current = t; first = false }
        target = t
        updateDrawableSize()
    }
    required init(coder: NSCoder) { fatalError() }

    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); updateDrawableSize() }

    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); updateDrawableSize() }

    /// Like the canvas' dpr = pixelDensity: render at points × pixelDensity, ignoring the Retina scale unless `retina`.
    private func updateDrawableSize() {
        let d = CGFloat(target.pixelDensity) * backing
        let s = CGSize(width: max(1, (bounds.width * d).rounded()), height: max(1, (bounds.height * d).rounded()))
        if drawableSize != s { drawableSize = s }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { targets = nil }

    /// The animation time of the system-wallpaper still (Store.matchSystemWallpaper).
    static let stillTime = 3.5
    /// Jumps to the still's frame and draws it, e.g. right before pausing.
    func showStill() {
        current = target
        elapsed = GradientView.stillTime
        rampIn = 0
        last = CACurrentMediaTime()
        draw()
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = min(now - last, 0.1) // a long gap means we were paused: don't jump ahead
        current.approach(target, 1 - exp(-Float(dt) * 8))
        // After showStill, speed eases up from 0 over ~1.2 s, so the still comes alive instead of restarting.
        rampIn = min(1, rampIn + dt / 1.2)
        elapsed += dt * rampIn * rampIn * (3 - 2 * rampIn)
        last = now
        guard let drawable = currentDrawable, let cmd = Renderer.shared.queue.makeCommandBuffer() else { return }
        let w = drawable.texture.width, h = drawable.texture.height
        let r = Renderer.shared
        let scale = sceneScale / Float(backing)
        let spec = SIMD4(w, h, Int(scale * 1000), (r.antialias ? 1 : 0) | (r.tileMemory ? 2 : 0))
        if targets == nil || spec != targetsSpec {
            targets = r.makeTargets(width: w, height: h, scale: scale)
            targetsSpec = spec
        }
        var p = current
        // Read every frame, past the easing in `approach`, which would smear the beats.
        if p.music { p.react(to: GradientView.audioLevel()) }
        Renderer.shared.encode(cmd, params: p, time: current.time(elapsed: elapsed), fade: fade,
                               targets: targets!, target: drawable.texture, pointSize: bounds.size)
        cmd.present(drawable)
        cmd.commit()
    }
}
