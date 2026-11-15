// Mac simulation for the floor reader (FieldVision/FloorSteps.swift).
// Synthetic streets are ray-cast into depth pictures with depth-model-like errors (smooth distortion, noise,
// blurred edges, random blobs, an unknown affine scale), then fed through the same code the app runs:
// metric fit from fake ARKit feature points, the floor reader, and the announcer.
// Run: tools/steps-sim/run.sh
import Foundation
import simd
import CoreGraphics

// MARK: - random numbers

struct RNG {
    var s: UInt64
    init(_ seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 &+ 1 }
    mutating func next() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
    mutating func uniform() -> Float { Float(next() >> 40) / Float(1 << 24) }
    mutating func range(_ a: Float, _ b: Float) -> Float { a + (b - a) * uniform() }
    mutating func normal() -> Float {
        let u1 = max(1e-7, uniform()), u2 = uniform()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

// MARK: - scenes

struct Box { var lo: SIMD3<Float>; var hi: SIMD3<Float> }
struct Cyl { var c: SIMD2<Float>; var r: Float; var y0: Float; var y1: Float }
struct Truth { var label: String; var kinds: Set<FloorKind>; var center: SIMD2<Float>; var dir: SIMD2<Float>; var width: Float; var mustSay: Bool }

final class Scene {
    let name: String
    var terrain: (Float, Float) -> Float = { _, _ in 0 }
    var maxTerrain: Float = 2.5
    var boxes: [Box] = []
    var cyls: [Cyl] = []
    var truth: [Truth] = []
    var start = SIMD3<Float>(0, 0, 0)
    var speed: Float = 1.2
    var duration: Double = 26
    var stopAlong: Float? = 0.6
    var tilt: Float = 8                                  // degrees, camera looking down
    /// dark scenes: is this world point lit (torch or street lamp)?
    var lit: ((SIMD3<Float>, SIMD3<Float>) -> Bool)? = nil
    init(_ n: String) { name = n }

    func cast(_ o: SIMD3<Float>, _ d: SIMD3<Float>, maxT: Float = 90) -> Float? {
        var best = maxT
        var any = false
        for b in boxes {
            let inv = SIMD3<Float>(1 / (abs(d.x) < 1e-6 ? 1e-6 : d.x), 1 / (abs(d.y) < 1e-6 ? 1e-6 : d.y), 1 / (abs(d.z) < 1e-6 ? 1e-6 : d.z))
            let t0 = (b.lo - o) * inv, t1 = (b.hi - o) * inv
            let tmin = simd_reduce_max(simd_min(t0, t1)), tmax = simd_reduce_min(simd_max(t0, t1))
            if tmax >= max(tmin, 0.01) && tmin > 0.01 && tmin < best { best = tmin; any = true }
        }
        for c in cyls {
            let ox = o.x - c.c.x, oz = o.z - c.c.y
            let a = d.x * d.x + d.z * d.z, b = 2 * (ox * d.x + oz * d.z), cc = ox * ox + oz * oz - c.r * c.r
            let disc = b * b - 4 * a * cc
            if a > 1e-8 && disc >= 0 {
                let t = (-b - disc.squareRoot()) / (2 * a)
                let y = o.y + d.y * t
                if t > 0.01 && t < best && y >= c.y0 && y <= c.y1 { best = t; any = true }
            }
        }
        var t: Float = 0.05, prev: Float = 0.05
        while t < best {
            let p = o + d * t
            if d.y >= 0 && p.y > maxTerrain { break }
            if p.y < terrain(p.x, p.z) {
                var lo = prev, hi = t
                for _ in 0..<22 { let m = (lo + hi) / 2; let q = o + d * m; if q.y < terrain(q.x, q.z) { hi = m } else { lo = m } }
                if hi < best { best = hi; any = true }
                break
            }
            prev = t
            t += max(0.01, 0.009 * t)
        }
        return any ? best : nil
    }
}

/// Stairs cut into a retaining wall, up to a terrace: x half-width w, first riser at along = 0.
func terraceStairs(_ x: Float, _ along: Float, w: Float, n: Int, rise: Float, tread: Float) -> Float {
    guard along >= 0 else { return 0 }
    return abs(x) < w ? stairsHeight(along, n: n, rise: rise, tread: tread) : rise * Float(n)
}

func stairsHeight(_ along: Float, n: Int, rise: Float, tread: Float) -> Float {
    guard along >= 0 else { return 0 }
    return rise * Float(min(n, Int(along / tread) + 1))
}

func scenes() -> [Scene] {
    var out: [Scene] = []
    let wallFar = Box(lo: SIMD3(-25, -3, -60), hi: SIMD3(25, 8, -58))
    func across(_ z: Float, _ w: Float = 6) -> SIMD2<Float> { SIMD2(0, z) }

    do { let s = Scene("flat street, nothing on the floor"); s.boxes = [wallFar]; s.duration = 22; s.stopAlong = nil; out.append(s) }
    do {
        let s = Scene("ramp 6% from 10 m (must stay silent)"); s.boxes = [wallFar]; s.stopAlong = nil; s.duration = 22
        s.terrain = { _, z in let a = -z - 10; return a <= 0 ? 0 : min(1.2, 0.06 * a) }; out.append(s)
    }
    do {
        let s = Scene("street climbing 12% (must stay silent)"); s.boxes = [wallFar]; s.stopAlong = nil; s.duration = 18
        s.terrain = { _, z in max(0, 0.12 * (-z - 4)) }; s.maxTerrain = 6; out.append(s)
    }
    do {
        let s = Scene("curb up 15 cm at 26 m"); s.boxes = [wallFar]
        s.terrain = { _, z in z < -26 ? 0.15 : 0 }
        s.truth = [Truth(label: "curb up", kinds: [.stepUp], center: SIMD2(0, -26), dir: SIMD2(1, 0), width: 120, mustSay: true)]; out.append(s)
    }
    do {
        let s = Scene("curb down 15 cm at 24 m"); s.boxes = [wallFar]
        s.terrain = { _, z in z < -24 ? -0.15 : 0 }
        s.truth = [Truth(label: "curb down", kinds: [.stepDown], center: SIMD2(0, -24), dir: SIMD2(1, 0), width: 120, mustSay: true)]; out.append(s)
    }
    do {
        let s = Scene("stairs up, 8 x 17 cm, starting at 30 m"); s.boxes = [wallFar]; s.duration = 30
        s.terrain = { x, z in terraceStairs(x, -z - 30, w: 1.6, n: 8, rise: 0.17, tread: 0.29) }
        s.truth = [Truth(label: "stairs up", kinds: [.stairsUp], center: SIMD2(0, -30), dir: SIMD2(1, 0), width: 3.2, mustSay: true)]; out.append(s)
    }
    do {
        let s = Scene("stairs down, 10 x 17 cm, top edge at 22 m (stairwell)"); s.duration = 26
        s.terrain = { x, z in abs(x) < 2.2 ? -stairsHeight(-z - 22, n: 10, rise: 0.17, tread: 0.29) : 0 }
        s.boxes = [Box(lo: SIMD3(-2.4, -2.2, -40), hi: SIMD3(-2.2, 1.0, -22)), Box(lo: SIMD3(2.2, -2.2, -40), hi: SIMD3(2.4, 1.0, -22)), wallFar]
        s.truth = [Truth(label: "stairs down", kinds: [.stairsDown, .dropOff], center: SIMD2(0, -22), dir: SIMD2(1, 0), width: 4.4, mustSay: true)]; out.append(s)
    }
    do {
        let s = Scene("ledge 1 m down at 20 m"); s.boxes = [wallFar]
        s.terrain = { _, z in z < -20 ? -1.0 : 0 }
        s.truth = [Truth(label: "ledge", kinds: [.dropOff], center: SIMD2(0, -20), dir: SIMD2(1, 0), width: 120, mustSay: true)]; out.append(s)
    }
    do {
        let s = Scene("stairs up off to the left (25 degrees, 18 m), walking past"); s.boxes = [wallFar]; s.stopAlong = nil; s.duration = 14
        s.terrain = { x, z in x < -6.0 ? terraceStairs(x + 7.6, -z - 16.3, w: 1.6, n: 6, rise: 0.16, tread: 0.3) : 0 }
        s.truth = [Truth(label: "stairs left", kinds: [.stairsUp], center: SIMD2(-7.6, -16.3), dir: SIMD2(1, 0), width: 3.2, mustSay: true)]; out.append(s)
    }
    do {
        let s = Scene("one 3-step flight, 15 cm, at 16 m"); s.boxes = [wallFar]
        s.terrain = { x, z in terraceStairs(x, -z - 16, w: 2, n: 3, rise: 0.15, tread: 0.32) }
        s.truth = [Truth(label: "3 steps", kinds: [.stairsUp], center: SIMD2(0, -16), dir: SIMD2(1, 0), width: 4, mustSay: true)]; out.append(s)
    }
    do {
        let s = Scene("small 12 cm step up at 24 m"); s.boxes = [wallFar]
        s.terrain = { _, z in z < -24 ? 0.12 : 0 }
        s.truth = [Truth(label: "12 cm step", kinds: [.stepUp], center: SIMD2(0, -24), dir: SIMD2(1, 0), width: 120, mustSay: true)]; out.append(s)
    }
    do {
        let s = Scene("low box 25 cm on the floor at 9 m (not a step)"); s.boxes = [wallFar]; s.stopAlong = nil; s.duration = 7
        s.terrain = { x, z in (abs(x) < 0.5 && z < -9 && z > -9.5) ? 0.25 : 0 }; out.append(s)
    }
    do {
        let s = Scene("planter 35 cm high, 1 m deep, at 10 m (not a step)"); s.boxes = [wallFar]; s.stopAlong = nil; s.duration = 8
        s.terrain = { x, z in (abs(x) < 1 && z < -10 && z > -11) ? 0.35 : 0 }; out.append(s)
    }
    do {
        let s = Scene("wall 2.5 m across the path at 14 m (not a step)"); s.stopAlong = nil; s.duration = 10
        s.boxes = [Box(lo: SIMD3(-6, 0, -14.2), hi: SIMD3(6, 2.5, -14))]; out.append(s)
    }
    do {
        let s = Scene("people and a parked car (not steps)"); s.boxes = [wallFar, Box(lo: SIMD3(1.3, 0, -15), hi: SIMD3(3.1, 1.5, -10.8))]
        s.cyls = [Cyl(c: SIMD2(0.6, -7), r: 0.25, y0: 0, y1: 1.75), Cyl(c: SIMD2(-1.2, -12), r: 0.25, y0: 0, y1: 1.7),
                  Cyl(c: SIMD2(0.3, -19), r: 0.25, y0: 0, y1: 1.8), Cyl(c: SIMD2(-2.5, -24), r: 0.3, y0: 0, y1: 1.6)]
        s.stopAlong = nil; s.duration = 5; out.append(s)
    }
    // dark: torch only (lights about 6 m in a cone)
    let torch: (SIMD3<Float>, SIMD3<Float>) -> Bool = { cam, p in
        let d = p - cam
        let hd = (d.x * d.x + d.z * d.z).squareRoot()
        return hd < 6.5
    }
    do {
        let s = Scene("DARK, torch only: stairs up at 12 m"); s.boxes = [wallFar]; s.lit = torch; s.duration = 14
        s.terrain = { x, z in terraceStairs(x, -z - 12, w: 1.6, n: 8, rise: 0.17, tread: 0.29) }
        s.truth = [Truth(label: "stairs up (dark)", kinds: [.stairsUp], center: SIMD2(0, -12), dir: SIMD2(1, 0), width: 3.2, mustSay: true)]; out.append(s)
    }
    do {
        let s = Scene("DARK, torch only: curb down at 10 m"); s.boxes = [wallFar]; s.lit = torch; s.duration = 12
        s.terrain = { _, z in z < -10 ? -0.15 : 0 }
        s.truth = [Truth(label: "curb down (dark)", kinds: [.stepDown], center: SIMD2(0, -10), dir: SIMD2(1, 0), width: 120, mustSay: true)]; out.append(s)
    }
    do {
        let s = Scene("NIGHT street: lamps at 15 and 30 m, stairs up at 24 m"); s.boxes = [wallFar]; s.duration = 26
        s.lit = { cam, p in
            let d = p - cam
            if (d.x * d.x + d.z * d.z).squareRoot() < 6.5 { return true }
            for lz: Float in [-15, -30] { let q = SIMD2(p.x, p.z) - SIMD2(0.0, lz); if simd_length(q) < 7 { return true } }
            return false
        }
        s.terrain = { x, z in terraceStairs(x, -z - 24, w: 1.6, n: 8, rise: 0.17, tread: 0.29) }
        s.truth = [Truth(label: "stairs up (night)", kinds: [.stairsUp], center: SIMD2(0, -24), dir: SIMD2(1, 0), width: 3.2, mustSay: true)]; out.append(s)
    }
    // the same key scenes with the phone held straight (0°) and tilted well down (20°)
    for tilt: Float in [0, 20] {
        for base in out where !base.name.contains("tilt") && (base.name.hasPrefix("curb up") || base.name.hasPrefix("stairs up, 8") || base.name.hasPrefix("stairs down") || base.name.hasPrefix("flat") || base.name.hasPrefix("curb down")) {
            let s = Scene(base.name + " · tilt \(Int(tilt))°")
            s.terrain = base.terrain; s.maxTerrain = base.maxTerrain; s.boxes = base.boxes; s.cyls = base.cyls
            s.truth = base.truth; s.start = base.start; s.speed = base.speed; s.duration = base.duration
            s.stopAlong = base.stopAlong; s.lit = base.lit; s.tilt = tilt
            out.append(s)
        }
    }
    return out
}

// MARK: - camera

let fx: Float = 1440
func intrinsics() -> simd_float3x3 { simd_float3x3(SIMD3(fx, 0, 0), SIMD3(0, fx, 0), SIMD3(960, 720, 1)) }

func makeCam(pos: SIMD3<Float>, yaw: Float, pitchDown: Float, roll: Float) -> StepCam {
    let fwdH = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
    let up = SIMD3<Float>(0, 1, 0)
    let v = simd_normalize(fwdH * cos(pitchDown) - up * sin(pitchDown))
    let right = simd_normalize(simd_cross(v, up))
    let Z = -v
    var Y = right
    var X = simd_cross(Y, Z)
    if roll != 0 { let c = cos(roll), s = sin(roll); let X2 = X * c + Y * s; let Y2 = -X * s + Y * c; X = X2; Y = Y2 }
    let m = simd_float4x4(SIMD4(X, 0), SIMD4(Y, 0), SIMD4(Z, 0), SIMD4(pos, 1))
    return StepCam(transform: m, intrinsics: intrinsics(), width: 1920, height: 1440)
}

// MARK: - fake depth model

let W = 518, H = 392

struct DepthNoise {
    var a1: Float, a2: Float, a3: Float, f: Float, ph: Float
    var white: Float
    var blobs: [(c: SIMD2<Float>, r: Float, a: Float)]
    var s0: Float, t0: Float
    init(_ g: inout RNG, strength: Float) {
        a1 = g.normal() * 0.035 * strength; a2 = g.normal() * 0.035 * strength; a3 = g.normal() * 0.015 * strength
        f = g.range(1, 3); ph = g.range(0, 6.28)
        white = 0.012 * strength
        blobs = (0..<2).map { _ in (SIMD2(g.uniform(), g.uniform()), g.range(0.03, 0.08), g.normal() * 0.05 * strength) }
        s0 = g.range(2, 8); t0 = g.range(-0.02, 0.04)
    }
    func field(_ xu: Float, _ yb: Float) -> Float {
        var k = 1 + a1 * (xu - 0.5) + a2 * (yb - 0.5) + a3 * sin(2 * .pi * f * yb + ph)
        for b in blobs { let d = SIMD2(xu, yb) - b.c; k += b.a * exp(-simd_length_squared(d) / (b.r * b.r)) }
        return k
    }
}

struct Rendered { var rel: [Float]; var lit: [Bool] }

func render(_ sc: Scene, cam: StepCam, band: DepthBand, noise: DepthNoise, g: inout RNG) -> Rendered {
    var rel = [Float](repeating: .nan, count: W * H)
    var lit = [Bool](repeating: true, count: W * H)
    let grid = DepthGrid(rel: [], W: W, H: H, band: band, s: 0, t: 0)
    var inv = [Float](repeating: 0, count: H)
    var i = 2
    while i < W {
        for j in 0..<H {
            let uv = grid.sensor(i, j, cam)
            let d = cam.ray(u: uv.x, v: uv.y)
            var v: Float = 1 / 250
            if let th = sc.cast(cam.position, d) {
                v = 1 / max(0.05, th * simd_dot(d, cam.forward))
                if let l = sc.lit { lit[j * W + i] = l(cam.position, cam.position + d * th) }
            } else if sc.lit != nil { lit[j * W + i] = false }
            let xu = (Float(i) + 0.5) / Float(W), yb = (Float(j) + 0.5) / Float(H)
            inv[j] = v * noise.field(xu, yb) * (1 + noise.white * g.normal())
        }
        for j in 0..<H {
            let a = inv[max(0, j - 1)], b = inv[j], c = inv[min(H - 1, j + 1)]
            rel[j * W + i] = ((a + b + c) / 3 - noise.t0) / noise.s0
        }
        i += 4
    }
    return Rendered(rel: rel, lit: lit)
}

/// Fake ARKit feature points: random pixels, true 3D position plus ~1% noise, up to 20 m, lit ones only in the dark.
func featurePoints(_ sc: Scene, cam: StepCam, g: inout RNG, n: Int) -> [SIMD3<Float>] {
    var out: [SIMD3<Float>] = []
    for _ in 0..<n {
        let u = g.range(0, 1920), v = g.range(0, 1440)
        let d = cam.ray(u: u, v: v)
        guard let th = sc.cast(cam.position, d), th < 20 else { continue }
        let p = cam.position + d * th
        if let l = sc.lit, !l(cam.position, p) { continue }
        out.append(p + d * (th * 0.01 * g.normal()))
    }
    return out
}

/// Fills the model output at the feature points' pixels (no blur there), like the real model would have.
func fillPairs(_ r: inout Rendered, pts: [SIMD3<Float>], sc: Scene, cam: StepCam, band: DepthBand, noise: DepthNoise, g: inout RNG) {
    let grid = DepthGrid(rel: [], W: W, H: H, band: band, s: 0, t: 0)
    for p in pts {
        guard let uv = cam.project(p), let ij = grid.index(uv, cam) else { continue }
        let k = ij.j * W + ij.i
        guard r.rel[k].isNaN else { continue }
        let c = grid.sensor(ij.i, ij.j, cam)
        let d = cam.ray(u: c.x, v: c.y)
        var v: Float = 1 / 250
        if let th = sc.cast(cam.position, d) { v = 1 / max(0.05, th * simd_dot(d, cam.forward)) }
        let xu = (Float(ij.i) + 0.5) / Float(W), yb = (Float(ij.j) + 0.5) / Float(H)
        r.rel[k] = (v * noise.field(xu, yb) * (1 + noise.white * g.normal()) - noise.t0) / noise.s0
    }
}

// MARK: - run one scene

struct Result { var name: String; var ok: Bool; var notes: [String] }

func run(_ sc: Scene, seed: UInt64, noiseStrength: Float, verbose: Bool) -> Result {
    var g = RNG(seed)
    let reader = StepReader()
    let announcer = StepAnnouncer()
    var central = DepthScale(), floorScale = DepthScale()
    let centralBand: DepthBand = { let b = DepthEstimator.band(for: CGSize(width: 1920, height: 1440)); return DepthBand(y0: b.y0, h: b.h) }()
    var lastC = -1.0, lastF = -0.12, lastA = 0.0
    var t = 0.0
    let dt = 1.0 / 30
    var walked: Float = 0
    var firstSure: [Int: (t: Double, along: Float, kind: FloorKind)] = [:]
    var firstSay: [Int: (along: Float, kind: FloorKind, text: String)] = [:]
    var nearSay: [Int: (along: Float, kind: FloorKind, text: String)] = [:]
    var wrongSay: [String] = []
    var said: [String] = []
    var falseIds = Set<Int>()
    var falseNotes: [String] = []
    var falseSay: [String] = []
    var lastKind: [Int: FloorKind] = [:]
    var obstacleNoted = false
    var carefulSay: [String] = []
    var trace: [String] = []
    var stopped = false
    var notes: [String] = []
    let yaw0: Float = 0

    func walkerPos(_ walked: Float) -> SIMD3<Float> {
        let fwd = SIMD3<Float>(-sin(yaw0), 0, -cos(yaw0))
        var p = sc.start + fwd * walked
        p.y = sc.terrain(p.x, p.z)
        return p
    }
    func alongTo(_ tr: Truth, _ w: SIMD3<Float>) -> Float { -(tr.center.y - w.z) }   // walking along -z
    func matchTruth(_ v: StepView) -> Int? {
        sc.truth.firstIndex(where: { tr in
            let d = v.f.center - tr.center
            let polarityOK = tr.kinds.contains(where: { ($0 == .stepUp || $0 == .stairsUp) == v.f.isUp })
            let tol = 0.6 + 0.18 * v.dist                      // far edges are placed roughly (monocular depth: ±15% at 30 m)
            // a staircase's sides belong to it
            // the stairs go away from the start point (walking along -z): across = how far into them
            var nrm = SIMD2<Float>(-tr.dir.y, tr.dir.x)
            if simd_dot(tr.center - SIMD2(sc.start.x, sc.start.z), nrm) < 0 { nrm = -nrm }
            let into = simd_dot(d, nrm)
            let inside = abs(simd_dot(d, tr.dir)) < tr.width / 2 + tol && into > -tol && into < 3.5
            return polarityOK && (abs(simd_dot(d, SIMD2(-tr.dir.y, tr.dir.x))) < tol || (tr.kinds.contains(.stairsUp) && inside))
                && abs(simd_dot(d, tr.dir)) < tr.width / 2 + tol
        })
    }

    while t < sc.duration {
        let foot = walkerPos(walked)
        let camPos = foot + SIMD3(0, 1.35 + 0.02 * sin(Float(t) * 2 * .pi * 1.8), 0)
        let pitch = (sc.tilt + 2 * sin(Float(t) * 2 * .pi * 0.9)) * .pi / 180
        let roll = 2 * sin(Float(t) * 2 * .pi * 0.9 + 1) * .pi / 180
        let yaw = yaw0 + 1.5 * sin(Float(t) * 0.3) * .pi / 180
        let cam = makeCam(pos: camPos, yaw: yaw, pitchDown: pitch, roll: roll)
        let ground = foot.y + 0.01 * g.normal()
        let fwd2 = SIMD2<Float>(-sin(yaw), -cos(yaw))

        // central band at 6 Hz, floor band at 4 Hz in between (as in the app)
        var job: (band: DepthBand, isFloor: Bool)? = nil
        if t - lastC >= 1.0 / 6 { lastC = t; job = (centralBand, false) }
        else if t - lastF >= 1.0 / 4 && t - lastC > 0.06, let fb = DepthBand.floor(cam: cam, h: centralBand.h) { lastF = t; job = (fb, true) }
        if let job {
            let noise = DepthNoise(&g, strength: noiseStrength)
            var r = render(sc, cam: cam, band: job.band, noise: noise, g: &g)
            let pts = featurePoints(sc, cam: cam, g: &g, n: sc.lit == nil ? 260 : 160)
            fillPairs(&r, pts: pts, sc: sc, cam: cam, band: job.band, noise: noise, g: &g)
            let pairs = DepthPairs.fromPoints(pts, rel: r.rel, W: W, H: H, band: job.band, cam: cam, maxZ: job.isFloor ? 18 : 15)
            if job.isFloor {
                var ps = pairs
                if ps.count < 8 { ps += DepthPairs.fromFloor(rel: r.rel, W: W, H: H, band: job.band, cam: cam, ground: ground) }
                floorScale.fit(ps, now: t)
            } else {
                central.fit(pairs, now: t)
            }
            let sc2 = job.isFloor ? floorScale : central
            if sc2.valid && sc2.lastFit == t {
                let grid = DepthGrid(rel: r.rel, W: W, H: H, band: job.band, s: sc2.s, t: sc2.t)
                let litMask = r.lit
                let litFn: ((SIMD2<Float>) -> Bool)? = sc.lit == nil ? nil : { uv in
                    guard let ij = grid.index(uv, cam) else { return false }
                    return litMask[ij.j * W + ij.i]
                }
                let obs = reader.ingest(grid, cam: cam, ground: ground, t: t, lit: litFn)
                if debugFalse > 0 && t >= debugFrom {
                    for o in obs where o.r < 26 && !sc.truth.contains(where: { simd_distance($0.center, o.center) < $0.width / 2 + 1.5 && abs(o.center.y - $0.center.y) < 1.5 }) {
                        guard debugFalse > 0 else { break }
                        debugFalse -= 1
                        print(String(format: "  DEBUG t=%.2f %@ obs %@ r=%.1f rise=%.3f support=%d width=%.2f steps=%d", t, job.isFloor ? "floor" : "central", o.kind.rawValue, o.r, o.rise, o.support, o.width, o.steps))
                        let ra = grid.rowAngle(cam)
                        let cols = ColumnReader.columns(grid, cam: cam, ground: ground, maxRange: 30, colStride: 4, lit: litFn)
                        var shown = 0
                        for (ci, col) in cols.enumerated() {
                            let evs = ColumnReader.events(col, col: ci * 4 + 2, rowAngle: ra, camY: cam.position.y, ground: ground)
                            for e in evs where simd_distance(e.edge, o.center) < o.width / 2 + 0.5 && shown < 2 {
                                shown += 1
                                print(String(format: "    col %d event up=%d rise=%.3f r=%.2f steps=%d", ci * 4 + 2, e.up ? 1 : 0, e.rise, e.r, e.steps))
                                if let k = col.firstIndex(where: { simd_distance($0.p, e.edge) < 0.6 }) {
                                    let lo = max(0, k - 10), hi = min(col.count - 1, k + 14)
                                    var line = "      "
                                    for x in col[lo...hi] { line += String(format: "(%.2f,%.3f) ", x.r, x.h) }
                                    print(line)
                                }
                            }
                        }
                    }
                }
            }
        }

        if t - lastA >= 0.2 {
            lastA = t
            reader.maintain(t: t, walker: camPos, fwd: fwd2)
            let views = reader.views(walker: camPos, fwd: fwd2)
            for v in views {
                if let ti = matchTruth(v) {
                    if firstSure[ti] == nil { firstSure[ti] = (t, alongTo(sc.truth[ti], foot), v.f.kind) }
                    if verbose && lastKind[v.f.id] != v.f.kind {
                        lastKind[v.f.id] = v.f.kind
                        let vs = v.f.votes.map { "\($0.key.rawValue)=\(String(format: "%.2f", $0.value))" }.sorted().joined(separator: " ")
                        trace.append(String(format: "   #%d -> %@ at %.1f m (rise %.2f, hits %d) votes: %@", v.f.id, v.f.kind.rawValue, alongTo(sc.truth[ti], foot), v.f.rise, v.f.hits, vs))
                    }
                } else if !falseIds.contains(v.f.id) {
                    falseIds.insert(v.f.id)
                    falseNotes.append(String(format: "FALSE %@ at %.1f m (bearing %.0f°) t=%.1f", v.f.kind.rawValue, v.dist, v.bearing * 180 / .pi, t))
                }
            }
            // stairs going up must never reach the obstacle check (5 m): the rising stretch has to cover them
            for tr in sc.truth where tr.kinds.contains(.stairsUp) {
                let along = alongTo(tr, foot)
                if along > 0.8 && along < 5.0 && abs(tr.center.x) < 1 {
                    if let st = reader.risingStretch(walker: camPos, fwd: fwd2), st.from <= along + 0.3, st.to >= along + 0.6 {} else {
                        if !obstacleNoted {
                            obstacleNoted = true
                            wrongSay.append(String(format: "STAIRS NOT SHIELDED from the obstacle check at %.1f m", along))
                            if verbose {
                                let w = SIMD2(camPos.x, camPos.z)
                                for f in reader.features {
                                    wrongSay.append(String(format: "   feature #%d %@ up=%d conf=%.2f was=%d hits=%d centerAlong=%.2f lat=%.2f width=%.2f extent=%.2f",
                                        f.id, f.kind.rawValue, f.isUp ? 1 : 0, f.conf, f.wasConfirmed ? 1 : 0, f.hits, simd_dot(f.center - w, fwd2), simd_dot(f.center - w, SIMD2(fwd2.y, -fwd2.x)), f.width, f.extent))
                                }
                                if let st = reader.risingStretch(walker: camPos, fwd: fwd2) { wrongSay.append(String(format: "   stretch %.2f ... %.2f", st.from, st.to)) } else { wrongSay.append("   no stretch") }
                            }
                        }
                    }
                }
            }
            if let line = announcer.next(views, t: t) {
                let txt = line.far ? Say.floorFar(line.kind, distance: line.distance, side: line.side, .it) : Say.floor(line.kind, distance: line.distance, .it)
                said.append(String(format: "t=%4.1f  «%@»%@", t, txt, line.urgent ? " (urgent)" : ""))
                if let v = views.first(where: { $0.f.id == line.id }) {
                    if let ti = matchTruth(v) {
                        let along = alongTo(sc.truth[ti], foot)
                        if firstSay[ti] == nil { firstSay[ti] = (along, line.kind, txt) }
                        if !line.far && nearSay[ti] == nil { nearSay[ti] = (along, line.kind, txt) }
                        if !sc.truth[ti].kinds.contains(line.kind) {
                            // "stairs or drop going down" for what is really one step down is the careful name, not a mistake
                            let careful = line.kind == .dropOff && sc.truth[ti].kinds.contains(.stepDown)
                            if careful { carefulSay.append(String(format: "careful name at %.1f m: «%@»", along, txt)) }
                            else { wrongSay.append(String(format: "WRONG NAME said at %.1f m: «%@»", along, txt)) }
                        }
                    } else {
                        falseSay.append(String(format: "FALSE LINE t=%.1f: «%@»", t, txt))
                    }
                }
            }
        }

        // walk on, stop in front of the first edge
        if !stopped {
            if let s = sc.stopAlong, let tr = sc.truth.first, alongTo(tr, walkerPos(walked)) <= s { stopped = true }
            else { walked += sc.speed * Float(dt) }
        }
        t += dt
    }

    var ok = falseSay.isEmpty && wrongSay.isEmpty
    for (ti, tr) in sc.truth.enumerated() {
        var line = "\(tr.label): "
        if let f = firstSure[ti] { line += String(format: "found at %.1f m as %@", f.along, f.kind.rawValue) } else { line += "NOT FOUND"; ok = false }
        if let f = firstSay[ti] { line += String(format: "; first said at %.1f m", f.along) } else if tr.mustSay { line += "; NEVER SAID"; ok = false }
        if sc.stopAlong != nil {
            if let n = nearSay[ti] { line += String(format: "; close warning at %.1f m «%@»", n.along, n.text) }
            else { line += "; NO CLOSE WARNING"; ok = false }
        }
        notes.append(line)
    }
    notes += wrongSay + falseSay + carefulSay
    if !falseNotes.isEmpty { notes.append("(map only) " + falseNotes.prefix(3).joined(separator: " | ") + (falseNotes.count > 3 ? " (+\(falseNotes.count - 3) more)" : "")) }
    if verbose || !ok { notes += said.map { "   " + $0 } }
    if verbose { notes += trace }
    return Result(name: sc.name, ok: ok, notes: notes)
}

// MARK: - main

let args = CommandLine.arguments
let seeds = Int(args.first(where: { $0.hasPrefix("--seeds=") })?.dropFirst(8) ?? "") ?? 3
let strength = Float(args.first(where: { $0.hasPrefix("--noise=") })?.dropFirst(8) ?? "") ?? 1
let only = args.first(where: { $0.hasPrefix("--only=") }).map { String($0.dropFirst(7)) }
let verbose = args.contains("--verbose")
let seedBase = Int(args.first(where: { $0.hasPrefix("--seedbase=") })?.dropFirst(11) ?? "") ?? 0
var debugFalse = args.contains("--debug") ? 40 : 0
let debugFrom = Double(args.first(where: { $0.hasPrefix("--from=") })?.dropFirst(7) ?? "") ?? 0

let all = scenes().filter { only == nil || $0.name.lowercased().contains(only!.lowercased()) }
var jobs: [(Int, Int)] = []
for si in all.indices { for k in 0..<seeds { jobs.append((si, k)) } }
var results = [Result?](repeating: nil, count: jobs.count)
let lock = NSLock()
DispatchQueue.concurrentPerform(iterations: jobs.count) { n in
    let (si, k) = jobs[n]
    let sc = scenes().filter { only == nil || $0.name.lowercased().contains(only!.lowercased()) }[si]
    let r = run(sc, seed: UInt64(1000 + (k + seedBase) * 77), noiseStrength: strength, verbose: verbose)
    lock.lock(); results[n] = r; lock.unlock()
}
var pass = 0
for (n, r) in results.enumerated() {
    guard let r else { continue }
    if r.ok { pass += 1 }
    print((r.ok ? "PASS " : "FAIL ") + r.name + "  [seed \(jobs[n].1)]")
    for line in r.notes { print("    " + line) }
}
print("\n\(pass)/\(jobs.count) runs passed (noise x\(strength))")
