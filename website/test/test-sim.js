require('../src/sim-core.js');
const F = globalThis.FVSim;
const M = F.buildMap(11);
const S = F.makeSim();
const dt = 1 / 30;
let prev = {};
const out = [];
for (let i = 0; i < F.L.T / dt; i++) {
  F.step(S, dt); F.updateMap(M, S, dt);
  for (const e of S.events) {
    if (e.type === 'tick') continue;
    out.push(`${e.t.toFixed(2).padStart(6)}  ${e.type.padEnd(6)} ${e.text ? '«' + e.text + '»' : ''} ${e.sfx || e.pattern || ''} ${e.d ? 'd=' + e.d.toFixed(1) : ''}`);
  }
  S.events.length = 0;
  for (const a of S.agents) {
    const k = a.id + a.state;
    if (prev[a.id] !== a.state) { out.push(`${S.t.toFixed(2).padStart(6)}    #${a.id} ${a.kind} → ${a.state} (d ${a.d.toFixed(1)}, ahead ${a.ahead.toFixed(1)}, lat ${a.lat.toFixed(2)})`); prev[a.id] = a.state; }
  }
  if (Math.abs(S.t - 20) < dt / 2 || Math.abs(S.t - 46) < dt / 2) {
    let seen = 0, solid = 0; for (let j = 0; j < M.n; j++) { if (M.conf[j] > 0.05) seen++; if (M.conf[j] > 0.8) solid++; }
    out.push(`        map @${S.t.toFixed(0)}s: ${M.n} pts, seen ${seen}, locked ${solid}, walker z ${S.w.z.toFixed(1)}`);
  }
}
// prox summary
console.log(out.filter(l => !l.includes(' prox ')).join('\n'));
const prox = out.filter(l => l.includes(' prox ')); console.log(`prox pulses: ${prox.length}, first ${prox[0]}, last ${prox[prox.length-1]}`);
