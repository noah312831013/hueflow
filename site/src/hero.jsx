// Live ShaderGradient behind the landing page hero. window.setHero(name) swaps presets (used by the gallery).
import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { ShaderGradientCanvas, ShaderGradient, presets } from '@shadergradient/react';

const byName = Object.fromEntries(Object.values(presets).map((p) => [p.title, p.props]));

function Hero() {
  const [props, setProps] = useState(byName.Universe);
  useEffect(() => {
    window.setHero = (name) => byName[name] && setProps(byName[name]);
  }, []);
  return (
    <ShaderGradientCanvas style={{ position: 'absolute', inset: 0 }} pixelDensity={1} fov={45} pointerEvents="none" lazyLoad={false} envBasePath="assets/hdr/">
      <ShaderGradient {...props} control="props" />
    </ShaderGradientCanvas>
  );
}

// Static image stays as the background if WebGL is unavailable.
try {
  if (document.createElement('canvas').getContext('webgl2')) createRoot(document.getElementById('hero-canvas')).render(<Hero />);
} catch {}
