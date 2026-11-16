import * as THREE from 'three';

const F = window.FVSim, L = F.L;
const $ = (id) => document.getElementById(id);
// The language and its interface text (text.js). Spoken lines, names and checkpoints come from sim-core.js.
let lang = window.FVText.lang, T = window.FVText.TEXT[lang];
const fmt = (v, d = 1) => v.toFixed(d).replace('.', T.decimal);
// Colors are defined once, as CSS tokens in shell.html, so the 3D scenes and the interface never drift apart.
// They're read from a view, which keeps the dark values in both appearances.
const viewStyle = getComputedStyle(document.querySelector('.view'));
const token = (name) => viewStyle.getPropertyValue('--' + name).trim();
const HEX = { accent: token('accent'), sure: token('sure'), maybe: token('maybe'), danger: token('danger'), warn: token('warn'), grey: token('frozen'), bg: token('bg') };
const ICON = {
  play: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5.5v13a1 1 0 0 0 1.5.86l10.5-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5z"/></svg>',
  pause: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/></svg>',
  audioOn: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9h3l5-4v14l-5-4H4z"/><path d="M15.5 8.5a5 5 0 0 1 0 7M18.5 5.5a9 9 0 0 1 0 13" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
  audioOff: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9h3l5-4v14l-5-4H4z"/><path d="M16 9l5 6M21 9l-5 6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
};
const raw = (hex) => { const n = parseInt(hex.slice(1), 16); return new THREE.Color().setRGB(((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255); };
const srgb = (c) => new THREE.Color().setRGB(c[0], c[1], c[2], THREE.SRGBColorSpace);
const smooth = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };

// ---------------- simulation ----------------
const M = F.buildMap(11);
let S = F.makeSim();
let playing = false, audioOn = false, waveT = -99, snap = true;

// ---------------- renderers ----------------
const cReal = $('cReal'), cSplat = $('cSplat');
function makeRenderer(canvas, real) {
  const r = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
  r.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  if (real) {
    r.shadowMap.enabled = true; r.shadowMap.type = THREE.PCFSoftShadowMap;
    r.toneMapping = THREE.ACESFilmicToneMapping; r.toneMappingExposure = 1.05;
  }
  return r;
}
const rR = makeRenderer(cReal, true), rS = makeRenderer(cSplat, false);

// ================= LEFT: the real street =================
const sceneR = new THREE.Scene();
const SKY = new THREE.Color('#AFC3D6');
sceneR.background = SKY;
sceneR.fog = new THREE.Fog(SKY, 32, 92);
const camR = new THREE.PerspectiveCamera(55, 1, 0.1, 220);
const hemi = new THREE.HemisphereLight(0xE2EBFF, 0x6B5A48, 1.2);
const sun = new THREE.DirectionalLight(0xFFE0B5, 2.5);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
Object.assign(sun.shadow.camera, { left: -24, right: 24, top: 24, bottom: -24, near: 1, far: 90 });
sun.shadow.bias = -0.0005; sun.shadow.normalBias = 0.03;
sceneR.add(hemi, sun, sun.target);

const std = (color, rough = 0.9, extra = {}) => new THREE.MeshStandardMaterial(Object.assign({ color: typeof color === 'string' ? new THREE.Color(color) : color, roughness: rough }, extra));
function canvasTex(w, h, draw) {
  const c = document.createElement('canvas'); c.width = w; c.height = h; draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 4; return t;
}
const css = (c, k = 1) => `rgb(${Math.round(c[0] * 255 * k)},${Math.round(c[1] * 255 * k)},${Math.round(c[2] * 255 * k)})`;
const facadeCache = new Map();
function facadeTex(c) {
  const key = c.join(',');
  if (!facadeCache.has(key)) {
    facadeCache.set(key, canvasTex(256, 256, (g, w, h) => {
      g.fillStyle = css(c); g.fillRect(0, 0, w, h);
      for (let i = 0; i < 1400; i++) { g.fillStyle = `rgba(0,0,0,${Math.random() * 0.05})`; g.fillRect(Math.random() * w, Math.random() * h, 2, 2); }
      g.fillStyle = css(c, 0.8); g.fillRect(0, h / 2 - 7, w, 7); g.fillRect(0, h - 7, w, 7);
      for (let fy = 0; fy < 2; fy++) for (let fx = 0; fx < 2; fx++) {
        const x = fx * w / 2 + 38, y = fy * h / 2 + 22, ww = 52, hh = 78;
        g.fillStyle = '#2B3038'; g.fillRect(x, y, ww, hh);
        g.fillStyle = '#3E6B51'; g.fillRect(x - 17, y, 15, hh); g.fillRect(x + ww + 2, y, 15, hh);
        g.fillStyle = 'rgba(255,255,255,.18)'; g.fillRect(x - 17, y, 2, hh); g.fillRect(x + ww + 2, y, 2, hh);
        g.fillStyle = css(c, 0.66); g.fillRect(x - 22, y + hh, ww + 44, 5);
        g.strokeStyle = 'rgba(25,25,25,.65)'; g.lineWidth = 2; g.strokeRect(x - 20, y + hh - 24, ww + 40, 24);
      }
    }));
  }
  return facadeCache.get(key);
}
const pave = canvasTex(256, 256, (g, w, h) => {
  g.fillStyle = '#5E5953'; g.fillRect(0, 0, w, h);
  for (let r = 0; r < 4; r++) {
    const off = (r % 2) * 32;
    for (let x = -64; x < w + 64; x += 64) {
      const v = 112 + Math.random() * 28;
      g.fillStyle = `rgb(${v},${v - 5},${v - 12})`; g.fillRect(x + off + 2, r * h / 4 + 2, 60, h / 4 - 4);
    }
  }
});
pave.repeat.set((2 * L.half) / 2.4, (L.zMax - L.zMin) / 2.4);

const ground = new THREE.Mesh(new THREE.PlaneGeometry(2 * L.half, L.zMax - L.zMin + 10), std('#FFFFFF', 0.95, { map: pave }));
ground.rotation.x = -Math.PI / 2; ground.position.set(0, 0, (L.zMin + L.zMax) / 2); ground.receiveShadow = true; sceneR.add(ground);
const sideGround = new THREE.Mesh(new THREE.PlaneGeometry(14, L.side.z1 - L.side.z0), std('#76706A', 1));
sideGround.rotation.x = -Math.PI / 2; sideGround.position.set(-L.half - 7, 0.002, (L.side.z0 + L.side.z1) / 2); sideGround.receiveShadow = true; sceneR.add(sideGround);

const DEPTH = 8;
function addBlock(side, z0, z1, h, c) {
  if (z1 - z0 < 0.3) return;
  const tex = facadeTex(c).clone(); tex.needsUpdate = true; tex.repeat.set((z1 - z0) / 5.2, h / 6.4);
  const plain = std(srgb([c[0] * 0.86, c[1] * 0.86, c[2] * 0.86]), 0.95);
  const face = std('#FFFFFF', 0.92, { map: tex });
  const mats = [plain, plain, plain, plain, plain, plain];
  mats[side > 0 ? 1 : 0] = face;
  const m = new THREE.Mesh(new THREE.BoxGeometry(DEPTH, h, z1 - z0), mats);
  m.position.set(side * (L.half + DEPTH / 2), h / 2, (z0 + z1) / 2); m.castShadow = true; m.receiveShadow = true; sceneR.add(m);
}
for (const b of M.blocks) {
  if (b.side < 0 && b.z1 > L.side.z0 && b.z0 < L.side.z1) {
    addBlock(b.side, b.z0, L.side.z0, b.h, b.c);
    addBlock(b.side, L.side.z1, b.z1, b.h, b.c);
  } else addBlock(b.side, b.z0, b.z1, b.h, b.c);
}
// buildings that close the side street and the two ends of the street
const closer = (x, z, w, d, h, c) => { const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), std(srgb(c), 0.95)); m.position.set(x, h / 2, z); m.castShadow = m.receiveShadow = true; sceneR.add(m); };
closer(-L.half - DEPTH - 4, (L.side.z0 + L.side.z1) / 2, 8, 14, 15, [0.86, 0.78, 0.6]);
closer(0, L.zMax + 6, 40, 8, 18, [0.78, 0.6, 0.45]);
closer(0, L.zMin - 6, 40, 8, 18, [0.78, 0.6, 0.45]);

// covered passage
const stone = std('#CDBFA6', 0.9);
const roof = new THREE.Mesh(new THREE.BoxGeometry(2 * L.half + 0.6, 0.5, L.passage.z1 - L.passage.z0), stone);
roof.position.set(0, L.passage.roof + 0.25, (L.passage.z0 + L.passage.z1) / 2); roof.castShadow = roof.receiveShadow = true; sceneR.add(roof);
for (const zz of [L.passage.z0, L.passage.z1]) {
  const beam = new THREE.Mesh(new THREE.BoxGeometry(2 * L.half, 2.4, 0.6), stone);
  beam.position.set(0, 5.8, zz); beam.castShadow = beam.receiveShadow = true; sceneR.add(beam);
}
// parked van
const van = new THREE.Group();
const vb = L.van;
const vanBody = new THREE.Mesh(new THREE.BoxGeometry(vb.x1 - vb.x0, vb.h - 0.35, vb.z1 - vb.z0 - 0.7), std('#ECEEF2', 0.5));
vanBody.position.set((vb.x0 + vb.x1) / 2, 0.35 + (vb.h - 0.35) / 2, (vb.z0 + 0.7 + vb.z1) / 2);
const cab = new THREE.Mesh(new THREE.BoxGeometry(vb.x1 - vb.x0 - 0.1, 1.55, 0.7), std('#ECEEF2', 0.5));
cab.position.set((vb.x0 + vb.x1) / 2, 0.35 + 0.78, vb.z0 + 0.35);
const shield = new THREE.Mesh(new THREE.BoxGeometry(vb.x1 - vb.x0 - 0.2, 0.55, 0.05), std('#22303C', 0.2));
shield.position.set((vb.x0 + vb.x1) / 2, 1.5, vb.z0 - 0.01);
const stripe = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.22, vb.z1 - vb.z0 - 0.8), std('#5F8FFF', 0.6));
stripe.position.set(vb.x0 - 0.01, 1.2, (vb.z0 + 0.7 + vb.z1) / 2);
van.add(vanBody, cab, shield, stripe);
for (const [x, z] of [[vb.x0, vb.z0 + 0.5], [vb.x1, vb.z0 + 0.5], [vb.x0, vb.z1 - 0.6], [vb.x1, vb.z1 - 0.6]]) {
  const wh = new THREE.Mesh(new THREE.CylinderGeometry(0.34, 0.34, 0.24, 18), std('#1E1F24', 0.8));
  wh.rotation.z = Math.PI / 2; wh.position.set(x, 0.34, z); van.add(wh);
}
van.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
sceneR.add(van);
// bollards
for (const b of L.bollards) {
  const post = new THREE.Mesh(new THREE.CylinderGeometry(0.11, 0.12, 0.92, 16), std('#3A3C42', 0.6));
  post.position.set(b.x, 0.46, b.z); post.castShadow = true; sceneR.add(post);
  const band = new THREE.Mesh(new THREE.CylinderGeometry(0.115, 0.115, 0.08, 16), std('#F2F2EC', 0.4));
  band.position.set(b.x, 0.75, b.z); sceneR.add(band);
}
// café on the right
for (let k = 0; k < 3; k++) {
  const cx = -3.9, cz = 31.4 + k * 1.5;
  const top = new THREE.Mesh(new THREE.CylinderGeometry(0.38, 0.38, 0.04, 20), std('#EDEDE8', 0.5)); top.position.set(cx, 0.74, cz);
  const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.04, 0.72, 8), std('#2E2E33', 0.5)); leg.position.set(cx, 0.37, cz);
  const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.025, 0.025, 2.3, 8), std('#2E2E33', 0.5)); pole.position.set(cx, 1.15, cz);
  const umb = new THREE.Mesh(new THREE.ConeGeometry(1.05, 0.36, 18), std('#D9534F', 0.8)); umb.position.set(cx, 2.36, cz);
  for (const o of [top, leg, pole, umb]) { o.castShadow = true; sceneR.add(o); }
}
// planters
for (const p of L.planters) {
  const box = new THREE.Mesh(new THREE.BoxGeometry(0.9, 0.5, 0.9), std('#A8603E', 0.9)); box.position.set(p.x, 0.25, p.z);
  const bush = new THREE.Mesh(new THREE.SphereGeometry(0.48, 14, 10), std('#4C7A44', 1)); bush.position.set(p.x, 0.8, p.z);
  for (const o of [box, bush]) { o.castShadow = true; sceneR.add(o); }
}

// people
function personMesh(coat, trousers = '#2D323C', skin = '#C99878') {
  const g = new THREE.Group();
  const legs = new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.13, 0.8, 12), std(trousers, 0.9)); legs.position.y = 0.4;
  const torso = new THREE.Mesh(new THREE.CapsuleGeometry(0.2, 0.42, 4, 12), std(coat, 0.85)); torso.position.y = 1.12;
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.115, 14, 10), std(skin, 0.7)); head.position.y = 1.64;
  g.add(legs, torso, head);
  g.traverse(o => { if (o.isMesh) o.castShadow = true; });
  g.userData.parts = { legs, torso, head };
  return g;
}
const walkerR = personMesh('#DAD6CE', '#30343E');
{
  // white cane with a red tip, held in the right hand (the walker's right is -x)
  const pivot = new THREE.Group(); pivot.position.set(-0.27, 0.95, 0.12);
  const dir = new THREE.Vector3(0.1, -0.93, 0.92).normalize();
  const cane = new THREE.Group(); cane.quaternion.setFromUnitVectors(new THREE.Vector3(0, -1, 0), dir);
  const white = new THREE.Mesh(new THREE.CylinderGeometry(0.017, 0.017, 1.12, 8), std('#F7F7F2', 0.4)); white.position.y = -0.56;
  const red = new THREE.Mesh(new THREE.CylinderGeometry(0.018, 0.018, 0.2, 8), std('#D33A2C', 0.5)); red.position.y = -1.22;
  cane.add(white, red); pivot.add(cane); walkerR.add(pivot); walkerR.userData.cane = pivot;
  const phone = new THREE.Mesh(new THREE.BoxGeometry(0.075, 0.15, 0.014), std('#15151A', 0.3)); phone.position.set(0, 1.28, 0.215);
  const lens = new THREE.Mesh(new THREE.SphereGeometry(0.012, 8, 6), new THREE.MeshBasicMaterial({ color: HEX.accent })); lens.position.set(0.018, 1.33, 0.225);
  walkerR.add(phone, lens);
}
sceneR.add(walkerR);

const COATS = { 1: '#B4553A', 3: '#2F4A7A', 4: '#6F7A3E', 5: '#8C5A8E' };
const agentR = new Map();
for (const a of S.agents) {
  if (a.kind === 'persona') {
    const m = personMesh(COATS[a.id] || '#777777');
    if (a.seated) { m.userData.parts.legs.scale.y = 0.55; m.userData.parts.legs.position.y = 0.24; m.userData.parts.torso.position.y = 0.82; m.userData.parts.head.position.y = 1.34; }
    sceneR.add(m); agentR.set(a.id, m);
  } else if (a.kind === 'bici') {
    const g = new THREE.Group();
    const wheelGeo = new THREE.TorusGeometry(0.33, 0.035, 8, 26);
    const wm = std('#1D1E22', 0.7);
    const w1 = new THREE.Mesh(wheelGeo, wm), w2 = new THREE.Mesh(wheelGeo, wm);
    w1.rotation.y = Math.PI / 2; w2.rotation.y = Math.PI / 2; w1.position.set(0, 0.34, 0.55); w2.position.set(0, 0.34, -0.55);
    const frame = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.05, 1.05), std('#2C7BE5', 0.5)); frame.position.set(0, 0.62, 0); frame.rotation.x = 0.08;
    const rider = personMesh('#E8C547', '#2A2E36');
    rider.position.set(0, 0.25, -0.08); rider.userData.parts.torso.rotation.x = 0.42; rider.userData.parts.torso.position.z = 0.12; rider.userData.parts.head.position.z = 0.3; rider.userData.parts.legs.scale.y = 0.8;
    g.add(w1, w2, frame, rider); g.userData.wheels = [w1, w2];
    g.traverse(o => { if (o.isMesh) o.castShadow = true; });
    sceneR.add(g); agentR.set(a.id, g);
  }
}

// ================= RIGHT: the live splat map =================
const sceneS = new THREE.Scene();
sceneS.background = new THREE.Color(HEX.bg);
const camS = new THREE.PerspectiveCamera(50, 1, 0.1, 220);

const mapGeo = new THREE.BufferGeometry();
mapGeo.setAttribute('position', new THREE.BufferAttribute(M.pos, 3));
mapGeo.setAttribute('aCol', new THREE.BufferAttribute(M.col, 3));
mapGeo.setAttribute('aNoise', new THREE.BufferAttribute(M.noise, 3));
mapGeo.setAttribute('aSize', new THREE.BufferAttribute(M.size, 1));
const confAttr = new THREE.BufferAttribute(M.conf, 1); confAttr.setUsage(THREE.DynamicDrawUsage);
mapGeo.setAttribute('aConf', confAttr);
const mapMat = new THREE.ShaderMaterial({
  uniforms: { uScale: { value: 600 }, uFrozen: { value: 0 }, uWave: { value: -10 }, uWaveA: { value: 0 }, uWalker: { value: new THREE.Vector3() }, uWaveCol: { value: raw(HEX.accent) } },
  vertexShader: `
    uniform float uScale, uFrozen, uWave, uWaveA; uniform vec3 uWalker;
    attribute vec3 aCol; attribute vec3 aNoise; attribute float aSize; attribute float aConf;
    varying vec3 vCol; varying float vA; varying float vWave; varying float vC;
    void main() {
      float c = aConf; vC = c;
      vec3 p = position + aNoise * (1.0 - c) * 1.3;
      vec4 mv = modelViewMatrix * vec4(p, 1.0);
      gl_Position = projectionMatrix * mv;
      float sz = aSize * (1.0 + (1.0 - c) * 2.4);
      gl_PointSize = clamp(sz * uScale / max(0.1, -mv.z), 0.0, 46.0);
      float behind = smoothstep(-16.0, -2.0, p.z - uWalker.z);
      vA = c < 0.004 ? 0.0 : pow(c, 0.75) * mix(0.16, 1.0, behind);
      float d = distance(p.xz, uWalker.xz);
      vWave = uWaveA * exp(-pow((d - uWave) * 0.9, 2.0));
      vec3 grey = vec3(dot(aCol, vec3(0.3, 0.55, 0.15)));
      vCol = mix(aCol, grey * 0.75, uFrozen * 0.85);
    }`,
  fragmentShader: `
    uniform vec3 uWaveCol;
    varying vec3 vCol; varying float vA; varying float vWave; varying float vC;
    void main() {
      vec2 q = gl_PointCoord * 2.0 - 1.0; float r2 = dot(q, q); if (r2 > 1.0) discard;
      // Confirmed splats get crisp edges, ones still being gathered stay soft.
      float g = exp(-r2 * mix(3.0, 6.0, vC));
      vec3 col = vCol + uWaveCol * vWave * 0.9;
      float a = g * (vA * 0.9 + vWave * 0.3 * step(0.004, vA));
      if (a < 0.008) discard;
      gl_FragColor = vec4(col, a);
    }`,
  transparent: true, depthWrite: false,
});
const mapPts = new THREE.Points(mapGeo, mapMat); mapPts.frustumCulled = false; sceneS.add(mapPts);

// moving objects as splat clusters
const R = F.rng(5);
function shape(kind) {
  const pts = [];
  const cyl = (n, r0, r1, y0, y1, zOff = 0, tilt = 0) => { for (let i = 0; i < n * 2; i++) { const u = R(), a = R() * Math.PI * 2, y = y0 + (y1 - y0) * u, r = r0 + (r1 - r0) * u; pts.push([Math.cos(a) * r, y, Math.sin(a) * r + zOff + (y - y0) * tilt]); } };
  const ball = (n, cx, cy, cz, r) => { for (let i = 0; i < n * 2; i++) { let x = R() * 2 - 1, y = R() * 2 - 1, z = R() * 2 - 1; const k = Math.hypot(x, y, z) || 1; pts.push([cx + x / k * r, cy + y / k * r, cz + z / k * r]); } };
  if (kind === 'persona') { cyl(120, 0.15, 0.2, 0.05, 0.8); cyl(130, 0.21, 0.19, 0.8, 1.5); ball(50, 0, 1.64, 0, 0.12); }
  else if (kind === 'seated') { cyl(80, 0.15, 0.18, 0.05, 0.45); cyl(110, 0.2, 0.18, 0.5, 1.15); ball(40, 0, 1.34, 0, 0.12); }
  else if (kind === 'bici') {
    for (const zc of [0.55, -0.55]) for (let i = 0; i < 140; i++) { const a = R() * Math.PI * 2; pts.push([0, 0.34 + Math.sin(a) * 0.33, zc + Math.cos(a) * 0.33]); }
    for (let i = 0; i < 80; i++) pts.push([0, 0.6 + R() * 0.06, -0.5 + R() * 1.0]);
    cyl(70, 0.13, 0.16, 0.3, 0.95, -0.05); cyl(90, 0.19, 0.17, 0.95, 1.55, 0.05, 0.45); ball(36, 0, 1.72, 0.33, 0.11);
  }
  return pts;
}
function agentMat() {
  return new THREE.ShaderMaterial({
    uniforms: { uScale: { value: 600 }, uColor: { value: raw(HEX.sure) }, uAlpha: { value: 1 }, uJit: { value: 0 }, uTime: { value: 0 }, uRing: { value: 0 } },
    vertexShader: `
      uniform float uScale, uJit, uTime; attribute float aSeed;
      float h(float n) { return fract(sin(n) * 43758.5453); }
      void main() {
        float k = floor(uTime * 14.0);
        vec3 j = vec3(h(aSeed + k), h(aSeed * 1.7 + k * 1.3), h(aSeed * 2.3 + k * 0.7)) - 0.5;
        vec3 p = position + j * uJit * 2.0;
        vec4 mv = modelViewMatrix * vec4(p, 1.0);
        gl_Position = projectionMatrix * mv;
        gl_PointSize = clamp(0.12 * uScale / max(0.1, -mv.z), 0.0, 40.0);
      }`,
    fragmentShader: `
      uniform vec3 uColor; uniform float uAlpha, uRing;
      void main() {
        vec2 q = gl_PointCoord * 2.0 - 1.0; float r2 = dot(q, q); if (r2 > 1.0) discard;
        float g = exp(-r2 * 5.0);
        float ring = smoothstep(0.3, 0.55, r2) * (1.0 - smoothstep(0.75, 1.0, r2));
        float a = mix(g, ring * 1.3, uRing) * uAlpha;
        if (a < 0.01) discard;
        gl_FragColor = vec4(uColor, a);
      }`,
    transparent: true, depthWrite: false,
  });
}
const ringGeo = new THREE.RingGeometry(0.46, 0.56, 40);
const agentS = new Map();
for (const a of S.agents) {
  const v = { a: a.id, local: null, pts: null, mat: null, halo: null, yaw: 0 };
  if (a.kind !== 'ostacolo') {
    v.local = shape(a.seated ? 'seated' : a.kind);
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(v.local.length * 3), 3));
    const seeds = new Float32Array(v.local.length); for (let i = 0; i < seeds.length; i++) seeds[i] = R() * 100;
    geo.setAttribute('aSeed', new THREE.BufferAttribute(seeds, 1));
    v.mat = agentMat(); v.pts = new THREE.Points(geo, v.mat); v.pts.frustumCulled = false; sceneS.add(v.pts);
  }
  v.halo = new THREE.Mesh(ringGeo, new THREE.MeshBasicMaterial({ color: HEX.sure, transparent: true, opacity: 0.8, depthWrite: false, side: THREE.DoubleSide }));
  v.halo.rotation.x = -Math.PI / 2; sceneS.add(v.halo);
  agentS.set(a.id, v);
}

// the walker in the map: body, phone, sensing wedge, distance rings, walking corridor
const walkerS = new THREE.Group(); sceneS.add(walkerS);
const yawS = new THREE.Group(); walkerS.add(yawS);
const body = new THREE.Mesh(new THREE.CapsuleGeometry(0.16, 1.15, 4, 12), new THREE.MeshBasicMaterial({ color: '#FFFFFF', transparent: true, opacity: 0.55, depthWrite: false }));
body.position.y = 0.82; yawS.add(body);
const phoneDot = new THREE.Mesh(new THREE.SphereGeometry(0.07, 12, 8), new THREE.MeshBasicMaterial({ color: HEX.accent })); phoneDot.position.set(0, 1.3, 0.24); yawS.add(phoneDot);
const wedgeMat = new THREE.ShaderMaterial({
  uniforms: { uCol: { value: raw(HEX.accent) }, uA: { value: 0.2 } },
  vertexShader: `varying vec2 vP; void main() { vP = position.xy; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
  fragmentShader: `uniform vec3 uCol; uniform float uA; varying vec2 vP;
    void main() { float r = length(vP) / ${L.range.toFixed(1)}; float band = 0.55 + 0.45 * smoothstep(0.42, 0.5, abs(fract(r * 6.0) - 0.5));
      float a = uA * pow(1.0 - r, 1.5) * smoothstep(0.0, 0.03, r) * band; gl_FragColor = vec4(uCol, a); }`,
  transparent: true, depthWrite: false, side: THREE.DoubleSide,
});
const wedge = new THREE.Mesh(new THREE.CircleGeometry(L.range, 56, -Math.PI / 2 - L.mapFovHalf, 2 * L.mapFovHalf), wedgeMat);
wedge.rotation.x = -Math.PI / 2; wedge.position.y = 0.012; yawS.add(wedge);
const corrMat = new THREE.ShaderMaterial({
  uniforms: { uCol: { value: raw(HEX.accent) }, uA: { value: 0.3 } },
  vertexShader: `varying vec2 vUv; void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
  fragmentShader: `uniform vec3 uCol; uniform float uA; varying vec2 vUv;
    void main() { float edge = smoothstep(0.42, 0.5, abs(vUv.x - 0.5)); float a = uA * (0.25 + 0.75 * vUv.y) * (0.35 + 0.65 * edge); gl_FragColor = vec4(uCol, a); }`,
  transparent: true, depthWrite: false, side: THREE.DoubleSide,
});
const corridor = new THREE.Mesh(new THREE.PlaneGeometry(2 * L.corridorHalf, L.corridorLen), corrMat);
corridor.rotation.x = -Math.PI / 2; corridor.position.set(0, 0.02, 0.3 + L.corridorLen / 2); yawS.add(corridor);
const rings = [2, 5].map(r => { const m = new THREE.Mesh(new THREE.RingGeometry(r - 0.035, r + 0.035, 96), new THREE.MeshBasicMaterial({ color: HEX.accent, transparent: true, opacity: 0.4, depthWrite: false, side: THREE.DoubleSide })); m.rotation.x = -Math.PI / 2; m.position.y = 0.016; walkerS.add(m); return m; });
// the bike's predicted path when it's heading into the walker's line
const dangerLine = new THREE.Line(new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(), new THREE.Vector3()]), new THREE.LineBasicMaterial({ color: HEX.danger, transparent: true, opacity: 0.95 }));
dangerLine.frustumCulled = false; sceneS.add(dangerLine);
const crossMark = new THREE.Mesh(new THREE.RingGeometry(0.28, 0.38, 32), new THREE.MeshBasicMaterial({ color: HEX.danger, transparent: true, depthWrite: false, side: THREE.DoubleSide }));
crossMark.rotation.x = -Math.PI / 2; sceneS.add(crossMark);

// ---------------- labels over the map ----------------
const labelsEl = $('labels');
const mkLabel = () => { const el = document.createElement('span'); el.className = 'lab'; el.hidden = true; labelsEl.appendChild(el); return el; };
const agentLabel = new Map(); for (const a of S.agents) agentLabel.set(a.id, mkLabel());
const ringLabels = [2, 5].map(r => { const el = mkLabel(); el.dataset.s = 'ring'; el.textContent = r + ' m'; return el; });
const v3 = new THREE.Vector3();
function project(x, y, z) {
  v3.set(x, y, z).project(camS);
  if (v3.z > 1 || Math.abs(v3.x) > 1.05 || Math.abs(v3.y) > 1.05) return null;
  return [(v3.x * 0.5 + 0.5) * cSplat.clientWidth, (-v3.y * 0.5 + 0.5) * cSplat.clientHeight];
}
// Labels never overlap: the most important one keeps its place, the others move up or step aside.
function layoutLabels(queue) {
  queue.sort((p, q) => q.prio - p.prio || p.d - q.d);
  const placed = [], W = cSplat.clientWidth;
  for (const q of queue) {
    if (!q.p) { q.el.hidden = true; continue; }
    q.el.hidden = false;
    const w = q.el.offsetWidth, h = q.el.offsetHeight;
    const x0 = Math.min(Math.max(4, q.p[0] - w / 2), Math.max(4, W - w - 4));
    let ok = false;
    for (const dy of [0, -(h + 4), -2 * (h + 4), h + 4]) {
      const r = [x0, q.p[1] - h + dy, x0 + w, q.p[1] + dy];
      if (placed.every(o => r[2] < o[0] || r[0] > o[2] || r[3] < o[1] || r[1] > o[3])) {
        placed.push(r); q.el.style.transform = `translate(${r[0].toFixed(1)}px, ${r[1].toFixed(1)}px)`; ok = true; break;
      }
    }
    if (!ok) q.el.hidden = true;
  }
}

// ---------------- sound, speech, haptics ----------------
let AC = null, master = null;
function initAudio() {
  if (AC) { if (AC.state === 'suspended') AC.resume(); return; }
  try {
    AC = new (window.AudioContext || window.webkitAudioContext)();
    master = AC.createGain(); master.gain.value = 0.9;
    const comp = AC.createDynamicsCompressor(); master.connect(comp); comp.connect(AC.destination);
  } catch (e) { AC = null; return; }
  loadVoice();
}
function tone(f, type, at, a, d, peak, f2, lp) {
  const o = AC.createOscillator(), g = AC.createGain();
  o.type = type; o.frequency.setValueAtTime(f, at);
  if (f2) o.frequency.exponentialRampToValueAtTime(f2, at + a + d);
  g.gain.setValueAtTime(0.0001, at); g.gain.exponentialRampToValueAtTime(peak, at + a); g.gain.exponentialRampToValueAtTime(0.0001, at + a + d);
  let node = o;
  if (lp) { const fl = AC.createBiquadFilter(); fl.type = 'lowpass'; fl.frequency.value = lp; o.connect(fl); node = fl; }
  node.connect(g); g.connect(master); o.start(at); o.stop(at + a + d + 0.05);
}
const SFX = {
  tick: (t) => tone(2200, 'sine', t, 0.002, 0.035, 0.07),
  knock: (t) => { tone(160, 'sine', t, 0.004, 0.2, 0.75, 85); tone(320, 'triangle', t, 0.002, 0.06, 0.2); },
  flutter: (t) => { for (let i = 0; i < 3; i++) tone(1300, 'sine', t + i * 0.075, 0.003, 0.045, 0.18); },
  fast: (t) => { for (let i = 0; i < 2; i++) tone(940, 'square', t + i * 0.22, 0.005, 0.15, 0.25, null, 3200); },
  long: (t) => { for (let i = 0; i < 2; i++) tone(110, 'sawtooth', t + i * 0.62, 0.02, 0.45, 0.36, null, 750); },
  rising: (t) => { tone(440, 'triangle', t, 0.004, 0.13, 0.38); tone(660, 'triangle', t + 0.17, 0.004, 0.15, 0.38); },
  prox: (t) => tone(1500, 'sine', t, 0.003, 0.07, 0.22),
};
const VIB = { knock: [60], flutter: [25, 45, 25, 45, 25], fast: [140, 90, 140], long: [450, 170, 450], rising: [50, 70, 90], prox: [30] };
function sfx(name) {
  if (!audioOn || !AC || !SFX[name]) return;
  try { SFX[name](AC.currentTime + 0.01); } catch (e) { /* audio is optional */ }
  try { if (navigator.vibrate && VIB[name]) navigator.vibrate(VIB[name]); } catch (e) { /* not every device vibrates */ }
}
// Every spoken line is a recording of a natural voice in each language (made by voice.py, embedded by build.py
// as window.FVVoice). It plays through Web Audio once the line's cue sound ends, trimmed to the speech itself.
// A line with no recording, or a browser that can't decode one, falls back to the browser's own speech.
const CUE_LEN = { knock: 0.2, flutter: 0.2, fast: 0.38, long: 1.1, rising: 0.32 };
const clips = new Map();
const voiceSrc = new Set();
let voiceGen = 0, voiceEnd = 0;
// Skips the silence around the speech, keeping a few milliseconds so the first and last sounds aren't clipped.
function trimmed(buf) {
  const d = buf.getChannelData(0); let i = 0, j = d.length - 1;
  while (i < j && Math.abs(d[i]) < 0.01) i++;
  while (j > i && Math.abs(d[j]) < 0.01) j--;
  const from = Math.max(0, i / buf.sampleRate - 0.02), to = Math.min(buf.duration, j / buf.sampleRate + 0.08);
  return { buf, from, len: to - from };
}
function loadVoice() {
  for (const [text, b64] of Object.values(window.FVVoice || {}).flatMap(Object.entries)) {
    try {
      const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
      const clip = AC.decodeAudioData(bytes.buffer).then(trimmed);
      clip.catch(() => clips.delete(text));
      clips.set(text, clip);
    } catch (e) { /* the browser's speech says this line */ }
  }
}
function speak(text, priority, cue) {
  if (!audioOn) return;
  const clip = AC && clips.get(text);
  if (!clip) { speakBrowser(text, priority); return; }
  if (priority) hush();
  const gen = voiceGen, at = AC.currentTime + (CUE_LEN[cue] || 0) + 0.01;
  clip.then((c) => {
    if (gen !== voiceGen || !audioOn) return; // hushed while the clip was decoding
    const src = AC.createBufferSource(); src.buffer = c.buf; src.connect(master);
    // Like speechSynthesis, a line that isn't urgent waits for the one already speaking.
    const start = Math.max(at, AC.currentTime, voiceEnd);
    src.start(start, c.from, c.len); voiceEnd = start + c.len;
    voiceSrc.add(src); src.onended = () => voiceSrc.delete(src);
  }, () => speakBrowser(text, priority));
}
// The browser's best voice for each language, preferring its natural-sounding ones.
const browserVoice = {};
function pickVoices() {
  try {
    const all = speechSynthesis.getVoices();
    for (const [code, text] of Object.entries(window.FVText.TEXT)) {
      const vs = all.filter(v => v.lang.toLowerCase().startsWith(code));
      browserVoice[code] = vs.find(v => /natural|premium|enhanced|google/i.test(v.name)) || vs.find(v => v.lang.replace('_', '-') === text.speech) || vs[0] || null;
    }
  } catch (e) { /* the browser picks one */ }
}
if ('speechSynthesis' in window) { pickVoices(); try { speechSynthesis.addEventListener('voiceschanged', pickVoices); } catch (e) { /* older browsers */ } }
function speakBrowser(text, priority) {
  if (!('speechSynthesis' in window)) return;
  try {
    if (priority) speechSynthesis.cancel();
    const u = new SpeechSynthesisUtterance(text); u.lang = T.speech; if (browserVoice[lang]) u.voice = browserVoice[lang]; u.rate = 1.08;
    speechSynthesis.speak(u);
  } catch (e) { /* captions still show the line */ }
}
function hush() {
  voiceGen++; voiceEnd = 0;
  for (const src of voiceSrc) try { src.stop(); } catch (e) { /* already stopped */ }
  voiceSrc.clear();
  try { if ('speechSynthesis' in window) speechSynthesis.cancel(); } catch (e) { /* nothing to stop */ }
}

// The subtitles keep the spoken event and the cue, not their text, so a language change can redraw them.
const captionEl = $('caption'), cueEl = $('cue');
let shownLine = null, shownCue = null;
function setCaption(ev) { shownLine = ev; captionEl.textContent = F.lineText(lang, ev || { line: 'start' }); }
function setCue(name) {
  shownCue = name;
  const cue = T.cue[name];
  cueEl.textContent = cue ? '[' + cue + ']' : '';
  cueEl.parentElement.hidden = !cue;
}

function handleEvents() {
  for (const e of S.events) {
    if (e.type === 'tick') { sfx('tick'); waveT = S.t; }
    else if (e.type === 'haptic') { sfx(e.pattern); setCue(e.pattern); }
    else if (e.type === 'prox') { sfx('prox'); setCue('prox'); }
    else if (e.type === 'say') { setCaption(e); setCue(e.sfx); if (e.sfx) sfx(e.sfx); speak(F.lineText(lang, e), e.priority, e.sfx); }
  }
  S.events.length = 0;
}

// ---------------- transport ----------------
function jumpTo(t, play) {
  hush();
  S = F.makeSim(); M.conf.fill(0);
  let last = null;
  while (S.t < t - 1e-6) {
    const h = Math.min(1 / 20, t - S.t);
    F.step(S, h); F.updateMap(M, S, h);
    for (const e of S.events) if (e.type === 'say') last = e;
    S.events.length = 0;
  }
  confAttr.needsUpdate = true; snap = true; waveT = -99;
  setCaption(last);
  setCue(last ? last.sfx : null);
  playing = !!play; syncButtons();
}
function syncButtons() {
  const play = $('btnPlay'), audio = $('btnAudio');
  play.innerHTML = playing ? ICON.pause : ICON.play;
  play.setAttribute('aria-label', playing ? T.pause : T.play);
  audio.innerHTML = audioOn ? ICON.audioOn : ICON.audioOff;
  audio.setAttribute('aria-label', audioOn ? T.audioOn : T.audioOff);
}
function closeStart() { $('start').hidden = true; }
// Switches every word on the page, and the voice, to the other language. A line already speaking stops.
function setLang(next) {
  if (next === lang || !window.FVText.TEXT[next]) return;
  lang = next; T = window.FVText.TEXT[lang];
  window.FVText.apply(lang); window.FVText.save(lang);
  hush(); setCaption(shownLine); setCue(shownCue); syncButtons();
  $('status').dataset.state = ''; shownSec = -1; // the next frame redraws the status and the slider's spoken value
}
for (const b of document.querySelectorAll('[data-lang]')) b.addEventListener('click', () => setLang(b.dataset.lang));

// Scrubber: one segment per checkpoint, like chapters in Apple's player. Click or drag to jump, arrow keys go
// between checkpoints. The jump happens on release, because each one replays the scene from 0.
const scrubEl = $('scrub'), tipEl = $('tip');
const CH = F.CHAPTERS.map((c, i, all) => ({ ...c, end: i + 1 < all.length ? all[i + 1].t : L.T }));
const segs = CH.map((c) => {
  const el = document.createElement('span'); el.className = 'seg'; el.style.flex = `${c.end - c.t} 1 0`;
  const fill = document.createElement('i'); el.appendChild(fill); $('track').appendChild(el);
  return { el, fill };
});
const clockText = (s) => Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
const chapterAt = (t) => { let i = 0; CH.forEach((c, k) => { if (t >= c.t - 0.01) i = k; }); return i; };
let scrubbing = false, shownSec = -1;
scrubEl.setAttribute('aria-valuemin', '0');
scrubEl.setAttribute('aria-valuemax', String(L.T));
function paint(t) { CH.forEach((c, i) => { segs[i].fill.style.width = (Math.min(1, Math.max(0, (t - c.t) / (c.end - c.t))) * 100).toFixed(2) + '%'; }); }
// A click in a gap, or in the first few pixels of a segment, lands exactly on that checkpoint.
function timeAt(x) {
  for (let i = 0; i < CH.length; i++) {
    const r = segs[i].el.getBoundingClientRect();
    if (x < r.left + 8) return CH[i].t;
    if (x <= r.right) return CH[i].t + (x - r.left) / r.width * (CH[i].end - CH[i].t);
  }
  return L.T - 0.1;
}
function showTip(x, t) {
  const r = scrubEl.getBoundingClientRect();
  tipEl.textContent = CH[chapterAt(t)].name[lang] + ' · ' + clockText(Math.floor(t));
  tipEl.hidden = false;
  tipEl.style.left = Math.min(Math.max(0, x - r.left - tipEl.offsetWidth / 2), r.width - tipEl.offsetWidth) + 'px';
}
scrubEl.addEventListener('pointerdown', (e) => { scrubbing = true; scrubEl.setPointerCapture(e.pointerId); const t = timeAt(e.clientX); paint(t); showTip(e.clientX, t); });
scrubEl.addEventListener('pointermove', (e) => { const t = timeAt(e.clientX); showTip(e.clientX, t); if (scrubbing) paint(t); });
scrubEl.addEventListener('pointerleave', () => { if (!scrubbing) tipEl.hidden = true; });
scrubEl.addEventListener('pointerup', (e) => { if (!scrubbing) return; scrubbing = false; tipEl.hidden = true; closeStart(); jumpTo(timeAt(e.clientX), playing); });
scrubEl.addEventListener('pointercancel', () => { scrubbing = false; tipEl.hidden = true; });
window.addEventListener('keydown', (e) => {
  const dir = { ArrowLeft: -1, ArrowRight: 1 }[e.key]; if (!dir) return;
  e.preventDefault();
  let i = chapterAt(S.t);
  // Like Apple's players, back first returns to the start of the current checkpoint, then to the previous one.
  if (dir > 0) i = Math.min(CH.length - 1, i + 1);
  else if (S.t - CH[i].t < 2) i = Math.max(0, i - 1);
  closeStart(); jumpTo(CH[i].t, playing);
});
$('btnCaptions').addEventListener('click', (e) => {
  const on = e.currentTarget.getAttribute('aria-pressed') !== 'true';
  e.currentTarget.setAttribute('aria-pressed', String(on));
  $('subtitles').hidden = !on;
});
$('goAudio').addEventListener('click', () => { initAudio(); audioOn = true; closeStart(); jumpTo(0, true); });
$('goSilent').addEventListener('click', () => { audioOn = false; closeStart(); jumpTo(0, true); });
function togglePlay() { closeStart(); if (S.t >= L.T - 0.05) jumpTo(0, true); else { playing = !playing; if (!playing) hush(); syncButtons(); } }
$('btnPlay').addEventListener('click', togglePlay);
// Space plays and pauses from anywhere, like Apple's players, so it never activates the focused button instead.
window.addEventListener('keydown', (e) => { if (e.code !== 'Space') return; e.preventDefault(); if (!e.repeat) togglePlay(); }, true);
window.addEventListener('keyup', (e) => { if (e.code === 'Space') e.preventDefault(); }, true);
$('btnAudio').addEventListener('click', () => { audioOn = !audioOn; if (audioOn) initAudio(); else hush(); syncButtons(); });

// ---------------- sizing ----------------
function resize() {
  for (const [r, cam, cv] of [[rR, camR, cReal], [rS, camS, cSplat]]) {
    const w = cv.clientWidth, h = cv.clientHeight; if (!w || !h) continue;
    r.setSize(w, h, false); cam.aspect = w / h; cam.updateProjectionMatrix();
  }
  const s = (cSplat.clientHeight * rS.getPixelRatio()) / (2 * Math.tan(THREE.MathUtils.degToRad(camS.fov) / 2));
  mapMat.uniforms.uScale.value = s; for (const v of agentS.values()) if (v.mat) v.mat.uniforms.uScale.value = s;
}
new ResizeObserver(resize).observe(cReal); new ResizeObserver(resize).observe(cSplat);

// ---------------- per-frame visuals ----------------
const lookR = new THREE.Vector3(), lookS = new THREE.Vector3();
function follow(cam, look, back, up, ahead, lookY, k) {
  const w = S.w;
  const tx = w.x - w.hx * back, tz = w.z - w.hz * back, lx = w.x + w.hx * ahead, lz = w.z + w.hz * ahead;
  if (snap) { cam.position.set(tx, up, tz); look.set(lx, lookY, lz); }
  else { cam.position.x += (tx - cam.position.x) * k; cam.position.y += (up - cam.position.y) * k; cam.position.z += (tz - cam.position.z) * k; look.x += (lx - look.x) * k; look.y += (lookY - look.y) * k; look.z += (lz - look.z) * k; }
  cam.lookAt(look);
}
let frozenK = 0, clock = 0;

function updateVisuals(dt) {
  clock += dt;
  const w = S.w, yaw = Math.atan2(w.hx, w.hz);
  // walker, left
  walkerR.position.set(w.x, Math.abs(Math.sin(w.phase * Math.PI)) * 0.035, w.z); walkerR.rotation.y = yaw;
  walkerR.userData.cane.rotation.y = Math.sin(w.phase * Math.PI * 0.5) * 0.38;
  // darkness inside the covered passage
  const dk = smooth(L.passage.z0, L.passage.z0 + 1.2, w.z) * (1 - smooth(L.passage.z1 - 0.4, L.passage.z1 + 0.6, w.z));
  hemi.intensity = 1.2 * (1 - 0.72 * dk); sun.intensity = 2.5 * (1 - 0.55 * dk);
  $('dim').style.opacity = (dk * 0.8).toFixed(3);
  sun.position.set(w.x + 14, 26, w.z + 6); sun.target.position.set(w.x, 0, w.z + 8);
  // agents, left
  for (const a of S.agents) {
    const m = agentR.get(a.id); if (!m) continue;
    m.position.set(a.x, 0, a.z);
    const sp = Math.hypot(a.vx, a.vz);
    if (sp > 0.1) m.rotation.y = Math.atan2(a.vx, a.vz);
    if (a.kind === 'persona' && !a.seated) m.position.y = Math.abs(Math.sin(clock * 5.2 * Math.min(1, sp))) * 0.03;
    if (a.kind === 'bici') for (const wh of m.userData.wheels) wh.rotation.x += dt * sp / 0.33;
  }
  follow(camR, lookR, 4.6, 2.35, 6, 1.1, 1 - Math.exp(-dt * 3.2));

  // map, right
  frozenK += ((S.reliable ? 0 : 1) - frozenK) * Math.min(1, dt * 5);
  mapMat.uniforms.uFrozen.value = frozenK;
  mapMat.uniforms.uWalker.value.set(w.x, 0, w.z);
  const age = S.t - waveT;
  mapMat.uniforms.uWave.value = age * 15; mapMat.uniforms.uWaveA.value = S.reliable ? Math.max(0, 1 - age / 1.7) : 0;
  confAttr.needsUpdate = true;
  walkerS.position.set(w.x, 0, w.z); yawS.rotation.y = yaw;
  wedgeMat.uniforms.uCol.value.copy(raw(S.reliable ? HEX.accent : HEX.warn)); wedgeMat.uniforms.uA.value = S.reliable ? 0.2 : 0.07;

  let danger = false, dangerBike = null;
  const queue = [];
  for (const a of S.agents) {
    const v = agentS.get(a.id), lab = agentLabel.get(a.id);
    const showable = a.state === 'maybe' || a.state === 'sure' || a.state === 'hidden';
    const isDanger = a.danger && !a.frozen;
    if (isDanger) danger = true;
    if (isDanger && a.fast) dangerBike = a;
    const hx = a.state === 'hidden' ? a.gx : a.x, hz = a.state === 'hidden' ? a.gz : a.z;
    let col = HEX.sure, alpha = 0.95, jit = 0.012, ringMode = 0, haloOp = 0.8;
    if (a.frozen) { col = HEX.grey; alpha = 0.55; jit = 0; haloOp = 0.4; }
    else if (isDanger) { col = HEX.danger; alpha = 1; jit = 0.01; haloOp = 0.6 + 0.4 * Math.sin(clock * 14); }
    else if (a.state === 'maybe') { col = HEX.maybe; alpha = 0.3 + a.conf * 0.6; jit = 0.11; haloOp = 0.55; }
    else if (a.state === 'hidden') { col = HEX.sure; alpha = 0.5 + 0.2 * Math.sin(clock * 6); jit = 0.03; ringMode = 1; haloOp = 0.35 + 0.3 * Math.sin(clock * 6); }
    if (v.pts) {
      v.pts.visible = showable;
      if (showable) {
        const sp = Math.hypot(a.vx, a.vz); if (sp > 0.1 && a.state !== 'hidden') v.yaw = Math.atan2(a.vx, a.vz);
        const c = Math.cos(v.yaw), s = Math.sin(v.yaw), arr = v.pts.geometry.attributes.position.array;
        for (let i = 0; i < v.local.length; i++) { const p = v.local[i]; arr[i * 3] = hx + p[0] * c + p[2] * s; arr[i * 3 + 1] = p[1]; arr[i * 3 + 2] = hz - p[0] * s + p[2] * c; }
        v.pts.geometry.attributes.position.needsUpdate = true;
        v.mat.uniforms.uColor.value.copy(raw(col)); v.mat.uniforms.uAlpha.value = alpha; v.mat.uniforms.uJit.value = jit; v.mat.uniforms.uRing.value = ringMode; v.mat.uniforms.uTime.value = clock;
      }
    }
    v.halo.visible = showable;
    if (showable) { v.halo.position.set(hx, 0.03, hz); v.halo.material.color.set(col); v.halo.material.opacity = Math.max(0.1, haloOp); const sc = a.kind === 'ostacolo' ? 0.6 : (a.kind === 'bici' ? 1.9 : 1); v.halo.scale.setScalar(sc); }
    // label
    if (!showable) { lab.hidden = true; continue; }
    const W = T.tag, name = a.name[lang] + ' ' + a.id;
    let text, st;
    if (a.frozen) { text = name + ' · ' + W.memory; st = 'frozen'; }
    else if (isDanger && a.fast) { text = name + ' · ' + W.fast; st = 'danger'; }
    else if (a.state === 'hidden') { text = name + ' · ' + W.hidden(a.g, fmt(a.hiddenT)); st = 'hidden'; }
    else if (a.state === 'maybe' && a.d > 18) { text = W.far + ' ' + a.id + ' · ' + W.maybe + ' · ' + Math.round(a.d) + ' m'; st = 'maybe'; }
    else { text = name + ' · ' + (a.state === 'sure' ? W.sure(a.g) : W.maybe) + ' · ' + fmt(a.d) + ' m' + (a.inPath ? ' · ' + W.ahead : ''); st = isDanger ? 'danger' : a.state; }
    if (lab.textContent !== text) lab.textContent = text;
    lab.dataset.s = st;
    const prio = st === 'danger' ? 4 : st === 'hidden' ? 3 : a.inPath ? 2.5 : st === 'sure' ? 2 : 1;
    queue.push({ el: lab, p: project(hx, a.kind === 'ostacolo' ? 1.15 : (a.seated ? 1.6 : 1.95), hz), prio, d: a.d });
  }
  // corridor + danger line
  const unknown = !S.reliable;
  corrMat.uniforms.uCol.value.copy(raw(unknown ? HEX.warn : danger ? HEX.danger : HEX.accent));
  corrMat.uniforms.uA.value = unknown ? 0.18 : danger ? 0.42 + 0.18 * Math.sin(clock * 12) : 0.28;
  dangerLine.visible = crossMark.visible = !!dangerBike;
  if (dangerBike) {
    const tc = (w.x - dangerBike.x) / (Math.abs(dangerBike.vx) > 1e-3 ? dangerBike.vx : 1e-3);
    const cx = dangerBike.x + dangerBike.vx * tc, cz = dangerBike.z + dangerBike.vz * tc;
    const pos = dangerLine.geometry.attributes.position.array;
    pos[0] = dangerBike.x; pos[1] = 0.35; pos[2] = dangerBike.z; pos[3] = cx + dangerBike.vx * 0.3; pos[4] = 0.35; pos[5] = cz + dangerBike.vz * 0.3;
    dangerLine.geometry.attributes.position.needsUpdate = true;
    crossMark.position.set(cx, 0.04, cz); crossMark.material.opacity = 0.6 + 0.4 * Math.sin(clock * 14);
  }
  // ring labels on the walker's right
  const rx = -w.hz, rz = w.hx;
  [2, 5].forEach((r, i) => queue.push({ el: ringLabels[i], p: project(w.x + rx * r, 0.05, w.z + rz * r), prio: 0, d: r }));
  layoutLabels(queue);
  follow(camS, lookS, 8.4, 7.2, 10.5, 0, 1 - Math.exp(-dt * 3.0));
  snap = false;

  // header and rail
  const st = $('status');
  const want = S.reliable ? 'ok' : 'bad';
  if (st.dataset.state !== want) { st.dataset.state = want; $('statusText').textContent = S.reliable ? T.statusOk : T.statusBad; }
  $('hatch').style.opacity = S.reliable ? '0' : '1';
  if (!scrubbing) paint(S.t);
  const sec = Math.floor(S.t);
  if (sec !== shownSec) { shownSec = sec; scrubEl.setAttribute('aria-valuenow', String(sec)); scrubEl.setAttribute('aria-valuetext', clockText(sec) + ', ' + CH[chapterAt(S.t)].name[lang]); }
}

// ---------------- main loop ----------------
let last = performance.now();
function frame(now) {
  const dt = Math.min(0.05, Math.max(0, (now - last) / 1000)); last = now;
  if (playing) {
    let rem = dt;
    while (rem > 1e-6) { const h = Math.min(rem, 1 / 60); F.step(S, h); F.updateMap(M, S, h); rem -= h; }
    handleEvents();
    if (S.t >= L.T) jumpTo(0, true);
  }
  updateVisuals(playing ? dt : 0);
  rR.render(sceneR, camR); rS.render(sceneS, camS);
  requestAnimationFrame(frame);
}
resize();
jumpTo(14.4, false);   // a still frame worth looking at: the person hidden behind the van
updateVisuals(0);
requestAnimationFrame(frame);
