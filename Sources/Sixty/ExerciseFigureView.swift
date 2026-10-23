import AppKit
import SixtyCore
import SwiftUI

/// How a figure is painted. The defaults suit the dark lock screen.
struct FigureStyle {
    var ink = Color.white
    var accent = Palette.accent
    /// The background: eyes are cut out of the head in it, and held objects get a thin outline of it.
    /// nil leaves the head plain.
    var cutout: Color? = Palette.top
    var showsProps = true
    var showsTrails = true
    /// Multiplies the stroke widths: tiny figures need relatively thicker lines.
    var weight: CGFloat = 1
    /// Crops this fraction of the figure box on every side, so a figure without props fills a small view.
    var inset: CGFloat = 0

    static let lockScreen = FigureStyle()
    /// A small accent-coloured figure for the warning panel.
    static let badge = FigureStyle(
        ink: Palette.accent,
        cutout: nil,
        showsProps: false,
        showsTrails: false,
        weight: 1.5,
        inset: 0.06
    )
}

/// The exercise, demonstrated by a looping stick figure. With Reduce Motion it shows a still of the key pose.
struct ExerciseFigureView: View {
    let exerciseID: String
    var style: FigureStyle

    @State private var start: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The loop starts when the view appears. The screens of a break build their views together, so they agree.
    init(exerciseID: String, style: FigureStyle = .lockScreen) {
        self.exerciseID = exerciseID
        self.style = style
        _start = State(initialValue: Date())
    }

    var body: some View {
        if reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            FigureCanvas(frame: FigureAnimations.keyFrame(for: exerciseID), style: style)
        } else {
            // 30 fps is plenty for this motion and keeps two full-screen 6K displays cheap.
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                let time = timeline.date.timeIntervalSince(start)
                FigureCanvas(frame: FigureAnimations.frame(for: exerciseID, at: time), style: style)
            }
        }
    }
}

/// Draws one frame. The figure box is centred in the view and scaled to its shorter side.
struct FigureCanvas: View {
    let frame: FigureFrame
    var style = FigureStyle.lockScreen

    var body: some View {
        Canvas { context, size in
            FigurePainter(frame: frame, style: style, size: size).paint(in: context)
        }
        .accessibilityHidden(true)
    }
}

private struct FigurePainter {
    let frame: FigureFrame
    let style: FigureStyle
    let size: CGSize

    /// The size of the whole figure box, which may overflow the view when the style crops it.
    private var side: CGFloat { min(size.width, size.height) / (1 - 2 * style.inset) }
    private var limbWidth: CGFloat { side * 0.03 * style.weight }
    private var torsoWidth: CGFloat { side * 0.042 * style.weight }

    private func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (size.width - side) / 2 + p.x * side, y: (size.height - side) / 2 + (1 - p.y) * side)
    }

    private func stroke(_ width: CGFloat, dash: [CGFloat] = [], phase: CGFloat = 0) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash, dashPhase: phase)
    }

    private func polyline(_ points: [CGPoint], closed: Bool = false) -> Path {
        var path = Path()
        path.addLines(points.map(point))
        if closed { path.closeSubpath() }
        return path
    }

    /// A Catmull-Rom curve through the points: a straight spine stays straight, a curled one bends smoothly.
    private func smoothCurve(_ points: [CGPoint]) -> Path {
        let p = points.map(point)
        var path = Path()
        guard let first = p.first else { return path }
        path.move(to: first)
        for i in 0..<(p.count - 1) {
            let before = p[max(i - 1, 0)]
            let after = p[min(i + 2, p.count - 1)]
            let c1 = CGPoint(x: p[i].x + (p[i + 1].x - before.x) / 6, y: p[i].y + (p[i + 1].y - before.y) / 6)
            let c2 = CGPoint(x: p[i + 1].x - (after.x - p[i].x) / 6, y: p[i + 1].y - (after.y - p[i].y) / 6)
            path.addCurve(to: p[i + 1], control1: c1, control2: c2)
        }
        return path
    }

    func paint(in context: GraphicsContext) {
        let trails = style.showsTrails
        if style.showsProps { paintProps(in: context, inFront: false) }
        if trails, !frame.trailsInFront { paintTrails(in: context) }
        paintLimbs(in: context, behind: true)
        paintBody(in: context)
        paintLimbs(in: context, behind: false)
        if trails, frame.trailsInFront { paintTrails(in: context) }
        if style.showsProps { paintProps(in: context, inFront: true) }
    }

    private func paintProps(in context: GraphicsContext, inFront: Bool) {
        let props = frame.props.filter { $0.inFront == inFront && $0.opacity > 0.01 }
        // Held objects get a thin outline of the background first, so they do not melt into the body.
        if inFront, let cutout = style.cutout {
            for prop in props where prop.ink == .body {
                context.stroke(path(for: prop), with: .color(cutout), style: stroke(limbWidth * 1.3))
            }
        }
        for prop in props {
            let color: Color
            switch prop.ink {
            case .ground: color = style.ink.opacity(0.18)
            case .object: color = style.ink.opacity(0.4)
            case .body: color = style.ink
            case .accent: color = style.accent
            }
            let shading = GraphicsContext.Shading.color(color.opacity(prop.opacity))
            let width = limbWidth * (prop.ink == .body ? 0.6 : 0.55)
            let dash: [CGFloat] = prop.dash == nil ? [] : [side * 0.012, side * 0.02]
            let phase = CGFloat(prop.dash ?? 0) * side
            switch prop.shape {
            case .line, .loop:
                context.stroke(path(for: prop), with: shading, style: stroke(width, dash: dash, phase: phase))
            case .area, .dot:
                context.fill(path(for: prop), with: shading)
            }
        }
    }

    private func path(for prop: FigureProp) -> Path {
        switch prop.shape {
        case .line(let points):
            return polyline(points)
        case .loop(let points), .area(let points):
            return polyline(points, closed: true)
        case .dot(let center, let radius):
            let r = radius * side
            let c = point(center)
            return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
    }

    /// The recent path of the moving joints, fading out and thinning towards its tail. Butt caps keep the
    /// short segments from beading where they overlap.
    private func paintTrails(in context: GraphicsContext) {
        for trail in frame.trails where trail.count > 1 {
            let count = CGFloat(trail.count - 1)
            for index in 0..<(trail.count - 1) {
                let a = trail[index]
                let b = trail[index + 1]
                guard hypot(a.x - b.x, a.y - b.y) > 0.0005 else { continue }
                let age = CGFloat(index) / count
                var segment = stroke(limbWidth * (0.85 - 0.55 * age))
                segment.lineCap = index == 0 ? .round : .butt
                context.stroke(polyline([a, b]), with: .color(style.accent.opacity(0.6 * (1 - age))), style: segment)
            }
        }
    }

    private func paintLimbs(in context: GraphicsContext, behind: Bool) {
        let s = frame.skeleton
        for side in FigureSide.allCases {
            let legDepth = frame.legDepth[side]
            if (legDepth < 0) == behind {
                var path = polyline([s.hips[side], s.knees[side], s.ankles[side]])
                path.addPath(polyline([s.heels[side], s.toes[side]]))
                context.stroke(path, with: shading(depth: legDepth), style: stroke(limbWidth))
            }
            let armDepth = frame.armDepth[side]
            if (armDepth < 0) == behind {
                let path = polyline([s.shoulders[side], s.elbows[side], s.hands[side]])
                context.stroke(path, with: shading(depth: armDepth), style: stroke(limbWidth))
            }
        }
    }

    /// Limbs behind the torso are dimmed in proportion to how far behind they are.
    private func shading(depth: Double) -> GraphicsContext.Shading {
        .color(style.ink.opacity(1 + 0.5 * min(0, max(-1, depth))))
    }

    private func paintBody(in context: GraphicsContext) {
        let s = frame.skeleton
        let ink = GraphicsContext.Shading.color(style.ink)
        let spine = smoothCurve([s.pelvis, s.lowerBack, s.upperBack, s.neckBase])
        context.stroke(spine, with: ink, style: stroke(torsoWidth))
        var girdles = polyline([s.shoulders.right, s.neckBase, s.shoulders.left])
        girdles.addPath(polyline([s.hips.right, s.pelvis, s.hips.left]))
        girdles.addPath(polyline([s.neckBase, s.head]))
        context.stroke(girdles, with: ink, style: stroke(limbWidth))

        let r = FigureMetrics.headRadius * side
        let head = point(s.head)
        context.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: 2 * r, height: 2 * r)), with: ink)
        if let eyes = style.cutout {
            let e = FigureMetrics.eyeRadius * side
            for eye in frame.eyes.map(point) {
                let dot = Path(ellipseIn: CGRect(x: eye.x - e, y: eye.y - e, width: 2 * e, height: 2 * e))
                context.fill(dot, with: .color(eyes))
            }
        }
    }
}

// MARK: - Contact sheets

/// `Sixty --render-figures <dir>`: PNG contact sheets of every animation, to review them without waiting for a break.
@MainActor
enum FigureSheets {
    static func render(to path: String) -> Int32 {
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print("Cannot create \(path): \(error.localizedDescription)")
            return 1
        }
        var ok = true
        for exercise in Exercises.all {
            guard let animation = FigureAnimations.animation(for: exercise.id) else {
                print("\(exercise.id): no animation")
                ok = false
                continue
            }
            ok = write(ContactSheet(title: "\(exercise.id) — \(exercise.title)", animation: animation),
                       to: directory.appendingPathComponent("\(exercise.id).png")) && ok
        }
        ok = write(ContactSheet(title: "fallback (unknown id)", animation: FigureAnimations.fallback),
                   to: directory.appendingPathComponent("fallback.png")) && ok
        ok = write(KeyPoseSheet(), to: directory.appendingPathComponent("key-poses.png")) && ok
        ok = write(WarningSheet(), to: directory.appendingPathComponent("warning-panel.png"), scale: 2) && ok
        // The lock screen at the sizes the layout must suit; the emergency text field does not render here.
        let screens: [(name: String, size: CGSize, primary: Bool)] = [
            ("lock-13in", CGSize(width: 1512, height: 982), true),
            ("lock-6k", CGSize(width: 3008, height: 1692), true),
            ("lock-secondary", CGSize(width: 1512, height: 982), false),
        ]
        for screen in screens {
            let view = LockPreview(exercise: Exercises.all[0], isPrimary: screen.primary)
                .frame(width: screen.size.width, height: screen.size.height)
            ok = write(view, to: directory.appendingPathComponent("\(screen.name).png"), scale: 1) && ok
        }
        print("Contact sheets written to \(directory.path)")
        return ok ? 0 : 1
    }

    private static func write(_ view: some View, to url: URL, scale: CGFloat = 1.5) -> Bool {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else {
            print("\(url.lastPathComponent): rendering failed")
            return false
        }
        do {
            try png.write(to: url)
            return true
        } catch {
            print("\(url.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }
}

/// The lock screen with a sample exercise. The figure shows the first moment of its loop.
private struct LockPreview: View {
    let exercise: Exercise
    let isPrimary: Bool
    @State private var model = BlockModel()

    var body: some View {
        BlockView(model: model, isPrimary: isPrimary)
            .onAppear {
                model.title = L(exercise.title)
                model.detail = L(exercise.detail)
                model.exerciseID = exercise.id
                model.secondsLeft = 42
                model.phrase = "river candle orbit maple"
                model.escapesLeft = 2
            }
    }
}

/// The warning panel for a few exercises, on a dark backdrop like a desktop.
private struct WarningSheet: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(["squats", "stepjacks", "pushups"], id: \.self) { id in
                let exercise = Exercises.all.first { $0.id == id } ?? Exercises.all[0]
                WarningView(model: {
                    let model = WarningModel()
                    model.exerciseTitle = exercise.title
                    model.exerciseID = exercise.id
                    model.secondsLeft = 37
                    return model
                }())
            }
        }
        .padding(20)
        .background(Color(white: 0.25))
    }
}

/// Eight frames across one loop, with the time of each.
private struct ContactSheet: View {
    let title: String
    let animation: FigureAnimation

    var body: some View {
        let times = (0..<8).map { animation.period * Double($0) / 8 }
        VStack(alignment: .leading, spacing: 10) {
            Text(String(format: "%@  ·  loop %.2f s", title, animation.period))
                .font(.system(size: 16, weight: .semibold))
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(times[(row * 4)..<(row * 4 + 4)], id: \.self) { time in
                        FigureCell(frame: animation.frame(at: time), caption: String(format: "%.2f s", time))
                    }
                }
            }
        }
        .padding(16)
        .foregroundStyle(.white)
        .background(Palette.bottom)
    }
}

/// The still of every exercise, plus each one at the warning panel's badge size.
private struct KeyPoseSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<((Exercises.all.count + 3) / 4), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(Exercises.all.dropFirst(row * 4).prefix(4), id: \.id) { exercise in
                        FigureCell(frame: FigureAnimations.keyFrame(for: exercise.id), caption: exercise.id) {
                            FigureCanvas(frame: FigureAnimations.keyFrame(for: exercise.id), style: .badge)
                                .frame(width: 36, height: 36)
                        }
                    }
                }
            }
        }
        .padding(16)
        .foregroundStyle(.white)
        .background(Palette.bottom)
    }
}

private struct FigureCell<Badge: View>: View {
    let frame: FigureFrame
    let caption: String
    @ViewBuilder var badge: Badge

    var body: some View {
        VStack(spacing: 4) {
            FigureCanvas(frame: frame)
                .frame(width: 260, height: 260)
                .background(LinearGradient(colors: [Palette.top, Palette.bottom], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .topLeading) { badge.padding(6) }
            Text(caption)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

extension FigureCell where Badge == EmptyView {
    init(frame: FigureFrame, caption: String) {
        self.init(frame: frame, caption: caption) { EmptyView() }
    }
}
