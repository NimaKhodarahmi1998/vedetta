import Foundation
import simd

// The floor reader: steps, stairs and drop-offs, out to 30 m, anywhere in the picture.
//
// Every depth picture is read column by column, from the bottom of the picture (near) to the top (far),
// like a cane sweeping forward: flat stretches of floor, and what happens between them. A riser between
// two flat stretches is a step up; a lower stretch that appears behind a hidden strip is a step down
// (the edge hides what's right behind it); a surface climbing at 20-50 degrees is a staircase seen from
// far away, where single treads are too small to see. Neighbouring columns must agree on a straight
// edge at least 45 cm wide, and an edge must be seen in more than one picture before it is said.
// Found edges are kept where they are in the world, so a step stays known after it drops out of the
// picture, right in front of the feet.
//
// Pure maths (Foundation + simd): the same code runs in the app and in the Mac simulation (tools/steps-sim).

// MARK: - Camera maths without ARKit (the same formulas as CamSnap)

nonisolated struct StepCam {
    var transform: simd_float4x4
    var inverse: simd_float4x4
    var intrinsics: simd_float3x3
    /// Sensor picture size in pixels (landscape).
    var width: Float
    var height: Float

    init(transform: simd_float4x4, intrinsics: simd_float3x3, width: Float, height: Float) {
        self.transform = transform
        self.inverse = transform.inverse
        self.intrinsics = intrinsics
        self.width = width
        self.height = height
    }

    var position: SIMD3<Float> { SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z) }
    var forward: SIMD3<Float> { -SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z) }

    /// Sensor pixel -> world ray direction.
    func ray(u: Float, v: Float) -> SIMD3<Float> {
        let x = (u - intrinsics[2][0]) / intrinsics[0][0]
        let y = (v - intrinsics[2][1]) / intrinsics[1][1]
        let d = transform * SIMD4<Float>(x, -y, -1, 0)
        return simd_normalize(SIMD3(d.x, d.y, d.z))
    }

    /// World point -> sensor pixel (nil if behind the camera).
    func project(_ p: SIMD3<Float>) -> SIMD2<Float>? {
        let c = inverse * SIMD4<Float>(p.x, p.y, p.z, 1)
        if c.z > -0.15 { return nil }
        let x = c.x / -c.z, y = -c.y / -c.z
        return SIMD2(intrinsics[0][0] * x + intrinsics[2][0], intrinsics[1][1] * y + intrinsics[2][1])
    }

    /// Upright (portrait) picture, normalized, top-left origin -> sensor pixel.
    /// Sensor x = upright y; sensor y = 1 - upright x (the phone is held upright).
    func sensor(xu: Float, yu: Float) -> SIMD2<Float> { SIMD2(yu * width, (1 - xu) * height) }

    /// Sensor pixel -> upright normalized (x, y).
    func upright(_ s: SIMD2<Float>) -> SIMD2<Float> { SIMD2(1 - s.y / height, s.x / width) }
}

// MARK: - Which part of the picture a depth run sees

/// A horizontal band of the upright picture (normalized): top y0, height h. The depth model sees only this band.
nonisolated struct DepthBand: Equatable {
    var y0: Float
    var h: Float

    /// The floor reader's own band: it starts just above the horizon and goes down, so the floor from a couple of
    /// metres out to the horizon is in it whatever the tilt of the phone. nil when the picture shows no floor.
    static func floor(cam: StepCam, h: Float) -> DepthBand? {
        func down(_ yu: Float) -> Float { cam.ray(u: yu * cam.width, v: 0.5 * cam.height).y }
        guard down(1) < -0.03 else { return nil }
        var lo: Float = 0, hi: Float = 1
        if down(0) <= 0 {
            hi = 0                                           // the horizon is above the picture
        } else {
            for _ in 0..<16 { let m = (lo + hi) / 2; if down(m) > 0 { lo = m } else { hi = m } }
        }
        return DepthBand(y0: max(0, min(1 - h, hi - 0.05)), h: h)
    }
}

/// One depth picture for the floor reader: the model's relative output, its metric fit (1/z = s * rel + t)
/// and where the band sits in the picture.
nonisolated struct DepthGrid {
    let rel: [Float]
    let W: Int
    let H: Int
    let band: DepthBand
    let s: Float
    let t: Float

    /// Metres along the camera axis, or nil beyond 60 m (sky, far facades).
    @inline(__always) func metric(_ i: Int, _ j: Int) -> Float? {
        let inv = s * rel[j * W + i] + t
        guard inv > 1.0 / 60.0 else { return nil }
        return max(0.2, 1 / inv)
    }

    /// Model pixel centre -> sensor pixel.
    @inline(__always) func sensor(_ i: Int, _ j: Int, _ cam: StepCam) -> SIMD2<Float> {
        let xu = (Float(i) + 0.5) / Float(W)
        let yu = band.y0 + (Float(j) + 0.5) / Float(H) * band.h
        return cam.sensor(xu: xu, yu: yu)
    }

    /// Sensor pixel -> model pixel, if it falls inside the band.
    func index(_ uv: SIMD2<Float>, _ cam: StepCam) -> (i: Int, j: Int)? {
        let up = cam.upright(uv)
        let j = Int(floor((up.y - band.y0) / band.h * Float(H))), i = Int(floor(up.x * Float(W)))
        guard i >= 0, i < W, j >= 0, j < H else { return nil }
        return (i, j)
    }

    /// Angle between two neighbouring model rows (radians).
    func rowAngle(_ cam: StepCam) -> Float { band.h * cam.width / Float(H) / cam.intrinsics[0][0] }
}

/// Pairs (model output, metres) to fit the metric scale of a depth picture.
nonisolated enum DepthPairs {
    /// ARKit feature points that fall inside the band. z is the depth along the camera axis.
    static func fromPoints(_ pts: [SIMD3<Float>], rel: [Float], W: Int, H: Int, band: DepthBand,
                           cam: StepCam, maxZ: Float = 18) -> [(rel: Float, z: Float)] {
        let g = DepthGrid(rel: rel, W: W, H: H, band: band, s: 0, t: 0)
        var out: [(rel: Float, z: Float)] = []
        out.reserveCapacity(min(pts.count, 600))
        for p in pts {
            let pc = cam.inverse * SIMD4<Float>(p.x, p.y, p.z, 1)
            let z = -pc.z
            guard z > 0.3, z < maxZ, let uv = cam.project(p), let ij = g.index(uv, cam) else { continue }
            out.append((rel[ij.j * W + ij.i], z))
            if out.count >= 600 { break }
        }
        return out
    }

    /// Where few feature points exist (dark, plain floors): the floor right in front of the walker, from the
    /// known floor height. Only the lowest quarter of the band (the nearest floor) and only up to 6 m.
    static func fromFloor(rel: [Float], W: Int, H: Int, band: DepthBand, cam: StepCam, ground: Float) -> [(rel: Float, z: Float)] {
        let g = DepthGrid(rel: rel, W: W, H: H, band: band, s: 0, t: 0)
        let C = cam.position, F = cam.forward
        var out: [(rel: Float, z: Float)] = []
        var j = H - 4
        while j > H * 3 / 4 {
            var i = 6
            while i < W - 6 {
                let uv = g.sensor(i, j, cam)
                let d = cam.ray(u: uv.x, v: uv.y)
                if d.y < -0.05 {
                    let len = (ground - C.y) / d.y
                    let z = len * simd_dot(d, F)
                    if len > 0.8 && len < 6 && z > 0.5 { out.append((rel[j * W + i], z)) }
                }
                i += 24
            }
            j -= 6
        }
        return out
    }
}

// MARK: - One column of a depth picture

nonisolated struct ColSample {
    var r: Float              // horizontal distance from the camera (m)
    var h: Float              // height above the walker's floor (m)
    var p: SIMD2<Float>       // world x, z
    var row: Int
}

/// What one column says about the floor.
nonisolated struct ColEvent {
    var up: Bool
    var edge: SIMD2<Float>    // world x, z: the foot of the riser (up) or the nosing (down)
    var r: Float              // distance from the camera
    var rise: Float           // per step: + up, - down. For a drop-off: the whole drop.
    var steps: Int            // 1 = one step, 2+ = stairs
    var drop: Bool            // more than 40 cm down, treads not seen
    var run: Float            // stairs: horizontal length covered
    var base: Float           // floor height before the edge
    var col: Int
}

/// A flat stretch of floor along a column (level, or a gentle slope such as a ramp).
nonisolated private struct Region {
    var a: Int, b: Int
    var n = 0
    var sr: Float = 0, sh: Float = 0, srr: Float = 0, srh: Float = 0
    var r0: Float = .greatestFiniteMagnitude, r1: Float = -.greatestFiniteMagnitude
    var firstP = SIMD2<Float>(0, 0), lastP = SIMD2<Float>(0, 0)
    var firstR: Float = 0, lastR: Float = 0
    var firstRow = 0, lastRow = 0
    var hMin: Float = .greatestFiniteMagnitude, hMax: Float = -.greatestFiniteMagnitude

    init(_ s: ColSample, _ k: Int) {
        a = k; b = k
        add(s, k)
        firstP = s.p; firstR = s.r; firstRow = s.row
    }

    mutating func add(_ s: ColSample, _ k: Int) {
        n += 1; b = k
        sr += s.r; sh += s.h; srr += s.r * s.r; srh += s.r * s.h
        r0 = min(r0, s.r); r1 = max(r1, s.r)
        hMin = min(hMin, s.h); hMax = max(hMax, s.h)
        lastP = s.p; lastR = s.r; lastRow = s.row
    }

    var span: Float { r1 - r0 }
    var mean: Float { sh / Float(n) }

    /// h = c0 + c1 * r. Level (mean) until the stretch is 0.5 m long; a gentle slope after that.
    var line: (c0: Float, c1: Float) {
        let nn = Float(n)
        guard span >= 0.5 else { return (mean, 0) }
        let den = nn * srr - sr * sr
        guard abs(den) > 1e-6 else { return (mean, 0) }
        let c1 = max(-0.16, min(0.16, (nn * srh - sr * sh) / den))
        return ((sh - c1 * sr) / nn, c1)
    }

    func at(_ r: Float) -> Float { let l = line; return l.c0 + l.c1 * r }

    /// Would the stretch stay "flat" (slope under 16%) with this sample added?
    func staysFlat(with s: ColSample) -> Bool {
        let nr0 = min(r0, s.r), nr1 = max(r1, s.r)
        guard nr1 - nr0 >= 0.5 else { return true }
        let nn = Float(n + 1)
        let tsr = sr + s.r, tsh = sh + s.h, tsrr = srr + s.r * s.r, tsrh = srh + s.r * s.h
        let den = nn * tsrr - tsr * tsr
        guard abs(den) > 1e-6 else { return true }
        return abs((nn * tsrh - tsr * tsh) / den) <= 0.16
    }
}

nonisolated enum ColumnReader {
    /// Tuning. Heights in metres; r is the distance from the camera.
    static func tolerance(_ r: Float) -> Float { 0.035 + 0.0012 * r }
    static func minRise(_ r: Float) -> Float { 0.06 + 0.002 * r }
    /// How far a vertical riser may seem to lean, from depth noise alone.
    static func riserLean(_ r: Float) -> Float { 0.12 + 0.02 * r }
    /// Shortest flat stretch that counts as floor before or after an edge.
    static func minFlat(_ r: Float) -> Float { max(0.15, 0.025 * r) }
    /// Tallest single step up (taller: a ledge, a bench, a wall) and deepest single step down (deeper: a drop-off).
    static let maxStepUp: Float = 0.30
    static let maxStep: Float = 0.40

    /// Back-projects every `colStride`-th column of the depth picture, from the bottom (near) to the top (far).
    static func columns(_ g: DepthGrid, cam: StepCam, ground: Float, maxRange: Float, colStride: Int = 4,
                        lit: ((SIMD2<Float>) -> Bool)? = nil) -> [[ColSample]] {
        let C = cam.position, F = cam.forward
        var out: [[ColSample]] = []
        out.reserveCapacity(g.W / colStride + 1)
        var i = colStride / 2
        while i < g.W {
            var col: [ColSample] = []
            col.reserveCapacity(g.H)
            var j = g.H - 1
            while j >= 0 {
                let jj = j
                j -= 1
                guard let z = g.metric(i, jj) else { continue }
                let uv = g.sensor(i, jj, cam)
                if let lit, !lit(uv) { continue }
                let dir = cam.ray(u: uv.x, v: uv.y)
                let along = simd_dot(dir, F)
                guard along > 0.05 else { continue }
                let P = C + dir * (z / along)
                let dx = P.x - C.x, dz = P.z - C.z
                let r = (dx * dx + dz * dz).squareRoot()
                let h = P.y - ground
                guard r <= maxRange + 6, h > -4, h < 4 else { continue }
                col.append(ColSample(r: r, h: h, p: SIMD2(P.x, P.z), row: jj))
            }
            out.append(col)
            i += colStride
        }
        return out
    }

    /// How far apart two samples `rows` model rows apart would be on a continuous floor at distance r.
    @inline(__always) static func floorSpacing(rows: Int, r: Float, hc: Float, rowAngle: Float) -> Float {
        (r * r + hc * hc) / hc * rowAngle * Float(max(1, rows))
    }

    /// A break in the surface between two neighbouring samples: something hides what's behind (a jump outwards
    /// much bigger than a continuous floor would give), or a nearer surface starts (a jump back).
    @inline(__always) static func isJump(_ a: ColSample, _ b: ColSample, rowAngle: Float, camY: Float, ground: Float) -> Bool {
        let dr = b.r - a.r
        let hc = max(0.3, camY - (ground + a.h))
        let expect = floorSpacing(rows: abs(a.row - b.row), r: a.r, hc: hc, rowAngle: rowAngle)
        let jitter = 0.02 * max(a.r, b.r)
        return dr > 2.5 * expect + 0.3 + 2 * jitter || dr < -(0.3 + 2 * jitter)
    }

    /// Flat stretches along one column (near to far). Single stray samples (edge blur, noise) are skipped.
    /// A stretch only counts if its samples spread out like a floor's do: points on a wall or a person
    /// (all at about the same distance) never make a "flat stretch", however level they happen to be.
    private static func regions(_ s: [ColSample], rowAngle: Float, camY: Float, ground: Float) -> [Region] {
        var out: [Region] = []
        guard s.count >= 3 else { return out }
        func keep(_ R: Region) {
            guard R.n >= 3 else { return }
            let hc = max(0.3, camY - (ground + R.mean))
            let expect = floorSpacing(rows: abs(R.firstRow - R.lastRow), r: R.r0, hc: hc, rowAngle: rowAngle)
            guard R.span >= max(0.08, 0.45 * expect) else { return }
            // a short stretch must be truly level: a wall seen almost edge-on climbs a few cm per row
            if R.span < 0.5 && R.hMax - R.hMin > max(0.04, 0.6 * tolerance(R.r0) + 0.16 * R.span) { return }
            out.append(R)
        }
        var cur = Region(s[0], 0)
        var k = 1
        while k < s.count {
            let x = s[k]
            let jump = isJump(s[k - 1], x, rowAngle: rowAngle, camY: camY, ground: ground)
            if !jump, abs(x.h - cur.at(x.r)) <= tolerance(x.r), cur.staysFlat(with: x) {
                cur.add(x, k); k += 1; continue
            }
            if k + 1 < s.count {
                let y = s[k + 1]
                if !isJump(s[k - 1], y, rowAngle: rowAngle, camY: camY, ground: ground),
                   abs(y.h - cur.at(y.r)) <= tolerance(y.r), cur.staysFlat(with: y) {
                    k += 1; continue                                  // skip the stray sample
                }
            }
            keep(cur)
            cur = Region(x, k)
            k += 1
        }
        keep(cur)
        return out
    }

    /// The floor level at the far end of a stretch (median of its last 0.5 m) and where that is.
    private static func endLevel(_ R: Region, _ s: [ColSample]) -> (h: Float, r: Float) {
        var hs: [Float] = [], rs: Float = 0
        var k = R.b
        while k >= R.a && (hs.count < 3 || R.lastR - s[k].r <= 0.5) {
            if abs(s[k].h - R.at(s[k].r)) <= tolerance(s[k].r) { hs.append(s[k].h); rs += s[k].r }
            k -= 1
        }
        guard !hs.isEmpty else { return (R.mean, R.lastR) }
        hs.sort()
        return (hs[hs.count / 2], rs / Float(hs.count))
    }

    /// The floor level at the near end of a stretch (median of its first 0.5 m) and where that is.
    private static func startLevel(_ R: Region, _ s: [ColSample]) -> (h: Float, r: Float) {
        var hs: [Float] = [], rs: Float = 0
        var k = R.a
        while k <= R.b && (hs.count < 3 || s[k].r - R.firstR <= 0.5) {
            if abs(s[k].h - R.at(s[k].r)) <= tolerance(s[k].r) { hs.append(s[k].h); rs += s[k].r }
            k += 1
        }
        guard !hs.isEmpty else { return (R.mean, R.firstR) }
        hs.sort()
        return (hs[hs.count / 2], rs / Float(hs.count))
    }

    /// Horizontal distance over which the middle half of a rise happens (25% to 75% of it), signed:
    /// positive when the surface climbs away from the viewer (stairs), about 0 for a vertical face.
    private static func riseRun(_ s: [ColSample], from: Int, to: Int, h0: Float, d: Float) -> Float {
        let lo = max(0, from), hi = min(s.count - 1, to)
        guard lo < hi else { return 0 }
        var r25: Float? = nil, r75: Float? = nil
        for k in lo...hi {
            if r25 == nil && s[k].h >= h0 + 0.25 * d { r25 = s[k].r }
            if r25 != nil && s[k].h >= h0 + 0.75 * d { r75 = s[k].r; break }
        }
        guard let a = r25, let b = r75 else { return 99 }
        return b - a
    }

    /// Everything one column says: steps up and down, stairs, drop-offs.
    static func events(_ s: [ColSample], col: Int, rowAngle: Float, camY: Float, ground: Float) -> [ColEvent] {
        let regs = regions(s, rowAngle: rowAngle, camY: camY, ground: ground)
        guard !regs.isEmpty else { return [] }
        struct Raw { var e: ColEvent; var from: Int }               // from = index of the stretch before the edge
        var raw: [Raw] = []
        var objectTop = Set<Int>()                                    // top of a low object: not floor

        for idx in 0..<regs.count where !objectTop.contains(idx) {
            let A = regs[idx]
            let ea = endLevel(A, s)
            let hA = ea.h, rA = ea.r
            guard abs(hA) < 1.2, A.span >= minFlat(rA) else { continue }  // only edges at the end of real floor
            let hc = max(0.3, camY - (ground + hA))

            guard idx + 1 < regs.count else {
                // nothing flat after A: a staircase rising to the end of the column, or the floor ends in a drop
                let tail = Array(s[(A.b + 1)...].prefix(80))
                if let e = risingTail(tail, from: A, hA: hA, col: col) { raw.append(Raw(e: e, from: idx)) }
                else if let e = dropTail(tail, from: A, hA: hA, hc: hc, col: col, rowAngle: rowAngle) { raw.append(Raw(e: e, from: idx)) }
                continue
            }
            let B = regs[idx + 1]
            let sb = startLevel(B, s)
            let c1 = A.span >= 1.0 ? A.line.c1 : 0                   // a ramp or a sloping street carries on
            let d = sb.h - (hA + c1 * (sb.r - rA))
            let span = B.firstR - A.lastR

            if d > 0 {
                guard d >= minRise(rA) else { continue }
                if d <= maxStepUp {
                    guard B.span >= minFlat(sb.r) else { continue }
                    // The riser stands where the lower floor ends: the upper floor starts right there, not behind a
                    // hidden stretch (a farther floor seen across a gap is not a step up).
                    let gap = span - floorSpacing(rows: abs(A.lastRow - B.firstRow), r: rA, hc: hc, rowAngle: rowAngle)
                    guard gap <= 0.3 + 0.03 * rA else { continue }
                    // A riser is vertical: the rise happens at one distance (within depth noise).
                    // Smooth bumps of a noisy depth picture rise over a metre or more: not a step.
                    let run = riseRun(s, from: A.b - 2, to: B.a + 2, h0: hA, d: d)
                    let vertical = abs(run) <= riserLean(rA)
                    let stairsLike = d >= 0.2 && run > 0 && 0.5 * d / run >= 0.3
                    guard vertical || stairsLike else { continue }
                    // A low object (box, planter) is up and straight back down: not a step
                    if idx + 2 < regs.count, B.span < 1.5 {
                        let C = regs[idx + 2]
                        if abs(startLevel(C, s).h - hA) < max(0.05, 0.35 * d) { objectTop.insert(idx + 1); continue }
                    }
                    let mid = (A.lastP + B.firstP) * 0.5
                    let two = (stairsLike && !vertical) || (d > 0.26 && span > 0.22)    // two risers seen as one
                    raw.append(Raw(e: ColEvent(up: true, edge: mid, r: rA, rise: two ? d / 2 : d,
                                               steps: two ? 2 : 1, drop: false, run: two ? max(span, run) : 0, base: hA, col: col), from: idx))
                } else if d > maxStep {
                    // too tall for one step: a staircase if it climbs like one (20-50 degrees), else a wall or an object.
                    // The climb's length comes from the samples on it, not from the next floor sample (far away,
                    // floor samples are a metre apart); depth noise can make a vertical face lean a little.
                    let half = riseRun(s, from: A.b - 2, to: B.a + 2, h0: hA, d: d)
                    let run = 2 * half - riserLean(rA)
                    let slope = d / max(run, 0.01)
                    if half > 0 && run >= 0.4 && run <= 6 && d <= 3.5 && slope >= 0.35 && slope <= 1.3 {
                        raw.append(Raw(e: ColEvent(up: true, edge: A.lastP, r: rA, rise: 0.17, steps: max(2, Int((d / 0.17).rounded())),
                                                   drop: false, run: run, base: hA, col: col), from: idx))
                    }
                }
            } else {
                guard -d >= minRise(rA), B.span >= minFlat(sb.r) else { continue }
                // the far side of a low object (A is its top, short, and B is back at the floor before it)
                if A.span < 1.5 {
                    let hP = idx >= 1 ? endLevel(regs[idx - 1], s).h : 0      // no floor seen before it: the walker's own
                    if hA - hP >= minRise(rA) && abs(sb.h - hP) < max(0.05, 0.35 * -d) { continue }
                }
                // a downhill slope seen over its crest is one continuous surface: not a step
                if B.span >= 1.0 && B.line.c1 < -0.04 && abs(B.at(A.lastR) - hA) < minRise(rA) { continue }
                // The edge hides a strip right behind it: the lower floor must start farther away than a
                // continuous floor would, by about that strip. A few blurred samples in between are allowed.
                let hidden = -d * rA / hc
                let expect = floorSpacing(rows: abs(A.lastRow - B.firstRow), r: rA, hc: hc, rowAngle: rowAngle)
                guard span - expect >= 0.4 * hidden - (0.1 + 0.02 * rA), B.a - A.b - 1 <= 8 else { continue }
                // The hidden strip grows with the depth of the drop. Far away, blur makes the lower floor look
                // higher than it is, so the strip's width (when it says deeper) wins.
                let fromStrip = -max(0, span - expect) * hc / rA
                let dd = min(d, 0.8 * fromStrip)
                // "One step down" only with a long stretch of lower floor seen beyond it; else it may be deeper
                let lowFloor = B.span >= max(0.5, 0.06 * sb.r)
                raw.append(Raw(e: ColEvent(up: false, edge: A.lastP, r: rA, rise: dd, steps: 1, drop: -dd > maxStep || !lowFloor,
                                           run: 0, base: hA, col: col), from: idx))
            }
        }

        // Steps in a row along the column, with tread-sized gaps between them: stairs.
        var out: [ColEvent] = []
        var i = 0
        while i < raw.count {
            var e = raw[i].e
            var j = i
            while j + 1 < raw.count {
                let nx = raw[j + 1]
                let cur = raw[j]
                guard nx.from == cur.from + 1, nx.e.up == e.up, !nx.e.drop, !cur.e.drop else { break }
                let tread = simd_distance(nx.e.edge, cur.e.edge)
                let ratio = abs(nx.e.rise) / max(0.01, abs(cur.e.rise))
                guard tread >= 0.15, tread <= 0.65, ratio >= 0.55, ratio <= 1.8 else { break }
                e.steps += nx.e.steps
                e.run += tread
                e.rise = (e.rise + nx.e.rise) / 2
                j += 1
            }
            out.append(e)
            i = j + 1
        }
        return out
    }

    /// A surface climbing at a staircase's angle after a flat floor, up to the end of the column.
    private static func risingTail(_ all: [ColSample], from A: Region, hA: Float, col: Int) -> ColEvent? {
        let tail = Array(all.prefix { $0.r <= A.lastR + 6 })      // a flight of stairs, not the building behind
        guard tail.count >= 3 else { return nil }
        var top = tail[0]
        var maxH = tail[0].h
        for x in tail where x.h > maxH { maxH = x.h; top = x }
        let d = maxH - hA
        guard d >= 0.3, d <= 3.5 else { return nil }
        // the climb must be steady: most samples rise from the one before
        var ups = 0, n = 0
        for k in 1..<tail.count where tail[k].r <= top.r + 0.5 {
            n += 1
            if tail[k].h >= tail[k - 1].h - 0.03 { ups += 1 }
        }
        guard n >= 2, Float(ups) >= 0.7 * Float(n) else { return nil }
        // the climb's length from its middle half (a vertical face climbs at one distance)
        let half = riseRun(tail, from: 0, to: tail.count - 1, h0: hA, d: d)
        let run = 2 * half - riserLean(A.lastR)
        let slope = d / max(run, 0.01)
        guard half > 0, run >= 0.4, slope >= 0.35, slope <= 1.3 else { return nil }
        return ColEvent(up: true, edge: A.lastP, r: A.lastR, rise: 0.17, steps: max(2, Int((d / 0.17).rounded())),
                        drop: false, run: run, base: hA, col: col)
    }

    /// The floor ends, and what is seen next, behind the hidden strip, is far below it (stairs going down
    /// seen from far, a ledge): the drop is at least that much, even when no flat floor is visible down there.
    private static func dropTail(_ tail: [ColSample], from A: Region, hA: Float, hc: Float, col: Int, rowAngle: Float) -> ColEvent? {
        guard tail.count >= 3 else { return nil }
        let first = tail.prefix(4).map { $0.h }.sorted()
        let low = first[first.count / 2]
        let d = low - hA
        guard d < -maxStep else { return nil }
        let rNext = tail.prefix(4).map { $0.r }.min() ?? A.lastR
        let hidden = -d * A.lastR / hc
        guard rNext - A.lastR >= 0.4 * hidden - (0.1 + 0.02 * A.lastR) else { return nil }
        return ColEvent(up: false, edge: A.lastP, r: A.lastR, rise: d, steps: 1, drop: true, run: 0, base: hA, col: col)
    }
}

// MARK: - One picture: column events grouped into straight edges

/// An edge found in one depth picture.
nonisolated struct StepObservation {
    var kind: FloorKind
    var center: SIMD2<Float>
    var dir: SIMD2<Float>      // along the edge (unit)
    var width: Float
    var rise: Float
    var steps: Int
    var run: Float
    var r: Float               // distance from the camera
    var support: Int           // columns that saw it
    var level: Float           // floor height before the edge (relative to the walker's floor)
}

nonisolated enum EdgeGrouper {
    static func group(_ events: [ColEvent], camXZ: SIMD2<Float>) -> [StepObservation] {
        var clusters: [[ColEvent]] = []
        for e in events.sorted(by: { $0.col < $1.col }) {
            var best = -1
            var bestD = Float.greatestFiniteMagnitude
            for (ci, c) in clusters.enumerated() {
                guard let last = c.last, last.up == e.up, e.col > last.col, e.col - last.col <= 12 else { continue }
                let d = simd_distance(last.edge, e.edge)
                if d <= 0.35 + 0.04 * e.r && d < bestD { bestD = d; best = ci }
            }
            if best >= 0 { clusters[best].append(e) } else { clusters.append([e]) }
        }

        var out: [StepObservation] = []
        for c in clusters where c.count >= 3 {
            let cols = (c.last!.col - c.first!.col) / 4 + 1          // columns are 4 model pixels apart
            guard Float(c.count) >= 0.4 * Float(cols) else { continue }
            // straight line through the edge points
            var m = SIMD2<Float>(0, 0)
            for e in c { m += e.edge }
            m /= Float(c.count)
            var sxx: Float = 0, sxy: Float = 0, syy: Float = 0
            for e in c { let d = e.edge - m; sxx += d.x * d.x; sxy += d.x * d.y; syy += d.y * d.y }
            let ang = 0.5 * atan2(2 * sxy, sxx - syy)
            let dir = SIMD2<Float>(cos(ang), sin(ang))
            let nrm = SIMD2<Float>(-dir.y, dir.x)
            var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude, res: Float = 0
            for e in c {
                let d = e.edge - m
                let a = simd_dot(d, dir), p = simd_dot(d, nrm)
                lo = min(lo, a); hi = max(hi, a); res += p * p
            }
            let width = hi - lo
            let r = simd_distance(m, camXZ)
            let rms = (res / Float(c.count)).squareRoot()
            guard width >= 0.6, c.count >= (r < 15 ? 4 : 3), rms <= 0.10 + 0.012 * r else { continue }

            let rises = c.map { $0.rise }.sorted()
            let rise = rises[rises.count / 2]
            let multi = c.filter { $0.steps >= 2 }.count
            let steps = c.map { $0.steps }.sorted()[c.count / 2]
            let run = c.map { $0.run }.sorted()[c.count / 2]
            let level = c.map { $0.base }.sorted()[c.count / 2]
            let up = c[0].up
            let stairs = Float(multi) >= max(2, 0.3 * Float(c.count))
            let kind: FloorKind
            if up {
                kind = stairs ? .stairsUp : .stepUp
            } else if stairs {
                kind = .stairsDown
            } else {
                let drops = c.filter { $0.drop }.count
                kind = drops * 2 > c.count ? .dropOff : .stepDown
            }
            // the edge's middle, between the outermost columns that saw it
            let center = m + dir * ((lo + hi) / 2)
            out.append(StepObservation(kind: kind, center: center, dir: dir, width: width, rise: rise,
                                       steps: max(1, stairs ? max(2, steps) : 1), run: run, r: r,
                                       support: c.count, level: level))
        }
        return out
    }
}

// MARK: - Remembered edges

nonisolated final class StepFeature {
    let id: Int
    var kind: FloorKind
    var center: SIMD2<Float>
    var dir: SIMD2<Float>
    /// Across the edge, pointing away from where it was first seen: the direction of travel over it.
    var normal: SIMD2<Float>
    var width: Float
    var rise: Float
    var steps: Int
    var run: Float
    var level: Float
    var conf: Float = 0
    var hits = 0
    var weight: Float = 0
    /// The most precise single sighting so far (metres): many rough far sightings share the same errors,
    /// so together they can't place the edge better than half of this.
    var bestSigma: Float = 9
    var firstT: Double
    var lastT: Double
    var lastHitFrame = -1
    var votes: [FloorKind: Float] = [:]
    /// Sightings since the name last changed: a name is said from far only once it has held.
    var stableHits = 0
    // what has been said about it
    var saidFar = false
    var saidNear = false
    var saidFinal = false
    var saidKind: FloorKind? = nil

    init(id: Int, o: StepObservation, camXZ: SIMD2<Float>, t: Double) {
        self.id = id
        kind = o.kind; center = o.center; dir = o.dir; width = o.width
        rise = o.rise; steps = o.steps; run = o.run; level = o.level
        var n = SIMD2<Float>(-o.dir.y, o.dir.x)
        if simd_dot(o.center - camXZ, n) < 0 { n = -n }
        normal = n
        firstT = t; lastT = t
    }

    var isUp: Bool { kind == .stepUp || kind == .stairsUp }
    var confirmed: Bool { conf >= 0.6 && hits >= 3 }
    /// Once confirmed, it keeps shielding a staircase from the obstacle check until it is passed or forgotten.
    var wasConfirmed = false
    /// How far the step or stairs reach past the first edge, along the direction of travel.
    var extent: Float {
        switch kind {
        case .stairsUp, .stairsDown: return max(0.6, max(run, Float(steps) * 0.29))
        default: return 0.3
        }
    }
}

/// What the guide needs to know about one remembered edge, seen from where the walker is now.
nonisolated struct StepView {
    let f: StepFeature
    /// Straight-line distance to the nearest point of the edge.
    let dist: Float
    /// Distance along the walking direction to where the path crosses the edge (in path only).
    let along: Float?
    /// + = to the left of the walking direction (radians).
    let bearing: Float
    /// The walker is on it now (between the first edge and the far end).
    let onIt: Bool
    var inPath: Bool { along != nil }
    /// Distance to say: along the path if crossing it, else straight-line.
    var sayDistance: Float { along ?? dist }
}

nonisolated final class StepReader {
    static let maxRange: Float = 30
    static let halfFOV: Float = 35 * .pi / 180

    private(set) var features: [StepFeature] = []
    private var nextId = 1
    private var frame = 0

    func reset() { features.removeAll(); nextId = 1; frame = 0 }

    /// Reads one depth picture and merges what it finds into the remembered edges. Returns the edges found in it.
    @discardableResult
    func ingest(_ g: DepthGrid, cam: StepCam, ground: Float, t: Double,
                lit: ((SIMD2<Float>) -> Bool)? = nil) -> [StepObservation] {
        frame += 1
        // old sightings fade (about a second): the edge follows the newest, closest and most precise ones
        for f in features { f.weight *= 0.9 }
        let ra = g.rowAngle(cam)
        let camY = cam.position.y
        let camXZ = SIMD2(cam.position.x, cam.position.z)
        let cols = ColumnReader.columns(g, cam: cam, ground: ground, maxRange: StepReader.maxRange, colStride: 4, lit: lit)
        var events: [ColEvent] = []
        for (ci, col) in cols.enumerated() {
            events += ColumnReader.events(col, col: ci * 4 + 2, rowAngle: ra, camY: camY, ground: ground)
        }
        let obs = EdgeGrouper.group(events, camXZ: camXZ).filter { $0.r <= StepReader.maxRange + 2 }
        // Edges whose own spot is in this picture. One that isn't (right in front of the feet, below the picture)
        // must not be pushed away by what is seen beyond it: that would be its second or third riser.
        // "In view" means the floor just before the edge is in the picture: only then would a nearer first riser
        // have been seen.
        var inView = Set<Int>()
        for f in features {
            let before = f.center - f.normal * 0.4
            let p = SIMD3<Float>(before.x, ground + f.level, before.y)
            if let uv = cam.project(p), g.index(uv, cam) != nil, simd_distance(before, camXZ) > 1.0 { inView.insert(f.id) }
        }
        for o in obs { merge(o, camXZ: camXZ, t: t, inView: inView) }

        // Edges that should have been in this picture but weren't seen lose confidence.
        for f in features where f.lastHitFrame != frame {
            let p = SIMD3<Float>(f.center.x, ground + f.level, f.center.y)
            guard let uv = cam.project(p), g.index(uv, cam) != nil else { continue }
            if let lit, !lit(uv) { continue }
            let r = simd_distance(f.center, camXZ)
            // close by, the floor before an edge is below the picture: not seeing it there proves nothing
            guard r <= StepReader.maxRange, r > 2.5 else { continue }
            f.conf *= r < 8 ? 0.8 : 0.9
        }
        features.removeAll { $0.conf < 0.12 && $0.lastHitFrame != frame }
        return obs
    }

    /// How sure the position of a remembered edge is (metres, one sigma).
    private func sigma(_ f: StepFeature) -> Float { max(1 / max(1e-3, f.weight).squareRoot(), 0.5 * f.bestSigma) }

    private func merge(_ o: StepObservation, camXZ: SIMD2<Float>, t: Double, inView: Set<Int>) {
        let up = o.kind == .stepUp || o.kind == .stairsUp
        let sigmaO = 0.06 + 0.025 * o.r
        var best: StepFeature? = nil
        var bestD = Float.greatestFiniteMagnitude
        for f in features where f.isUp == up {
            let d = o.center - f.center
            let across = simd_dot(d, f.normal), along = abs(simd_dot(d, f.dir))
            let sf = sigma(f)
            // the gate grows with how unsure both positions are: an edge first seen roughly from 25 m is the
            // same edge when it is seen precisely from 5 m
            let gate = max(0.4, 2.5 * (sigmaO * sigmaO + sf * sf).squareRoot())
            let stairs = f.kind == .stairsUp || f.kind == .stairsDown
            // inside a staircase's footprint: its sides and its later risers belong to it
            let inFoot = stairs && across > -0.4 && across < f.extent + 0.6 && along <= f.width / 2 + 0.4
            let collinear = abs(simd_dot(o.dir, f.dir)) > 0.94                 // within 20 degrees
            guard (abs(across) <= gate && along <= (f.width + o.width) / 2 + (collinear ? 2.5 : max(0.6, gate))) || inFoot else { continue }
            let score = inFoot && across > 0 ? 0 : abs(across) / gate
            if score < bestD { bestD = score; best = f }
        }
        let q = max(0.2, min(0.6, 0.65 - 0.015 * o.r)) * min(1, Float(o.support) / 6)
        let so = 0.06 + 0.025 * o.r
        let w = 1 / (so * so)

        guard let f = best else {
            let f = StepFeature(id: nextId, o: o, camXZ: camXZ, t: t)
            nextId += 1
            f.conf = q; f.hits = 1; f.weight = w; f.bestSigma = so; f.lastHitFrame = frame
            f.votes[o.kind] = q
            features.append(f)
            return
        }

        let across = simd_dot(o.center - f.center, f.normal)
        // a staircase's side, seen at right angles to its edge, belongs to it but doesn't move the edge;
        // nor does anything beyond an edge whose own spot is out of the picture
        let sideways = (f.kind == .stairsUp || f.kind == .stairsDown) && abs(simd_dot(o.dir, f.dir)) < 0.7
        let beyondUnseen = !inView.contains(f.id) && across > 0.15
        if !sideways && !beyondUnseen {
            // position and direction, weighted by how precise each sighting is (near ones count much more)
            let sf = sigma(f)
            let k = w / (1 / (sf * sf) + w)
            // across the edge: weighted by precision; along it: the edge covers both pieces
            let a0 = simd_dot(o.center - f.center, f.dir)
            let lo = min(-f.width / 2, a0 - o.width / 2), hi = max(f.width / 2, a0 + o.width / 2)
            f.center += f.normal * (across * k) + f.dir * ((lo + hi) / 2)
            f.width = hi - lo
            let od = simd_dot(o.dir, f.dir) < 0 ? -o.dir : o.dir
            f.dir = simd_normalize(f.dir * (1 - k) + od * k)
            var n = SIMD2<Float>(-f.dir.y, f.dir.x)
            if simd_dot(n, f.normal) < 0 { n = -n }
            f.normal = n
            f.weight = min(f.weight + w, 400)
            f.rise += (o.rise - f.rise) * max(0.2, k)
            f.level += (o.level - f.level) * max(0.2, k)
        } else {
            f.run = max(f.run, across + max(0.28, o.run))
        }
        f.bestSigma = min(f.bestSigma, so)
        f.steps = max(f.steps, o.steps)
        f.run = max(f.run, o.run)
        if f.lastHitFrame != frame { f.hits += 1; f.conf = 1 - (1 - f.conf) * (1 - q) }
        f.lastHitFrame = frame
        f.lastT = t
        f.votes[o.kind, default: 0] += q
        let k = StepReader.decide(f.votes, up: up, rise: f.rise)
        if k != f.kind { f.kind = k; f.stableHits = 0 } else { f.stableHits += 1 }
    }

    /// Stairs win as soon as they're clearly seen; a big drop is a drop-off until treads are seen.
    static func decide(_ v: [FloorKind: Float], up: Bool, rise: Float) -> FloorKind {
        if up {
            return (v[.stairsUp] ?? 0) >= 0.45 * max(0.01, v[.stepUp] ?? 0) && (v[.stairsUp] ?? 0) > 0.3 ? .stairsUp : .stepUp
        }
        if (v[.stairsDown] ?? 0) > 0.3 { return .stairsDown }
        // "One step down" needs clear evidence (shallow, and seen as such most of the time). Otherwise the careful
        // name: stairs going down or a drop. Calling a drop a step is the dangerous mistake; the other way is not.
        if rise >= -0.30 && (v[.stepDown] ?? 0) > 1.5 * (v[.dropOff] ?? 0) { return .stepDown }
        return .dropOff
    }

    /// Forgets edges that are passed, far away, or old. Call a few times a second.
    func maintain(t: Double, walker: SIMD3<Float>, fwd: SIMD2<Float>) {
        let w = SIMD2(walker.x, walker.z)
        features.removeAll { f in
            let sd = simd_dot(w - f.center, f.normal)
            let lat = abs(simd_dot(w - f.center, f.dir))
            let passed = sd > f.extent + 0.8 && lat < f.width / 2 + 1.5
            return passed || simd_distance(w, f.center) > 40 || t - f.lastT > 90
        }
        // two remembered edges that turned out to be the same one
        var i = 0
        while i < features.count {
            var j = i + 1
            while j < features.count {
                let a = features[i], b = features[j]
                let d = b.center - a.center
                let gate = max(0.35, 2 * (sigma(a) * sigma(a) + sigma(b) * sigma(b)).squareRoot())
                let collinear = abs(simd_dot(a.dir, b.dir)) > 0.94
                if a.isUp == b.isUp && abs(simd_dot(d, a.normal)) < gate
                    && abs(simd_dot(d, a.dir)) < (a.width + b.width) / 2 + (collinear ? 2.5 : 0.3) {
                    let keep = a.weight >= b.weight ? a : b, drop = keep === a ? b : a
                    if collinear {
                        let a0 = simd_dot(drop.center - keep.center, keep.dir)
                        let lo = min(-keep.width / 2, a0 - drop.width / 2), hi = max(keep.width / 2, a0 + drop.width / 2)
                        keep.center += keep.dir * ((lo + hi) / 2)
                        keep.width = hi - lo
                    }
                    keep.saidFinal = keep.saidFinal || drop.saidFinal
                    keep.wasConfirmed = keep.wasConfirmed || drop.wasConfirmed
                    keep.conf = max(keep.conf, drop.conf); keep.hits = max(keep.hits, drop.hits)
                    keep.saidFar = keep.saidFar || drop.saidFar; keep.saidNear = keep.saidNear || drop.saidNear
                    for (k, v) in drop.votes { keep.votes[k, default: 0] += v }
                    keep.kind = StepReader.decide(keep.votes, up: keep.isUp, rise: keep.rise)
                    features.removeAll { $0 === drop }
                    if drop === a { i -= 1; break }
                } else {
                    j += 1
                }
            }
            i += 1
        }
    }

    /// Confirmed edges as the walker sees them now.
    func views(walker: SIMD3<Float>, fwd: SIMD2<Float>) -> [StepView] {
        let w = SIMD2(walker.x, walker.z)
        let left = SIMD2<Float>(fwd.y, -fwd.x)
        var out: [StepView] = []
        for f in features where f.confirmed || (f.wasConfirmed && f.conf >= 0.3) {
            f.wasConfirmed = true
            let half = f.width / 2
            let a = max(-half, min(half, simd_dot(w - f.center, f.dir)))
            let near = f.center + f.dir * a
            let rel = near - w
            let dist = simd_length(rel)
            let bearing = atan2(simd_dot(rel, left), simd_dot(rel, fwd))
            let sd = simd_dot(w - f.center, f.normal)
            let latNow = abs(simd_dot(w - f.center, f.dir))
            let onIt = sd > -0.25 && sd < f.extent + 0.3 && latNow < half + 0.3
            var along: Float? = nil
            let den = simd_dot(fwd, f.normal)
            if den > 0.3 {
                let s = simd_dot(f.center - w, f.normal) / den
                let q = w + fwd * s
                if s > -0.2 && abs(simd_dot(q - f.center, f.dir)) <= half + 0.45 { along = max(0, s) }
            }
            out.append(StepView(f: f, dist: dist, along: along, bearing: bearing, onIt: onIt))
        }
        return out
    }
}

nonisolated extension StepReader {
    /// Stairs or a step going up across the walking path, as a stretch along the path [from, to] (metres ahead).
    /// The obstacle check leaves this stretch alone: rising treads are a staircase, not an obstacle or a wall.
    /// Edges still being confirmed count too, so stairs are never first called an obstacle.
    func risingStretch(walker: SIMD3<Float>, fwd: SIMD2<Float>) -> (from: Float, to: Float)? {
        let w = SIMD2(walker.x, walker.z)
        var best: (from: Float, to: Float)? = nil
        for f in features where f.isUp && (f.conf >= 0.3 || f.wasConfirmed) {
            let den = simd_dot(fwd, f.normal)
            guard den > 0.3 else { continue }
            let s = simd_dot(f.center - w, f.normal) / den
            let q = w + fwd * s
            guard abs(simd_dot(q - f.center, f.dir)) <= f.width / 2 + 0.5, s > -f.extent - 0.5 else { continue }
            let stretch = (from: s - 0.4, to: s + f.extent / den + 1.6)
            if best == nil || stretch.from < best!.from { best = stretch }
        }
        return best
    }
}

// MARK: - What to say, and when

/// One line about the floor.
nonisolated struct StepLine {
    let id: Int
    let kind: FloorKind
    let distance: Float
    /// true = said early, in metres; false = the close warning, in paces.
    let far: Bool
    /// +1 left, -1 right, 0 ahead.
    let side: Int
    let urgent: Bool
}

/// Says each step or staircase once when it is first sure (in metres, with the side), again close by when
/// it is in the walking path (in paces), and once more right at the edge for anything going down.
nonisolated final class StepAnnouncer {
    static let nearFrom: Float = 3.5
    private var lastSay = -99.0
    /// Apple's classifier also sees stairs (GuidancePipeline+Scene.swift): far step lines may come sooner.
    var isStairsLikely = false

    private var recent: [(p: SIMD2<Float>, up: Bool, t: Double)] = []
    private var recentNear: [(p: SIMD2<Float>, up: Bool, t: Double)] = []

    func reset() { lastSay = -99; recent.removeAll(); recentNear.removeAll() }

    private func remember(_ v: StepView, _ t: Double) {
        recent.removeAll { t - $0.t > 30 }
        recent.append((v.f.center, v.f.isUp, t))
    }

    func next(_ views: [StepView], t: Double) -> StepLine? {
        // walked away and came back: the close warning may be said again
        for v in views where v.f.saidNear && (v.along ?? 99) > 6.5 { v.f.saidNear = false; v.f.saidFinal = false }
        let live = views.filter { !$0.onIt && $0.dist <= StepReader.maxRange }

        // 1. right at the edge of anything going down
        if let v = live.filter({ $0.inPath && !$0.f.isUp && !$0.f.saidFinal && $0.along! <= 0.9 }).min(by: { $0.along! < $1.along! }) {
            v.f.saidFinal = true; v.f.saidNear = true; v.f.saidFar = true; v.f.saidKind = v.f.kind
            lastSay = t
            return StepLine(id: v.f.id, kind: v.f.kind, distance: v.along!, far: false, side: 0, urgent: true)
        }
        // 2. close, in the walking path (or its name just changed, e.g. a drop-off turned out to be stairs)
        // (a close warning was just given for this same spot under another remembered edge: don't repeat it)
        for v in live where v.inPath && !v.f.saidNear
            && recentNear.contains(where: { $0.up == v.f.isUp && t - $0.t < 15 && simd_distance($0.p, v.f.center) < 1.2 }) {
            v.f.saidNear = true; v.f.saidFar = true; v.f.saidKind = v.f.kind
        }
        if let v = live.filter({ $0.inPath && $0.along! <= StepAnnouncer.nearFrom && (!$0.f.saidNear || $0.f.saidKind != $0.f.kind) })
            .min(by: { $0.along! < $1.along! }) {
            let urgent = !v.f.isUp || v.along! < 2.0
            if urgent || t - lastSay >= 1.5 {
                v.f.saidNear = true; v.f.saidFar = true; v.f.saidKind = v.f.kind
                lastSay = t
                remember(v, t)
                recentNear.removeAll { t - $0.t > 15 }
                recentNear.append((v.f.center, v.f.isUp, t))
                return StepLine(id: v.f.id, kind: v.f.kind, distance: v.along!, far: false, side: 0, urgent: urgent)
            }
        }
        // 3. the first time it is sure, in metres (or when its name changes before it is close)
        guard t - lastSay >= 2.5 else { return nil }
        // Steps up are said early from 6 m (closer, the close warning comes right after with a better view);
        // anything going down from 4 m.
        // From far, a name is said once it has held for two more sightings (five for anything going down,
        // whose depth takes a few looks to measure).
        let fresh = live.filter { v in
            abs(v.bearing) <= StepReader.halfFOV && v.sayDistance > (v.f.isUp ? 6 : 4)
                && v.f.stableHits >= (v.f.isUp ? (isStairsLikely ? 1 : 2) : (isStairsLikely ? 3 : 5))
                && (!v.f.saidFar || (v.f.saidKind != v.f.kind && !v.f.saidNear))
        }
        // the same place was just named (another edge of the same staircase, a side face): say it once
        for v in fresh where !v.f.saidFar && recent.contains(where: {
            $0.up == v.f.isUp && t - $0.t < 30 && simd_distance($0.p, v.f.center) < 3 + 0.15 * v.dist     // far = rough
        }) {
            v.f.saidFar = true; v.f.saidKind = v.f.kind
        }
        guard let v = fresh.filter({ !$0.f.saidFar || ($0.f.saidKind != $0.f.kind && !$0.f.saidNear) })
            .min(by: { ($0.inPath ? 0 : 1, $0.sayDistance) < ($1.inPath ? 0 : 1, $1.sayDistance) }) else { return nil }
        v.f.saidFar = true; v.f.saidKind = v.f.kind
        remember(v, t)
        lastSay = t
        let side = v.inPath || abs(v.bearing) < 0.21 ? 0 : (v.bearing > 0 ? 1 : -1)
        let urgent = v.inPath && !v.f.isUp && v.sayDistance < 8
        return StepLine(id: v.f.id, kind: v.f.kind, distance: v.sayDistance, far: true, side: side, urgent: urgent)
    }
}
