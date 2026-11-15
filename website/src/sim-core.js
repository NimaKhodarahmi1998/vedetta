/* FieldVision concept: simulation core. Pure logic, no DOM, no three.js.
   World units are metres. The walker walks along +z; their LEFT is +x, their RIGHT is -x. */
(function (root) {
  'use strict';
  const D2R = Math.PI / 180;

  const L = {
    half: 5.2, zMin: -8, zMax: 74,
    van: { x0: 1.3, x1: 3.3, z0: 19.0, z1: 23.0, h: 2.5 },
    side: { z0: 25.5, z1: 29.5, len: 14 },          // side street opening on the RIGHT (x = -half)
    passage: { z0: 34, z1: 42, roof: 7.0 },          // covered passage: dark inside
    bollards: [{ x: -0.55, z: 50 }, { x: 1.75, z: 50 }, { x: -2.85, z: 50 }],
    cafe: { x0: -4.8, x1: -3.0, z0: 31.0, z1: 35.0 },
    planters: [{ x: 4.5, z: 7 }, { x: 4.5, z: 27 }, { x: 4.5, z: 57 }, { x: -4.5, z: 12 }],
    phoneH: 1.3, fovHalf: 32 * D2R, mapFovHalf: 37 * D2R, range: 30,
    corridorHalf: 0.75, corridorLen: 6.0,
    T: 61,
  };

  // Keyframes [t, x, z]. Linear between keys.
  const WALKER = [
    [0, -0.6, 0], [3.0, -0.6, 0],                  // stands: start line
    [9.4, -0.6, 8.0],                              // walks
    [10.9, -0.6, 8.4],                             // slows: person in the path
    [22.4, -0.6, 21.5],                            // walks on
    [24.6, -0.6, 21.65],                           // stops: the bike
    [35.4, -0.6, 34.0],                            // walks to the covered passage
    [44.8, -0.6, 42.0],                            // slow inside (dark)
    [50.6, -0.6, 47.3],                            // careful: something ahead
    [52.5, 0.6, 49.5],                             // steps left around the bollard
    [54.6, 0.6, 52.0],
    [58.2, -0.3, 55.8],
    [61.0, -0.3, 58.6],
  ];

  const AGENTS = [
    { id: 1, kind: 'persona', label: 'Persona', g: 'a',
      path: [[0, -0.35, 14.0], [9.8, -0.35, 14.0], [12.2, 2.4, 17.6], [13.8, 4.1, 20.2], [15.2, 4.1, 22.6], [16.9, 1.0, 25.0], [17.9, 0.8, 26.5], [23.5, 0.8, 33.5], [32.7, 0.8, 45], [56, 0.8, 74], [61, 0.8, 74]] },
    { id: 2, kind: 'bici', label: 'Bici', g: 'a', fast: true,
      path: [[0, -16, 27.5], [19.97, -16, 27.5], [23.97, 6.5, 27.5], [61, 6.5, 27.5]] },
    { id: 3, kind: 'persona', label: 'Persona', g: 'a', path: [[0, -2.9, 47], [39, -2.9, 0], [61, -2.9, -26]] },
    { id: 4, kind: 'persona', label: 'Persona', g: 'a', path: [[0, 4.2, 66], [61, 4.2, 6]] },
    { id: 5, kind: 'persona', label: 'Persona', g: 'a', seated: true, path: [[0, -4.1, 32.6], [61, -4.1, 32.6]] },
    { id: 6, kind: 'ostacolo', label: 'Ostacolo', g: 'o', fixed: true, path: [[0, -0.55, 50], [61, -0.55, 50]] },
  ];

  // Every spoken line. a is the object, side is 'sinistra' or 'destra'.
  const VOICE = {
    start: 'Guida attiva. Vedo solo davanti.',
    dark: 'Guida non affidabile: troppo buio',
    light: 'Guida di nuovo attiva',
    ahead: (a) => a.label + ' davanti',
    hidden: (a, side) => a.label + ' nascost' + a.g + ', a ' + side,
    back: (a, side) => a.label + ' riapparsa, a ' + side,
    lost: (a) => a.label + ' pers' + a.g + ' di vista',
    fast: (a, side) => 'Veloce a ' + side + '!',
  };

  // Timeline checkpoints, one per case the scene shows.
  const CHAPTERS = [
    { t: 0, name: 'Avvio' }, { t: 7.5, name: 'Persona davanti' }, { t: 12.5, name: 'Persona nascosta' },
    { t: 20.2, name: 'Bici veloce' }, { t: 33.6, name: 'Troppo buio' }, { t: 45.2, name: 'Ostacolo' },
  ];

  function samplePath(path, t) {
    if (t <= path[0][0]) return { x: path[0][1], z: path[0][2] };
    for (let i = 1; i < path.length; i++) {
      const a = path[i - 1], b = path[i];
      if (t <= b[0]) {
        const u = (t - a[0]) / Math.max(1e-6, b[0] - a[0]);
        return { x: a[1] + (b[1] - a[1]) * u, z: a[2] + (b[2] - a[2]) * u };
      }
    }
    const e = path[path.length - 1];
    return { x: e[1], z: e[2] };
  }
  function velocity(path, t) {
    const h = 0.05, a = samplePath(path, t - h), b = samplePath(path, t + h);
    return { x: (b.x - a.x) / (2 * h), z: (b.z - a.z) / (2 * h) };
  }

  function rng(seed) {
    let s = seed | 0;
    return function () {
      s = (s + 0x6D2B79F5) | 0;
      let t = Math.imul(s ^ (s >>> 15), 1 | s);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  const inPassage = (x, z) => z > L.passage.z0 && z < L.passage.z1 && x > -L.half && x < L.half;

  // 2D segment vs box (Liang–Barsky). True if the segment passes through the box.
  function segHitsBox(ax, az, bx, bz, b) {
    let t0 = 0, t1 = 1;
    const dx = bx - ax, dz = bz - az;
    const p = [-dx, dx, -dz, dz], q = [ax - b.x0, b.x1 - ax, az - b.z0, b.z1 - az];
    for (let i = 0; i < 4; i++) {
      if (Math.abs(p[i]) < 1e-9) { if (q[i] < 0) return false; continue; }
      const r = q[i] / p[i];
      if (p[i] < 0) { if (r > t1) return false; if (r > t0) t0 = r; }
      else { if (r < t0) return false; if (r < t1) t1 = r; }
    }
    return t0 < t1 && t1 > 0.03 && t0 < 0.97;
  }

  // Beyond a facade line, a target is visible only through the side-street opening.
  function facadeBlocks(w, x, z) {
    if (Math.abs(x) <= L.half + 0.01) return false;
    const sx = x > 0 ? L.half : -L.half;
    const u = (sx - w.x) / (x - w.x);
    const zc = w.z + (z - w.z) * u;
    if (x < 0 && zc > L.side.z0 && zc < L.side.z1) return false;
    return true;
  }

  function sight(w, x, z) {
    const dx = x - w.x, dz = z - w.z, d = Math.hypot(dx, dz) || 1e-6;
    const ux = dx / d, uz = dz / d;
    const ang = Math.atan2(w.hz * ux - w.hx * uz, w.hx * ux + w.hz * uz); // + = left
    const inFov = Math.abs(ang) <= L.fovHalf && d <= L.range && d > 0.4;
    const wall = facadeBlocks(w, x, z);
    const dark = inPassage(x, z);
    const occl = segHitsBox(w.x, w.z, x, z, L.van);
    return { d, ang, inFov, wall, dark, occl, visible: inFov && !wall && !dark && !occl };
  }

  // ---------- Static map: points on every surface, sorted by z ----------
  function buildMap(seed) {
    const R = rng(seed || 11);
    const P = [];
    // More, smaller splats than the surfaces strictly need: the map reads sharper while covering the same area.
    const DENSITY = 2.5, N = (k) => Math.round(k * DENSITY), SHRINK = 1 / Math.sqrt(DENSITY);
    function add(x, y, z, c, size, dark) {
      let u = R() * 2 - 1, v = R() * 2 - 1, k = R() * 2 - 1;
      const n = Math.hypot(u, v, k) || 1, m = 0.3 + R() * 1.0;
      P.push([x, y, z, c[0], c[1], c[2], size * SHRINK, dark ? 1 : 0, (u / n) * m, (v / n) * m * 0.6, (k / n) * m]);
    }
    const jc = (c, k) => [c[0] * (1 - k / 2 + R() * k), c[1] * (1 - k / 2 + R() * k), c[2] * (1 - k / 2 + R() * k)];
    const stone = [0.50, 0.48, 0.45];
    // street paving
    for (let i = 0; i < N(16000); i++) {
      const x = -L.half + R() * 2 * L.half, z = L.zMin + R() * (L.zMax - L.zMin);
      const seam = (Math.abs(((z + 100) % 1.2) - 0.6) > 0.56 || Math.abs(((x + 100) % 0.9) - 0.45) > 0.42);
      add(x, 0.02, z, jc(seam ? [0.34, 0.33, 0.31] : stone, 0.22), 0.20, inPassage(x, z));
    }
    // side street paving (right side)
    for (let i = 0; i < N(1100); i++) add(-L.half - R() * L.side.len, 0.02, L.side.z0 + R() * (L.side.z1 - L.side.z0), jc(stone, 0.22), 0.22, 0);
    // facades: building blocks with Neapolitan colours, windows and green shutters
    const pal = [[0.82, 0.64, 0.40], [0.74, 0.44, 0.31], [0.85, 0.67, 0.61], [0.88, 0.79, 0.55], [0.70, 0.60, 0.49]];
    const blocks = [];
    for (const side of [1, -1]) {
      let z = L.zMin, k = side > 0 ? 0 : 2;
      while (z < L.zMax) {
        const wdt = 6 + R() * 4, hgt = 12 + R() * 6;
        blocks.push({ side, z0: z, z1: Math.min(L.zMax, z + wdt), h: hgt, c: pal[k % pal.length] });
        z += wdt; k++;
      }
    }
    for (const b of blocks) {
      const x = b.side * L.half, area = (b.z1 - b.z0) * 11;
      const n = N(area * 7);
      for (let i = 0; i < n; i++) {
        const z = b.z0 + R() * (b.z1 - b.z0), y = R() * 11;
        if (b.side < 0 && z > L.side.z0 && z < L.side.z1) continue;       // the side-street opening
        const inWin = y > 2.4 && ((y - 2.4) % 3.2) > 0.9 && ((y - 2.4) % 3.2) < 2.5 && ((z + 50) % 2.6) > 0.7 && ((z + 50) % 2.6) < 1.7;
        const shutter = inWin && (((z + 50) % 2.6) < 0.95 || ((z + 50) % 2.6) > 1.45);
        const c = shutter ? [0.24, 0.42, 0.31] : inWin ? [b.c[0] * 0.38, b.c[1] * 0.38, b.c[2] * 0.42] : b.c;
        add(x, y, z, jc(c, 0.16), 0.24, inPassage(0, z) && y < L.passage.roof);
      }
    }
    // side-street walls
    for (const zz of [L.side.z0, L.side.z1]) {
      for (let i = 0; i < N(700); i++) add(-L.half - R() * L.side.len, R() * 11, zz, jc(pal[3], 0.16), 0.24, 0);
    }
    // parked van (left side)
    const v = L.van, white = [0.88, 0.89, 0.92];
    for (let i = 0; i < N(1300); i++) {
      const f = R();
      let x, y, z;
      if (f < 0.34) { x = v.x0; y = 0.35 + R() * (v.h - 0.35); z = v.z0 + R() * (v.z1 - v.z0); }
      else if (f < 0.52) { x = v.x0 + R() * (v.x1 - v.x0); y = v.h; z = v.z0 + R() * (v.z1 - v.z0); }
      else if (f < 0.76) { x = v.x0 + R() * (v.x1 - v.x0); y = 0.35 + R() * (v.h - 0.35); z = v.z0; }
      else { x = v.x0 + R() * (v.x1 - v.x0); y = 0.35 + R() * (v.h - 0.35); z = v.z1; }
      const stripe = y > 1.05 && y < 1.3;
      add(x, y, z, jc(stripe ? [0.45, 0.47, 0.95] : white, 0.08), 0.2, 0);
    }
    // bollards
    for (const b of L.bollards) {
      for (let i = 0; i < N(220); i++) {
        const a = R() * Math.PI * 2, y = R() * 0.92;
        const band = y > 0.70 && y < 0.80;
        add(b.x + Math.cos(a) * 0.11, y, b.z + Math.sin(a) * 0.11, jc(band ? [0.95, 0.95, 0.9] : [0.36, 0.37, 0.40], 0.1), 0.12, 0);
      }
    }
    // covered passage: roof underside, entrance beams
    const pz = L.passage;
    for (let i = 0; i < N(1400); i++) add(-L.half + R() * 2 * L.half, pz.roof, pz.z0 + R() * (pz.z1 - pz.z0), jc([0.42, 0.42, 0.46], 0.2), 0.26, 1);
    for (const zz of [pz.z0, pz.z1]) {
      for (let i = 0; i < N(700); i++) {
        const x = -L.half + R() * 2 * L.half, y = 4.6 + R() * (pz.roof - 4.6);
        add(x, y, zz, jc([0.78, 0.74, 0.66], 0.12), 0.24, 0);
      }
    }
    // café on the right: tables and umbrellas
    for (let k = 0; k < 3; k++) {
      const cx = -3.9, cz = 31.4 + k * 1.5;
      for (let i = 0; i < N(140); i++) { const a = R() * Math.PI * 2, r = R() * 0.38; add(cx + Math.cos(a) * r, 0.74, cz + Math.sin(a) * r, jc([0.85, 0.85, 0.82], 0.1), 0.14, 0); }
      for (let i = 0; i < N(160); i++) { const a = R() * Math.PI * 2, r = Math.sqrt(R()) * 1.0; add(cx + Math.cos(a) * r, 2.25 - r * 0.15, cz + Math.sin(a) * r, jc([0.86, 0.35, 0.30], 0.12), 0.18, 0); }
    }
    // planters
    for (const p of L.planters) {
      for (let i = 0; i < N(160); i++) { const a = R() * Math.PI * 2, r = Math.sqrt(R()) * 0.5, y = R() * 1.0; add(p.x + Math.cos(a) * r, y, p.z + Math.sin(a) * r, jc(y > 0.45 ? [0.30, 0.52, 0.30] : [0.55, 0.42, 0.32], 0.2), 0.18, 0); }
    }
    P.sort((a, b) => a[2] - b[2]);
    const n = P.length;
    const M = {
      n, pos: new Float32Array(n * 3), col: new Float32Array(n * 3), noise: new Float32Array(n * 3),
      size: new Float32Array(n), dark: new Uint8Array(n), conf: new Float32Array(n), z: new Float32Array(n),
    };
    for (let i = 0; i < n; i++) {
      const p = P[i];
      M.pos[i * 3] = p[0]; M.pos[i * 3 + 1] = p[1]; M.pos[i * 3 + 2] = p[2];
      M.col[i * 3] = p[3]; M.col[i * 3 + 1] = p[4]; M.col[i * 3 + 2] = p[5];
      M.size[i] = p[6]; M.dark[i] = p[7];
      M.noise[i * 3] = p[8]; M.noise[i * 3 + 1] = p[9]; M.noise[i * 3 + 2] = p[10];
      M.z[i] = p[2];
    }
    M.blocks = blocks;
    return M;
  }

  function lowerBound(arr, v) { let lo = 0, hi = arr.length; while (lo < hi) { const m = (lo + hi) >> 1; if (arr[m] < v) lo = m + 1; else hi = m; } return lo; }

  const COS_MAP = Math.cos(L.mapFovHalf);
  function updateMap(M, S, dt) {
    if (!S.reliable) return 0;
    const w = S.w;
    let i = lowerBound(M.z, w.z - 1), touched = 0;
    const zHi = w.z + L.range;
    for (; i < M.n && M.z[i] <= zHi; i++) {
      if (M.conf[i] >= 1) continue;
      const x = M.pos[i * 3], y = M.pos[i * 3 + 1], z = M.pos[i * 3 + 2];
      const dx = x - w.x, dz = z - w.z, d = Math.hypot(dx, dz);
      if (d < 0.6 || d > L.range) continue;
      if ((w.hx * dx + w.hz * dz) / d < COS_MAP) continue;
      if (y > L.phoneH + d * 1.05 || y < L.phoneH - d * 1.2) continue;
      if (facadeBlocks(w, x, z)) continue;
      let rate = 2.4 * Math.exp(-d / 7.5);
      if (M.dark[i]) rate *= 0.03;
      M.conf[i] = Math.min(1, M.conf[i] + rate * dt);
      touched++;
    }
    return touched;
  }

  // ---------- Live state ----------
  function makeSim() {
    return {
      t: 0, w: { x: WALKER[0][1], z: WALKER[0][2], hx: 0, hz: 1, speed: 0, phase: 0 },
      trust: 0.93, reliable: true, belowT: 0, aboveT: 0,
      lastTick: -99, lastBuzz: -99, lastProx: -99, lastSayT: -99, pending: null, started: false,
      agents: AGENTS.map(a => Object.assign({}, a, {
        x: a.path[0][1], z: a.path[0][2], vx: 0, vz: 0, conf: 0, state: 'unseen', wasSure: false,
        hiddenT: 0, gx: 0, gz: 0, gvx: 0, gvz: 0, inPath: false, said: false, offT: 0,
        fastSaid: false, danger: false, d: 99, ang: 0, ahead: 0, lat: 0, frozen: false,
      })),
      events: [],
    };
  }

  function emit(S, type, extra) { S.events.push(Object.assign({ type, t: S.t }, extra || {})); }
  function say(S, text, priority, sfx) {
    const ev = { type: 'say', text, priority: !!priority, sfx: sfx || null, t: S.t };
    if (priority || S.t - S.lastSayT >= 1.7) { S.lastSayT = S.t; S.events.push(ev); if (priority) S.pending = null; }
    else S.pending = ev;
  }

  function step(S, dt) {
    const t = (S.t += dt);
    // walker
    const p = samplePath(WALKER, t), v = velocity(WALKER, t), sp = Math.hypot(v.x, v.z);
    S.w.x = p.x; S.w.z = p.z; S.w.speed = sp; S.w.phase += sp * dt * 1.9;
    if (sp > 0.15) {
      const k = Math.min(1, dt * 4);
      S.w.hx += (v.x / sp - S.w.hx) * k; S.w.hz += (v.z / sp - S.w.hz) * k;
      const n = Math.hypot(S.w.hx, S.w.hz); S.w.hx /= n; S.w.hz /= n;
    }
    if (!S.started && t >= 0.4) { S.started = true; say(S, VOICE.start, true, null); S.lastTick = t - 1.2; }
    // self-check: is the picture good enough to guide?
    const dark = S.w.z > L.passage.z0 + 0.3 && S.w.z < L.passage.z1;
    const target = dark ? 0.14 : 0.93;
    S.trust += (target - S.trust) * Math.min(1, dt * 7);
    if (S.reliable) {
      S.belowT = S.trust < 0.45 ? S.belowT + dt : 0;
      if (S.belowT >= 0.3) { S.reliable = false; S.aboveT = 0; S.lastBuzz = t; say(S, VOICE.dark, true, 'long'); }
    } else {
      S.aboveT = S.trust >= 0.45 ? S.aboveT + dt : 0;
      if (S.aboveT >= 1.0) { S.reliable = true; S.belowT = 0; S.lastTick = t; say(S, VOICE.light, true, 'rising'); }
    }
    if (S.started && S.reliable && t - S.lastTick >= 2.0) { S.lastTick = t; emit(S, 'tick'); }
    if (!S.reliable && t - S.lastBuzz >= 4.0) { S.lastBuzz = t; emit(S, 'haptic', { pattern: 'long' }); }

    // objects
    for (const a of S.agents) {
      const ap = samplePath(a.path, t), av = velocity(a.path, t);
      a.x = ap.x; a.z = ap.z; a.vx = av.x; a.vz = av.z;
      const s = sight(S.w, a.x, a.z);
      a.d = s.d; a.ang = s.ang;
      const side = s.ang > 0 ? 'sinistra' : 'destra';
      a.ahead = (a.x - S.w.x) * S.w.hx + (a.z - S.w.z) * S.w.hz;
      a.lat = (a.x - S.w.x) * S.w.hz - (a.z - S.w.z) * S.w.hx;
      a.danger = false;
      if (!S.reliable) { a.frozen = true; continue; }
      a.frozen = false;
      if (s.visible) {
        const was = a.state;
        a.conf = Math.min(1, a.conf + dt * (a.fast ? 7 : 2.6 * Math.exp(-s.d / 7)));
        a.gx = a.x; a.gz = a.z; a.gvx = a.vx; a.gvz = a.vz; a.hiddenT = 0;
        a.state = a.conf >= 0.6 ? 'sure' : 'maybe';
        if (was === 'hidden' && a.wasSure) say(S, VOICE.back(a, side), false, 'knock');
        if (a.state === 'sure') a.wasSure = true;
      } else if (s.inFov && !s.wall && !s.dark && s.occl && (a.state === 'sure' || a.state === 'maybe' || a.state === 'hidden')) {
        if (a.state !== 'hidden') { a.state = 'hidden'; a.hiddenT = 0; if (a.wasSure) say(S, VOICE.hidden(a, side), false, 'flutter'); }
        a.hiddenT += dt; a.gx += a.gvx * dt; a.gz += a.gvz * dt;
        if (a.hiddenT > 3.0) { a.state = 'lost'; a.wasSure = false; say(S, VOICE.lost(a), false, null); }
      } else {
        if (a.state === 'sure' || a.state === 'maybe' || a.state === 'hidden') a.state = 'out';
        a.conf = Math.max(0, a.conf - dt * 0.12);
      }
      // fast mover heading into the walker's line
      const speed = Math.hypot(a.vx, a.vz);
      if (a.fast && s.visible && speed > 3) {
        const tc = (S.w.x - a.x) / (Math.abs(a.vx) > 1e-3 ? a.vx : 1e-3);
        if (tc > -0.4 && tc < 2.5 && a.ahead > 0 && a.ahead < 9) {
          a.danger = true;
          if (!a.fastSaid) { a.fastSaid = true; say(S, VOICE.fast(a, side), true, 'fast'); }
        }
      }
      // something sure in the walking path
      const halfW = L.corridorHalf + (a.kind === 'ostacolo' ? 0.35 : 0.3);
      const inPath = a.state === 'sure' && a.ahead > 0.3 && a.ahead < L.corridorLen && Math.abs(a.lat) < halfW;
      if (inPath) {
        a.offT = 0;
        if (!a.said && !a.fast) { a.said = true; say(S, VOICE.ahead(a), false, 'knock'); }
        if (a.ahead < 3.5) a.danger = true;
        if (a.kind === 'ostacolo' && a.ahead < 5.0) {
          const iv = Math.max(0.12, 0.12 + ((a.ahead - 1.0) / 4.0) * 0.68);
          if (t - S.lastProx >= iv) { S.lastProx = t; emit(S, 'prox', { d: a.ahead }); }
        }
      } else { a.offT += dt; if (a.offT > 4) a.said = false; }
      a.inPath = inPath;
    }
    if (S.pending && t - S.pending.t > 1.2) S.pending = null;   // a stale line is dropped, never said late
    if (S.pending && t - S.lastSayT >= 1.7) { const ev = S.pending; S.pending = null; S.lastSayT = t; ev.t = t; S.events.push(ev); }
  }

  root.FVSim = { L, WALKER, AGENTS, VOICE, CHAPTERS, samplePath, velocity, sight, buildMap, updateMap, makeSim, step, rng, inPassage };
})(typeof window !== 'undefined' ? window : globalThis);
