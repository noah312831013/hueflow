// Live ShaderGradients for the landing page: the hero (window.setHero(name) swaps presets, used by the gallery) and
// the "Make it yours" editor, whose controls mirror the app's editor tabs.
import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { ShaderGradientCanvas, ShaderGradient, presets } from '@shadergradient/react';
import { setPatternProps } from './patterns.js';

// Afterglow is Hueflow's own preset and the free version's wallpaper (native/Shared/Presets.swift).
const afterglow = {"uFrequency": 2.2, "fov": 45, "positionY": 0.038, "brightness": 1.3, "lightType": "3d", "pixelDensity": 1, "bgColor1": "#000000", "cAzimuthAngle": 79.4, "cPolarAngle": 69.8, "color1": "#ff7a33", "reflection": 0.4, "cDistance": 2.9, "wireframe": false, "animate": "on", "axesHelper": "on", "color3": "#ffc53d", "cameraZoom": 19.5, "positionX": 0.859, "color2": "#33a0ff", "bgColor2": "#000000", "rotationX": -74, "positionZ": -0.824, "grainAmount": 0.5, "rotationZ": 0, "rotationY": 1, "uDensity": 1.2, "envPreset": "city", "type": "waterPlane", "uStrength": 1.3, "uTime": 0, "grain": "on", "saturation": 0.6, "uSpeed": 0.1, "grainSize": 1.5, "uAmplitude": 2.3};
const byName = { Afterglow: afterglow, ...Object.fromEntries(Object.values(presets).map((p) => [p.title, p.props])) };
const canvasProps = { pixelDensity: 1, fov: 45, pointerEvents: 'none', envBasePath: 'assets/hdr/' };

function Hero() {
  const [props, setProps] = useState(byName.Afterglow);
  useEffect(() => {
    window.setHero = (name) => byName[name] && setProps(byName[name]);
  }, []);
  return (
    <ShaderGradientCanvas style={{ position: 'absolute', inset: 0, background: '#000' /* empty scene is transparent: don't show the poster through it */ }} lazyLoad={false} {...canvasProps}>
      <ShaderGradient {...props} control="props" />
    </ShaderGradientCanvas>
  );
}

// Same keys, labels, ranges and Advanced split as the app's editor (native/App/GalleryView.swift). Pattern keys go to
// src/patterns.js's uniforms instead of ShaderGradient.
const patternKeys = ['shapePattern', 'shapeSharpness', 'colorPattern', 'colorScale', 'colorSharpness', 'saturation'];
const patternNames = [['noise', 'Noise'], ['warp', 'Warp'], ['cells', 'Cells'], ['ridged', 'Ridged'], ['waves', 'Waves']];
const hasColorPattern = (p) => (p.colorPattern ?? 'position') !== 'position';
const isSphere = (p) => p.type === 'sphere';
const isEnv = (p) => p.lightType === 'env';
const onOff = [['on', 'On'], ['off', 'Off']];
const tabs = {
  Shape: [
    { key: 'type', label: 'Type', options: [['plane', 'Plane'], ['waterPlane', 'Water'], ['sphere', 'Sphere']] },
    { key: 'shapePattern', label: 'Pattern', options: patternNames, fallback: 'noise' },
    { key: 'uSpeed', label: 'Speed', range: [0, 2, 0.1] },
    { key: 'uStrength', label: 'Strength', range: [0, 10, 0.1] },
    { key: 'uDensity', label: 'Density', range: [0, 7, 0.1] },
    { key: 'shapeSharpness', label: 'Sharpness', range: [0, 1, 0.05], fallback: 0.5, advanced: true },
    { key: 'uFrequency', label: 'Frequency', range: [0, 10, 0.1], show: isSphere, advanced: true },
    { key: 'uAmplitude', label: 'Spiral', range: [0, 10, 0.1], show: isSphere, advanced: true },
  ],
  Colors: [
    { key: 'color1', label: 'Color 1', color: true },
    { key: 'color2', label: 'Color 2', color: true },
    { key: 'color3', label: 'Color 3', color: true },
    { key: 'colorPattern', label: 'Pattern', options: [['position', 'Gradient'], ...patternNames], fallback: 'position' },
    { key: 'saturation', label: 'Saturation', range: [0, 2, 0.05], fallback: 1 },
    { key: 'colorScale', label: 'Scale', range: [0.1, 5, 0.1], show: hasColorPattern, fallback: 1, advanced: true },
    { key: 'colorSharpness', label: 'Sharpness', range: [0, 1, 0.05], show: hasColorPattern, fallback: 0.5, advanced: true },
  ],
  Effects: [
    { key: 'grain', label: 'Grain', options: onOff },
    { key: 'lightType', label: 'Lighting', options: [['3d', 'Lights'], ['env', 'Environment']] },
    { key: 'brightness', label: 'Brightness', range: [0.1, 3, 0.1], show: (p) => !isEnv(p) },
    { key: 'envPreset', label: 'Environment', options: [['city', 'City'], ['dawn', 'Dawn'], ['lobby', 'Lobby']], show: isEnv },
    { key: 'reflection', label: 'Reflection', range: [0, 1, 0.1], show: isEnv, advanced: true },
  ],
  Camera: [
    { key: 'cAzimuthAngle', label: 'Azimuth', range: [0, 360, 1] },
    { key: 'cPolarAngle', label: 'Polar', range: [0, 180, 1] },
    { key: 'cDistance', label: 'Distance', range: [0, 20, 0.1] },
    { key: 'cameraZoom', label: 'Zoom', range: [0.1, 30, 0.1] },
  ],
};

function Control({ spec, props, set }) {
  const v = props[spec.key] ?? spec.fallback;
  if (spec.options && spec.options.length > 4) {
    // Like the app: more than 4 segments don't fit the panel.
    return (
      <label className="ctl">
        <span>{spec.label}</span>
        <select value={v} onChange={(e) => set(spec.key, e.target.value)}>
          {spec.options.map(([value, text]) => <option key={value} value={value}>{text}</option>)}
        </select>
      </label>
    );
  }
  if (spec.options) {
    return (
      <div className="ctl">
        <span>{spec.label}</span>
        <div className="seg" role="radiogroup" aria-label={spec.label}>
          {spec.options.map(([value, text]) => (
            <button key={value} role="radio" aria-checked={v === value} className={v === value ? 'on' : ''} onClick={() => set(spec.key, value)}>{text}</button>
          ))}
        </div>
      </div>
    );
  }
  if (spec.color) {
    return (
      <label className="ctl row">
        <span>{spec.label}</span>
        <input type="color" value={v} onChange={(e) => set(spec.key, e.target.value)} />
      </label>
    );
  }
  const [lo, hi, step] = spec.range;
  const n = Math.min(hi, Math.max(lo, Number(v ?? lo)));
  return (
    <label className="ctl">
      <span>{spec.label}<output>{step < 0.1 ? n.toFixed(2) : step < 1 ? n.toFixed(1) : n}</output></span>
      <input type="range" min={lo} max={hi} step={step} value={n} onChange={(e) => set(spec.key, Number(e.target.value))} />
    </label>
  );
}

function Editor() {
  const [preset, setPreset] = useState('Afterglow');
  const [props, setProps] = useState(byName.Afterglow);
  const [tab, setTab] = useState('Shape');
  const [showAdvanced, setShowAdvanced] = useState(false);
  const set = (key, value) => setProps((p) => ({ ...p, [key]: value }));
  const pick = (name) => { setPreset(name); setProps(byName[name]); };
  useEffect(() => setPatternProps(props), [props]);
  const visible = tabs[tab].filter((s) => !s.show || s.show(props));
  const advanced = visible.filter((s) => s.advanced);
  const gradientProps = Object.fromEntries(Object.entries(props).filter(([k]) => !patternKeys.includes(k)));
  return (
    <>
      <div className="editor-stage">
        <ShaderGradientCanvas style={{ position: 'absolute', inset: 0, background: '#000' /* empty scene is transparent: don't show the poster through it */ }} lazyLoad {...canvasProps}>
          <ShaderGradient {...gradientProps} control="props" />
        </ShaderGradientCanvas>
      </div>
      <div className="editor-panel">
        <div className="chips" aria-label="Start from">
          {Object.keys(byName).map((name) => (
            <button key={name} className={name === preset ? 'on' : ''} onClick={() => pick(name)}>{name}</button>
          ))}
        </div>
        <div className="tabs" role="tablist">
          {Object.keys(tabs).map((t) => (
            <button key={t} role="tab" aria-selected={t === tab} className={t === tab ? 'on' : ''} onClick={() => setTab(t)}>{t}</button>
          ))}
        </div>
        <div className="ctls">
          {visible.filter((s) => !s.advanced).map((s) => <Control key={s.key} spec={s} props={props} set={set} />)}
          {advanced.length > 0 && (
            <button className={'adv' + (showAdvanced ? ' open' : '')} aria-expanded={showAdvanced} onClick={() => setShowAdvanced(!showAdvanced)}>Advanced</button>
          )}
          {showAdvanced && advanced.map((s) => <Control key={s.key} spec={s} props={props} set={set} />)}
        </div>
        <button className="reset" onClick={() => pick(preset)}>Reset {preset}</button>
      </div>
    </>
  );
}

// Static images stay in place if WebGL is unavailable.
try {
  if (document.createElement('canvas').getContext('webgl2')) {
    createRoot(document.getElementById('hero-canvas')).render(<Hero />);
    const editor = document.getElementById('editor-root');
    if (editor) { editor.classList.add('live'); createRoot(editor).render(<Editor />); }
  }
} catch {}
