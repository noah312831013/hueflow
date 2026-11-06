// The app's shape and color patterns (native/Shared/Renderer.swift), injected into ShaderGradient's shaders for the
// website editor. site/build.mjs makes the library call window.__sgPatch(shader, renderer) from its onBeforeCompile;
// only canvases inside #editor-root get patterns, so the hero stays plain ShaderGradient.

export const patternKinds = { noise: 0, warp: 1, cells: 2, ridged: 3, waves: 4 };

// Shared uniform objects: the editor writes .value, every patched program reads them.
export const sgUniforms = {
  uShapePattern: { value: 0 }, uShapeSharp: { value: 0.5 },
  uColorPattern: { value: 0 }, uColorSharp: { value: 0.5 }, uColorScale: { value: 1 },
};

/** Props from the editor -> uniform values (same defaults and clamps as GradientParams in the app). */
export function setPatternProps(p) {
  const clamp = (v, lo, hi, d) => Math.min(hi, Math.max(lo, Number.isFinite(+v) ? +v : d));
  sgUniforms.uShapePattern.value = patternKinds[p.shapePattern] ?? 0;
  sgUniforms.uShapeSharp.value = clamp(p.shapeSharpness, 0, 1, 0.5);
  sgUniforms.uColorPattern.value = p.colorPattern in patternKinds ? patternKinds[p.colorPattern] + 1 : 0;
  sgUniforms.uColorSharp.value = clamp(p.colorSharpness, 0, 1, 0.5);
  sgUniforms.uColorScale.value = clamp(p.colorScale, 0.1, 5, 1);
}

// Prefixed names: the library's vertex shader already defines cnoise, mod289, permute...
const glsl = /* glsl */ `
uniform float uShapePattern, uShapeSharp, uColorPattern, uColorSharp, uColorScale;
vec3 sgMod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 sgMod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 sgPermute(vec4 x) { return sgMod289(((x * 34.0) + 1.0) * x); }
vec4 sgTaylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }
vec3 sgFade(vec3 t) { return t * t * t * (t * (t * 6.0 - 15.0) + 10.0); }
float sgNoise(vec3 P) {
  vec3 Pi0 = sgMod289(floor(P)), Pi1 = sgMod289(floor(P) + 1.0);
  vec3 Pf0 = fract(P), Pf1 = Pf0 - vec3(1.0);
  vec4 ix = vec4(Pi0.x, Pi1.x, Pi0.x, Pi1.x), iy = vec4(Pi0.yy, Pi1.yy);
  vec4 iz0 = Pi0.zzzz, iz1 = Pi1.zzzz;
  vec4 ixy = sgPermute(sgPermute(ix) + iy);
  vec4 ixy0 = sgPermute(ixy + iz0), ixy1 = sgPermute(ixy + iz1);
  vec4 gx0 = ixy0 * (1.0 / 7.0), gy0 = fract(floor(gx0) * (1.0 / 7.0)) - 0.5;
  gx0 = fract(gx0);
  vec4 gz0 = vec4(0.5) - abs(gx0) - abs(gy0), sz0 = step(gz0, vec4(0.0));
  gx0 -= sz0 * (step(0.0, gx0) - 0.5); gy0 -= sz0 * (step(0.0, gy0) - 0.5);
  vec4 gx1 = ixy1 * (1.0 / 7.0), gy1 = fract(floor(gx1) * (1.0 / 7.0)) - 0.5;
  gx1 = fract(gx1);
  vec4 gz1 = vec4(0.5) - abs(gx1) - abs(gy1), sz1 = step(gz1, vec4(0.0));
  gx1 -= sz1 * (step(0.0, gx1) - 0.5); gy1 -= sz1 * (step(0.0, gy1) - 0.5);
  vec3 g000 = vec3(gx0.x, gy0.x, gz0.x), g100 = vec3(gx0.y, gy0.y, gz0.y);
  vec3 g010 = vec3(gx0.z, gy0.z, gz0.z), g110 = vec3(gx0.w, gy0.w, gz0.w);
  vec3 g001 = vec3(gx1.x, gy1.x, gz1.x), g101 = vec3(gx1.y, gy1.y, gz1.y);
  vec3 g011 = vec3(gx1.z, gy1.z, gz1.z), g111 = vec3(gx1.w, gy1.w, gz1.w);
  vec4 norm0 = sgTaylorInvSqrt(vec4(dot(g000, g000), dot(g010, g010), dot(g100, g100), dot(g110, g110)));
  g000 *= norm0.x; g010 *= norm0.y; g100 *= norm0.z; g110 *= norm0.w;
  vec4 norm1 = sgTaylorInvSqrt(vec4(dot(g001, g001), dot(g011, g011), dot(g101, g101), dot(g111, g111)));
  g001 *= norm1.x; g011 *= norm1.y; g101 *= norm1.z; g111 *= norm1.w;
  float n000 = dot(g000, Pf0), n100 = dot(g100, vec3(Pf1.x, Pf0.yz)), n010 = dot(g010, vec3(Pf0.x, Pf1.y, Pf0.z));
  float n110 = dot(g110, vec3(Pf1.xy, Pf0.z)), n001 = dot(g001, vec3(Pf0.xy, Pf1.z)), n101 = dot(g101, vec3(Pf1.x, Pf0.y, Pf1.z));
  float n011 = dot(g011, vec3(Pf0.x, Pf1.yz)), n111 = dot(g111, Pf1);
  vec3 f = sgFade(Pf0);
  vec4 n_z = mix(vec4(n000, n100, n010, n110), vec4(n001, n101, n011, n111), f.z);
  vec2 n_yz = mix(n_z.xy, n_z.zw, f.y);
  return 2.2 * mix(n_yz.x, n_yz.y, f.x);
}
vec3 sgHash3(vec3 p) {
  p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
  return fract(sin(p) * 43758.5453);
}
float sgWarp(vec3 p) {
  vec3 q = vec3(sgNoise(p), sgNoise(p + vec3(5.2, 1.3, 2.8)), sgNoise(p + vec3(1.7, 9.2, 4.1)));
  return sgNoise(p + 1.5 * q);
}
float sgCells(vec3 p, float k) {
  vec3 i = floor(p), f = fract(p);
  float sum = 0.0;
  for (int z = -1; z <= 1; z++) for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
    vec3 g = vec3(float(x), float(y), float(z));
    sum += exp(-k * length(g + sgHash3(i + g) - f));
  }
  return 1.0 - 2.0 * clamp(-log(sum) / k + 0.25, 0.0, 1.0);
}
float sgRidged(vec3 p) {
  float s = 0.0, a = 0.5;
  for (int i = 0; i < 3; i++) { float n = 1.0 - abs(sgNoise(p)); s += n * n * a; p *= 2.0; a *= 0.5; }
  return s / 0.875 * 2.0 - 1.0;
}
float sgWaves(vec3 p) {
  return (sin(p.x * 2.0 + p.y * 0.7) + sin(p.y * 2.3 - p.z * 1.1 + 1.3) + sin(length(p.xz) * 3.0)) / 3.0;
}
float sgPattern(int kind, vec3 p, float sharp) {
  float v = kind == 1 ? sgWarp(p) : kind == 2 ? sgCells(p, mix(3.0, 24.0, sharp)) : kind == 3 ? sgRidged(p) : kind == 4 ? sgWaves(p) : sgNoise(p);
  if (kind == 2 || abs(sharp - 0.5) < 1e-3) return v;
  return sign(v) * pow(abs(v), exp2((0.5 - sharp) * 3.0));
}
`;

// Each edit must match exactly once, or the shader would silently stay unpatched.
function edit(src, find, replace, what) {
  const n = src.split(find).length - 1;
  if (n !== 1) throw new Error(`Hueflow patterns: expected 1 "${what}" in ShaderGradient's shader, found ${n}`);
  return src.replace(find, replace);
}

const defaultShape = 'uShapePattern < 0.5 && abs(uShapeSharp - 0.5) < 1e-3';

function patch(shader, sphere) {
  let v = shader.vertexShader, f = shader.fragmentShader;
  v = edit(v, 'void main()', glsl + '\nvoid main()', 'void main() (vertex)');
  v = sphere
    ? edit(v, 'distortion = pnoise((normal + t) * uNoiseDensity, vec3(10.0)) * uNoiseStrength;',
        `distortion = (${defaultShape} ? pnoise((normal + t) * uNoiseDensity, vec3(10.0))
                       : sgPattern(int(uShapePattern), (normal + t) * uNoiseDensity, uShapeSharp)) * uNoiseStrength;`, 'sphere distortion')
    : edit(v, 'distortion = 0.75 * cnoise(noisePos + t);',
        `distortion = 0.75 * (${defaultShape} ? cnoise(noisePos + t) : sgPattern(int(uShapePattern), noisePos + t, uShapeSharp));`, 'plane distortion');
  // The fragment shader may not declare the clock; the values come from the same uniforms object.
  const clock = ['uTime', 'uSpeed'].filter((u) => !new RegExp(`uniform float ${u};`).test(f)).map((u) => `uniform float ${u};\n`).join('');
  f = edit(f, 'void main()', clock + glsl + '\nvoid main()', 'void main() (fragment)');
  const base = f.match(/vec4 diffuseColor\s*=[\s\S]*?;/);
  if (!base) throw new Error('Hueflow patterns: diffuseColor not found in ShaderGradient\'s shader');
  f = f.replace(base[0], `${base[0]}
  if (uColorPattern > 0.5) {
    // Three-stop ramp c1 -> c2 -> c3 over the pattern, drifting slower than the shape.
    vec3 sgP = vPos * ${sphere ? '1.5' : '0.6'} * uColorScale + uTime * uSpeed * 0.5;
    float sgF = clamp(sgPattern(int(uColorPattern) - 1, sgP, uColorSharp) * 0.8 + 0.5, 0.0, 1.0);
    diffuseColor.rgb = mix(mix(color1, color2, smoothstep(0.0, 0.5, sgF)), color3, smoothstep(0.5, 1.0, sgF));
  }`);
  return [v, f];
}

window.__sgPatch = (shader, renderer) => {
  if (!renderer?.domElement?.closest?.('#editor-root')) return;
  try {
    // A failed edit leaves the plain ShaderGradient look instead of a broken canvas.
    [shader.vertexShader, shader.fragmentShader] = patch(shader, shader.vertexShader.includes('pnoise((normal + t)'));
    Object.assign(shader.uniforms, sgUniforms);
  } catch (e) { console.error(e); }
};
