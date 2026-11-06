// Bundles site/src/hero.jsx into site/hero.js. Run: npm run build
// It also makes ShaderGradient's material call window.__sgPatch(shader, renderer) from onBeforeCompile, so
// src/patterns.js can add the app's patterns. The match is against @shadergradient/react 2.4.20's minified code
// (pinned in package.json); the build fails if it changes.
import { build } from 'esbuild';
import { readFile } from 'node:fs/promises';

const target = 'onBeforeCompile:o=>{o.uniforms=n(n(n({},o.uniforms),F),w),o.vertexShader=H,o.fragmentShader=M}';
let patched = 0;

const hook = {
  name: 'shadergradient-pattern-hook',
  setup(b) {
    b.onLoad({ filter: /@shadergradient[\\/]react[\\/]dist[\\/].*\.mjs$/ }, async (args) => {
      const src = await readFile(args.path, 'utf8');
      if (!src.includes(target)) return undefined;
      patched++;
      return {
        contents: src.replace(target, target.replace('o=>{', '(o,rr)=>{').replace(/}$/, ',globalThis.__sgPatch&&globalThis.__sgPatch(o,rr)}')),
        loader: 'js',
      };
    });
    b.onEnd(() => {
      if (patched !== 1) throw new Error(`ShaderGradient hook: patched ${patched} files, expected 1 (library code changed?)`);
    });
  },
};

await build({
  entryPoints: ['site/src/hero.jsx'],
  bundle: true,
  minify: true,
  define: { 'process.env.NODE_ENV': '"production"' },
  outfile: 'site/hero.js',
  plugins: [hook],
  logLevel: 'info',
});
