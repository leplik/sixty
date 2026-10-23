import AppKit
import AVFoundation
import ImageIO
import SixtyCore
import SwiftUI
import UniformTypeIdentifiers

// `Sixty --render-media [repository]` draws the marketing media offscreen from the app's own SwiftUI views:
// no screen recording, nothing from the real desktop, the same pictures on every run. It reads the icon from the
// repository (default: the current directory) and writes
//   docs/media/                          lock.png, warning.png, call.png, exercises.png, demo.mp4, demo.gif
//   packaging/appstore/screenshots/en/   1-lock.jpg … 5-exercises.jpg, 2880×1800 with captions
//   site/assets/                         demo.mp4, demo-poster.jpg
//
// Every scene is laid out in points on a 1440×900 canvas, a 16:10 screen, and rendered at the output size.
// Add `--stills-only` to skip the video and the GIF while iterating on a picture.

@MainActor
enum MediaRenderer {
    static let canvas = CGSize(width: 1440, height: 900)

    static func run(repository path: String) -> Int32 {
        let root = URL(fileURLWithPath: path, isDirectory: true)
        guard let icon = NSImage(contentsOf: root.appendingPathComponent("site/assets/icon-512.png")) else {
            print("Run this from the repository root, or pass it: Sixty --render-media <repository>")
            return 1
        }
        let media = root.appendingPathComponent("docs/media")
        let site = root.appendingPathComponent("site/assets")
        let screenshots = root.appendingPathComponent("packaging/appstore/screenshots/en")
        let moving = !CommandLine.arguments.contains("--stills-only")
        do {
            let studio = try Studio(copy: .english, icon: icon)
            try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)

            try write(png: studio.lockStill(), to: media.appendingPathComponent("lock.png"))
            // JPEG: App Store Connect takes it, it has no alpha channel, and the gradients would make PNGs heavy.
            for (index, shot) in studio.appStoreShots().enumerated() {
                try write(jpeg: shot.view, size: CGSize(width: 2880, height: 1800), quality: 0.9,
                          to: screenshots.appendingPathComponent("\(index + 1)-\(shot.name).jpg"))
            }
            try write(jpeg: studio.lockStill(), size: CGSize(width: 1280, height: 800),
                      to: site.appendingPathComponent("demo-poster.jpg"))
            // The wallpaper's gradients make large PNGs; the README shows these small anyway.
            try write(png: studio.desktop(.warning), width: 1920, height: 1200,
                      to: media.appendingPathComponent("warning.png"))
            try write(png: studio.desktop(.call(camera: false)), width: 1920, height: 1200,
                      to: media.appendingPathComponent("call.png"))
            try write(png: studio.exerciseGrid(title: true), to: media.appendingPathComponent("exercises.png"))
            if moving {
                let video = site.appendingPathComponent("demo.mp4")
                try writeVideo(studio.storyboard(compact: false), to: video)
                try writeGIF(studio.storyboard(compact: true), to: media.appendingPathComponent("demo.gif"))
                let copy = media.appendingPathComponent("demo.mp4")
                try? FileManager.default.removeItem(at: copy)
                try FileManager.default.copyItem(at: video, to: copy)
            }
        } catch {
            print("Rendering failed: \(error)")
            return 1
        }
        print("Media written under \(root.path)")
        return 0
    }

    // MARK: Output

    struct RenderError: Error, CustomStringConvertible {
        let description: String
    }

    /// The scene drawn at exactly `width`×`height` pixels.
    static func image(_ view: some View, width: Int, height: Int) throws -> CGImage {
        // Small outputs are drawn at twice the size and scaled down: text stays crisp.
        let oversample = width < 1200 ? 2.0 : 1.0
        let renderer = ImageRenderer(
            content: view.frame(width: canvas.width, height: canvas.height).environment(\.colorScheme, .dark)
        )
        renderer.scale = CGFloat(width) / canvas.width * oversample
        guard let drawn = renderer.cgImage else { throw RenderError(description: "ImageRenderer returned nothing") }
        if drawn.width == width, drawn.height == height { return drawn }
        let context = try bitmap(width: width, height: height)
        context.interpolationQuality = .high
        context.draw(drawn, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw RenderError(description: "cannot scale a frame") }
        return image
    }

    static func bitmap(width: Int, height: Int) throws -> CGContext {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw RenderError(description: "cannot make a \(width)×\(height) bitmap") }
        return context
    }

    static func write(png view: some View, width: Int = 2880, height: Int = 1800, to url: URL) throws {
        try save(image(view, width: width, height: height), type: .png, to: url, properties: [:])
    }

    static func write(jpeg view: some View, size: CGSize, quality: Double = 0.82, to url: URL) throws {
        let picture = try image(view, width: Int(size.width), height: Int(size.height))
        try save(picture, type: .jpeg, to: url, properties: [kCGImageDestinationLossyCompressionQuality: quality])
    }

    static func save(_ image: CGImage, type: UTType, to url: URL, properties: [CFString: Any]) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw RenderError(description: "cannot write \(url.path)") }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw RenderError(description: "cannot write \(url.path)")
        }
        print("  \(url.lastPathComponent)")
    }

    /// H.264, 1920×1200, 30 fps, moov atom first so the browser can start playing at once.
    static func writeVideo(_ story: Storyboard, to url: URL) throws {
        let fps = 30
        let writer = try VideoWriter(url: url, width: 1920, height: 1200, fps: fps, bitrate: 1_600_000)
        let count = Int((story.duration * Double(fps)).rounded())
        for frame in 0..<count {
            let picture = try image(story.view(at: Double(frame) / Double(fps)), width: 1920, height: 1200)
            try writer.append(picture, frame: frame)
        }
        try writer.finish()
        print("  \(url.lastPathComponent)")
    }

    /// 800×500 at 12.5 fps. Identical frames are merged into one longer frame, so still moments cost nothing.
    static func writeGIF(_ story: Storyboard, to url: URL) throws {
        let delay = 0.08
        var frames: [(image: CGImage, delay: Double)] = []
        var previous: Data?
        for index in 0..<Int((story.duration / delay).rounded()) {
            let context = try bitmap(width: 800, height: 500)
            context.draw(try image(story.view(at: Double(index) * delay), width: 800, height: 500),
                         in: CGRect(x: 0, y: 0, width: 800, height: 500))
            guard let data = context.data, let picture = context.makeImage() else { continue }
            let pixels = Data(bytes: data, count: context.bytesPerRow * context.height)
            if pixels == previous, !frames.isEmpty {
                frames[frames.count - 1].delay += delay
            } else {
                frames.append((picture, delay))
                previous = pixels
            }
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames.count, nil
        ) else { throw RenderError(description: "cannot write \(url.path)") }
        let loop = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(destination, loop as CFDictionary)
        for frame in frames {
            let timing = [kCGImagePropertyGIFDelayTime: frame.delay, kCGImagePropertyGIFUnclampedDelayTime: frame.delay]
            let properties = [kCGImagePropertyGIFDictionary: timing] as CFDictionary
            CGImageDestinationAddImage(destination, frame.image, properties)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw RenderError(description: "cannot write \(url.path)")
        }
        print("  \(url.lastPathComponent): \(frames.count) frames")
    }
}

/// Encodes frames into an MP4 file.
@MainActor
final class VideoWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let width: Int
    private let height: Int
    private let fps: Int32

    init(url: URL, width: Int, height: Int, fps: Int, bitrate: Int) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
                AVVideoExpectedSourceFrameRateKey: fps,
            ],
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        writer.add(input)
        self.width = width
        self.height = height
        self.fps = Int32(fps)
        guard writer.startWriting() else {
            throw MediaRenderer.RenderError(description: "cannot start the video: \(String(describing: writer.error))")
        }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ image: CGImage, frame: Int) throws {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
        var buffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool,
              CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
              let buffer
        else { throw MediaRenderer.RenderError(description: "no pixel buffer") }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { throw MediaRenderer.RenderError(description: "no frame context") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps)) else {
            let reason = String(describing: writer.error)
            throw MediaRenderer.RenderError(description: "cannot append frame \(frame): \(reason)")
        }
    }

    func finish() throws {
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else {
            throw MediaRenderer.RenderError(description: "video failed: \(String(describing: writer.error))")
        }
    }
}

// MARK: - Words

/// Marketing text and the fake desktop's words. App texts come from `L()`.
struct MediaCopy {
    let menuBar: [String]
    let windowTitle: String
    let callTitle: String
    let clock: String
    /// App Store captions: a white lead and an accent rest.
    let captions: [(lead: String, rest: String)]
    let gridTitle: String
    let spineSection: String
    let otherSection: String
    let tagline: String
    let facts: String
    let website: String

    static let english = MediaCopy(
        menuBar: ["Editor", "File", "Edit", "View", "Window", "Help"],
        windowTitle: "project — Editor",
        callTitle: "Call",
        clock: "Thu 10:42",
        captions: [
            ("One minute every hour.", "Stand up and move."),
            ("Spine first:", "cat-cow, back bends, hip hinges"),
            ("Never during a call —", "it waits for you"),
            ("No Skip button.", "Only a phrase you can't type on autopilot."),
            ("22 standing exercises,", "animated"),
        ],
        gridTitle: "22 standing exercises",
        spineSection: "First 30 seconds · spine and lower back",
        otherSection: "Next 30 seconds · everything else",
        tagline: "Stand up every hour. Never during a call.",
        facts: "Free · Open source · macOS 14+",
        website: "leplik.github.io/sixty"
    )
}

// MARK: - Scenes

/// Builds every scene.
@MainActor
struct Studio {
    let copy: MediaCopy
    let icon: NSImage
    let catCow: Exercise
    let squats: Exercise
    let reach: Exercise
    let hinge: Exercise

    init(copy: MediaCopy, icon: NSImage) throws {
        func exercise(_ id: String) throws -> Exercise {
            guard let found = Exercises.all.first(where: { $0.id == id }) else {
                throw MediaRenderer.RenderError(description: "no exercise \(id)")
            }
            return found
        }
        self.copy = copy
        self.icon = icon
        catCow = try exercise("catcow")
        squats = try exercise("squats")
        reach = try exercise("reach")
        hinge = try exercise("hinge")
    }

    static let phrase = "river candle orbit maple"

    /// The lock screen at a given moment. `secondsLeft` may be fractional: the ring then moves smoothly.
    func lock(
        _ exercise: Exercise,
        step: Int,
        secondsLeft: Double,
        figure time: Double,
        typed: String = ""
    ) -> AnyView {
        let model = BlockModel()
        model.title = L(exercise.title)
        model.detail = L(exercise.detail)
        model.exerciseID = exercise.id
        model.step = step
        model.steps = 2
        model.totalSeconds = 30
        model.secondsLeft = Int(ceil(max(0, secondsLeft)))
        model.phrase = Self.phrase
        model.escapesLeft = 2
        model.typed = typed
        return AnyView(
            BlockView(model: model, isPrimary: true)
                .environment(\.figureClock, time)
                .environment(\.stillLock, StillLock(ringProgress: max(0, secondsLeft) / 30))
        )
    }

    /// Cat-cow, the cat moment, 18 seconds left of the first half.
    func lockStill() -> AnyView {
        lock(catCow, step: 0, secondsLeft: 18, figure: 0.6)
    }

    enum DesktopMoment {
        case working(minutes: Int, typing: Double)
        case warning
        case call(camera: Bool)
    }

    func desktop(_ moment: DesktopMoment) -> AnyView {
        switch moment {
        case .working(let minutes, let typing):
            AnyView(Desktop(copy: copy, status: .minutes(minutes), typing: typing))
        case .warning:
            AnyView(Desktop(copy: copy, status: .seconds(42), typing: 1, warning: warningPanel(42), clock: 0.6))
        case .call(let camera):
            AnyView(Desktop(copy: copy, status: .call, typing: 1, menu: callMenu(camera: camera), showsCall: true))
        }
    }

    func warningPanel(_ seconds: Int) -> WarningModel {
        let model = WarningModel()
        model.secondsLeft = seconds
        model.exerciseTitle = [catCow, squats].map { L($0.title) }.joined(separator: " + ")
        model.exerciseID = catCow.id
        return model
    }

    func callMenu(camera: Bool) -> [MenuLine] {
        let status = camera ? L("Break waits: the camera is on") : String(format: L("Break waits: call in %@"), "Zoom")
        return [
            .info(status),
            .info(String(format: L("Breaks today: %ld"), 3)),
            .info(String(format: L("Emergency exits left today: %ld of %ld"), 2, 2)),
            .separator,
            .action(L("Take a Break Now")),
            .separator,
            .action(L("About Sixty")),
            .action(L("How to turn Sixty off")),
        ]
    }

    func exerciseGrid(title: Bool) -> AnyView {
        AnyView(ExerciseGrid(copy: copy, showsTitle: title))
    }

    func endCard() -> AnyView {
        AnyView(EndCard(copy: copy, icon: icon))
    }

    // MARK: App Store

    func appStoreShots() -> [(name: String, view: AnyView)] {
        let captions = copy.captions
        let spine = ["catcow", "backbend", "hinge"].compactMap { id in Exercises.all.first { $0.id == id } }
        return [
            ("lock", AnyView(Captioned(caption: captions[0]) { lock(reach, step: 1, secondsLeft: 21, figure: 2.9) })),
            ("spine", AnyView(Captioned(caption: captions[1], framed: false) {
                SpineTrio(exercises: spine, backdrop: false)
            })),
            ("call", AnyView(Captioned(caption: captions[2]) { desktop(.call(camera: true)) })),
            ("no-skip", AnyView(Captioned(caption: captions[3]) {
                lock(hinge, step: 0, secondsLeft: 9, figure: 2.3, typed: "river cand")
                    .scaleEffect(1.6, anchor: UnitPoint(x: 0.5, y: 0.97))
                    .frame(width: MediaRenderer.canvas.width, height: MediaRenderer.canvas.height)
                    .clipped()
            })),
            ("exercises", AnyView(Captioned(caption: captions[4], framed: false) {
                ExerciseGrid(copy: copy, showsTitle: false, backdrop: false)
            })),
        ]
    }

    // MARK: Story

    /// The demo: working → warning → two exercises → back to work → end card. The compact cut for the GIF skips the
    /// working moments and keeps each exercise short.
    func storyboard(compact: Bool) -> Storyboard {
        let warningStart = compact ? 0.0 : 1.8
        let warningLength = compact ? 2.2 : 2.8
        let lockIn = warningStart + warningLength
        let exercise = compact ? 3.4 : 4.7
        let fade = 0.6
        var clips: [Clip] = []

        clips.append(Clip(start: 0, end: lockIn + fade) { u in
            let panel = u - warningStart
            if panel < 0 {
                return desktop(.working(minutes: 1, typing: min(1, u / 1.6)))
            }
            let slide = Ease.out(min(1, panel / 0.5))
            let seconds = max(1, Int(ceil(60 - 59 * min(1, panel / (warningLength - 0.2)))))
            return AnyView(Desktop(
                copy: copy, status: .seconds(seconds), typing: 1,
                warning: warningPanel(seconds), panelSlide: slide, clock: u
            ))
        })

        let first = lockIn
        clips.append(Clip(start: first, end: first + fade + exercise) { u in
            let left = 30 - 28 * Ease.inOut(min(1, max(0, (u - fade) / (exercise - 0.2))))
            return lock(catCow, step: 0, secondsLeft: left, figure: 0.9 + u)
        })

        let second = first + exercise
        clips.append(Clip(start: second, end: second + fade + exercise - (compact ? 0.4 : 0.6), dip: true) { u in
            let length = exercise - (compact ? 0.4 : 0.6)
            let left = 30 - 29 * Ease.inOut(min(1, max(0, (u - fade) / (length - 0.2))))
            return lock(squats, step: 1, secondsLeft: left, figure: 0.2 + u)
        })

        var end = second + exercise - (compact ? 0.4 : 0.6)
        if !compact {
            clips.append(Clip(start: end, end: end + fade + 1.0) { u in
                desktop(.working(minutes: 60, typing: min(1, u / 1.4)))
            })
            end += 1.0
        }
        clips.append(Clip(start: end, end: end + fade + (compact ? 1.8 : 2.2)) { _ in endCard() })
        return Storyboard(clips: clips)
    }
}

/// A clip of the storyboard, drawn from its own local time. Overlapping clips crossfade.
struct Clip {
    let start: Double
    let end: Double
    /// Fade through the lock screen's background instead of crossfading: two lock screens with different layouts
    /// would otherwise show both titles at once.
    var dip = false
    let make: @MainActor (Double) -> AnyView
}

@MainActor
struct Storyboard {
    let clips: [Clip]

    var duration: Double { clips.map(\.end).max() ?? 0 }

    /// The later clip fades in over the earlier one where they overlap; all scenes are opaque. A dipping clip waits
    /// for the earlier one to fade out first.
    func view(at time: Double) -> some View {
        ZStack {
            ForEach(Array(clips.enumerated()), id: \.offset) { index, clip in
                if clip.start <= time, time < clip.end {
                    clip.make(time - clip.start).opacity(opacity(of: index, at: time))
                }
            }
        }
        .frame(width: MediaRenderer.canvas.width, height: MediaRenderer.canvas.height)
        .background(LinearGradient(colors: [Palette.top, Palette.bottom], startPoint: .top, endPoint: .bottom))
    }

    private func opacity(of index: Int, at time: Double) -> Double {
        let clip = clips[index]
        let overlap = index > 0 ? clips[index - 1].end - clip.start : 0
        var opacity = 1.0
        if overlap > 0 {
            let progress = min(1, (time - clip.start) / overlap)
            opacity = Ease.inOut(clip.dip ? progress * 2 - 1 : progress)
        }
        // Fading out under a dipping successor.
        if index + 1 < clips.count, clips[index + 1].dip, time >= clips[index + 1].start {
            let next = clips[index + 1]
            opacity *= 1 - Ease.inOut((time - next.start) / (clip.end - next.start) * 2)
        }
        return opacity
    }
}

enum Ease {
    static func inOut(_ x: Double) -> Double { 0.5 - 0.5 * cos(.pi * min(1, max(0, x))) }
    static func out(_ x: Double) -> Double { sin(.pi / 2 * min(1, max(0, x))) }
}

// MARK: - Desktop

/// A neutral macOS-like desktop: soft wallpaper, menu bar with Sixty, an editor window with placeholder code.
struct Desktop: View {
    enum Status {
        case minutes(Int)
        case seconds(Int)
        case call
    }

    let copy: MediaCopy
    let status: Status
    /// 0…1: how much of the last code line is typed.
    var typing: Double = 1
    var warning: WarningModel?
    var panelSlide: Double = 1
    var menu: [MenuLine]?
    var showsCall = false
    /// Drives the warning panel's live figure.
    var clock: Double = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            Wallpaper()
            EditorWindow(title: copy.windowTitle, typing: typing)
                .frame(width: 1010, height: 700)
                .offset(x: 130, y: 96)
            if showsCall {
                CallWindow(title: copy.callTitle)
                    .frame(width: 340, height: 236)
                    .offset(x: 1010, y: 560)
            }
            MenuBar(copy: copy, status: status, menuOpen: menu != nil)
            if let menu {
                // A status menu that would not fit to the right of its item sits at the screen's edge.
                MenuPanel(lines: menu)
                    .fixedSize()
                    .frame(width: MediaRenderer.canvas.width - 6, alignment: .trailing)
                    .offset(y: 28)
            }
            if let warning {
                WarningView(model: warning)
                    .environment(\.figureClock, clock)
                    .offset(x: MediaRenderer.canvas.width - 316 + CGFloat(1 - panelSlide) * 340, y: 42)
                    .opacity(panelSlide)
            }
        }
        .frame(width: MediaRenderer.canvas.width, height: MediaRenderer.canvas.height, alignment: .topLeading)
        .clipped()
    }
}

struct Wallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.15, blue: 0.23), Color(red: 0.04, green: 0.06, blue: 0.09)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(red: 0.36, green: 0.43, blue: 0.75).opacity(0.5), .clear],
                center: UnitPoint(x: 0.1, y: 0.0), startRadius: 0, endRadius: 780
            )
            RadialGradient(
                colors: [Palette.accent.opacity(0.55), Palette.accent.opacity(0)],
                center: UnitPoint(x: 0.95, y: 1.1), startRadius: 0, endRadius: 760
            )
            Capsule()
                .fill(Palette.accent.opacity(0.2))
                .frame(width: 1500, height: 240)
                .rotationEffect(.degrees(-14))
                .offset(x: 260, y: 300)
                .blur(radius: 90)
        }
        .frame(width: MediaRenderer.canvas.width, height: MediaRenderer.canvas.height)
        .clipped()
    }
}

enum MenuLine {
    case info(String)
    case action(String)
    case separator
}

struct MenuBar: View {
    let copy: MediaCopy
    let status: Desktop.Status
    var menuOpen = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 20) {
                ForEach(Array(copy.menuBar.enumerated()), id: \.offset) { index, name in
                    Text(name).fontWeight(index == 0 ? .bold : .regular)
                }
            }
            .padding(.leading, 20)
            Spacer(minLength: 0)
            HStack(spacing: 18) {
                sixty
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Image(systemName: "switch.2")
                Text(copy.clock)
            }
            .padding(.trailing, 18)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .frame(width: MediaRenderer.canvas.width, height: 26)
        .background(Color.black.opacity(0.3))
    }

    private var sixty: some View {
        HStack(spacing: 5) {
            switch status {
            case .minutes(let minutes):
                Image(systemName: "figure.stand")
                Text(String(format: L("%ldm"), minutes)).monospacedDigit()
            case .seconds(let seconds):
                Image(systemName: "figure.walk")
                Text(String(format: L("%lds"), seconds)).monospacedDigit()
            case .call:
                Image(systemName: "phone.fill")
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background {
            if menuOpen { RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.24)) }
        }
    }
}

/// A dark macOS menu.
struct MenuPanel: View {
    let lines: [MenuLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                switch line {
                case .separator:
                    Rectangle()
                        .fill(.white.opacity(0.12))
                        .frame(height: 1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                case .info(let text):
                    row(text, opacity: 0.5)
                case .action(let text):
                    row(text, opacity: 0.92)
                }
            }
        }
        .padding(.vertical, 5)
        .frame(minWidth: 250, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(red: 0.17, green: 0.17, blue: 0.19).opacity(0.97))
        )
        .outlined(9, opacity: 0.14, width: 0.5)
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        .foregroundStyle(.white)
    }

    private func row(_ text: String, opacity: Double) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(opacity))
            .padding(.horizontal, 14)
            .frame(height: 22, alignment: .leading)
    }
}

/// A window of a generic code editor: grey bars instead of text.
struct EditorWindow: View {
    let title: String
    let typing: Double

    /// Indent and (width, colour) bars per line; the last line is the one being typed.
    private static let code: [(indent: Int, bars: [(CGFloat, Int)])] = [
        (0, [(56, 1), (118, 2)]),
        (0, [(56, 1), (92, 2)]),
        (0, []),
        (0, [(64, 1), (128, 2), (14, 0)]),
        (1, [(36, 1), (84, 0), (66, 2)]),
        (1, [(36, 1), (120, 0), (96, 3)]),
        (1, [(36, 1), (70, 0), (40, 3)]),
        (0, []),
        (1, [(48, 1), (150, 4), (14, 0)]),
        (2, [(88, 0), (20, 0), (176, 3)]),
        (2, [(28, 1), (104, 0), (72, 4), (14, 0)]),
        (3, [(140, 0), (90, 3)]),
        (3, [(60, 1), (110, 4)]),
        (2, [(14, 0)]),
        (2, [(56, 1), (124, 0)]),
        (1, [(14, 0)]),
        (0, []),
        (1, [(48, 1), (190, 4), (14, 0)]),
        (2, [(96, 0), (64, 2), (84, 3)]),
        (2, [(150, 0), (70, 4)]),
    ]

    private static let tints: [Color] = [
        .white.opacity(0.42),
        Color(red: 0.98, green: 0.47, blue: 0.67).opacity(0.75),
        Color(red: 0.45, green: 0.82, blue: 0.86).opacity(0.7),
        Color(red: 0.93, green: 0.78, blue: 0.45).opacity(0.7),
        Color(red: 0.6, green: 0.62, blue: 1.0).opacity(0.75),
    ]

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(.black.opacity(0.4)).frame(width: 1)
                editor
            }
        }
        .background(Color(red: 0.115, green: 0.12, blue: 0.135))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .outlined(12, opacity: 0.1, width: 1)
        .shadow(color: .black.opacity(0.5), radius: 40, y: 22)
    }

    private var titleBar: some View {
        ZStack {
            HStack(spacing: 8) {
                TrafficLights()
                Spacer()
            }
            .padding(.leading, 14)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(height: 36)
        .background(Color(white: 0.16))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array([90, 70, 110, 84, 64, 120, 76, 96, 58, 102].enumerated()), id: \.offset) { index, width in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.22)).frame(width: 11, height: 13)
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.28)).frame(width: CGFloat(width), height: 8)
                }
                .padding(.leading, index % 4 == 0 ? 16 : 30)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .background(index == 5 ? Color.white.opacity(0.08) : .clear)
            }
            Spacer()
        }
        .padding(.top, 14)
        .frame(width: 230)
        .background(Color(white: 0.09))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Self.code.enumerated()), id: \.offset) { index, line in
                let last = index == Self.code.count - 1
                HStack(spacing: 0) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.22))
                        .frame(width: 30, alignment: .trailing)
                    Spacer().frame(width: 20 + CGFloat(line.indent) * 26)
                    bars(line.bars, shown: last ? typing : 1)
                    if last {
                        RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.85)).frame(width: 2, height: 16)
                    }
                }
                .frame(height: 24)
            }
            Spacer()
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The bars of a line, cut off at `shown` of its total length.
    private func bars(_ bars: [(CGFloat, Int)], shown: Double) -> some View {
        let total = bars.reduce(CGFloat(0)) { $0 + $1.0 + 8 }
        var budget = total * CGFloat(shown)
        var visible: [(CGFloat, Int)] = []
        for (width, tint) in bars where budget > 0 {
            visible.append((min(width, budget), tint))
            budget -= width + 8
        }
        return HStack(spacing: 8) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, bar in
                RoundedRectangle(cornerRadius: 3).fill(Self.tints[bar.1]).frame(width: bar.0, height: 8)
            }
        }
        .padding(.trailing, 6)
    }
}

struct TrafficLights: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
            Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
            Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 12, height: 12)
        }
    }
}

/// A generic video call: two tiles and the usual controls.
struct CallWindow: View {
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    TrafficLights()
                    Spacer()
                }
                .padding(.leading, 12)
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            }
            .frame(height: 30)
            HStack(spacing: 8) {
                tile(Color(red: 0.22, green: 0.3, blue: 0.42), speaking: true)
                tile(Color(red: 0.35, green: 0.27, blue: 0.36), speaking: false)
            }
            .padding(.horizontal, 10)
            HStack(spacing: 14) {
                control("mic.fill", tint: .white.opacity(0.16))
                control("video.fill", tint: .white.opacity(0.16))
                control("phone.down.fill", tint: Color(red: 0.92, green: 0.27, blue: 0.27))
            }
            .padding(.vertical, 12)
        }
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .outlined(12, opacity: 0.12, width: 1)
        .shadow(color: .black.opacity(0.55), radius: 30, y: 16)
    }

    private func tile(_ color: Color, speaking: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(color)
            .overlay(Image(systemName: "person.fill").font(.system(size: 46)).foregroundStyle(.white.opacity(0.4)))
            .overlay {
                if speaking {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(red: 0.3, green: 0.85, blue: 0.45), lineWidth: 2)
                }
            }
    }

    private func control(_ symbol: String, tint: Color) -> some View {
        Circle()
            .fill(tint)
            .frame(width: 36, height: 36)
            .overlay(Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white))
    }
}

// MARK: - Cards

struct EndCard: View {
    let copy: MediaCopy
    let icon: NSImage

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.top, Palette.bottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [Palette.accent.opacity(0.22), .clear],
                center: UnitPoint(x: 0.5, y: 0.36), startRadius: 0, endRadius: 520
            )
            VStack(spacing: 0) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 176, height: 176)
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
                Text("Sixty")
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .padding(.top, 24)
                Text(copy.tagline)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.top, 4)
                Text(copy.facts)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 34)
                Text(copy.website)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .padding(.top, 12)
            }
            .foregroundStyle(.white)
        }
        .frame(width: MediaRenderer.canvas.width, height: MediaRenderer.canvas.height)
    }
}

/// All exercises at their key moment, in two panels: the spine half of a break and the other half.
struct ExerciseGrid: View {
    let copy: MediaCopy
    var showsTitle = true
    var backdrop = true

    var body: some View {
        ZStack {
            if backdrop {
                LinearGradient(colors: [Palette.top, Palette.bottom], startPoint: .top, endPoint: .bottom)
            }
            VStack(spacing: 0) {
                if showsTitle {
                    Text(copy.gridTitle)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .padding(.bottom, 30)
                }
                HStack(alignment: .top, spacing: 44) {
                    panel(copy.spineSection, Exercises.all.filter { $0.focus == .spine })
                    panel(copy.otherSection, Exercises.all.filter { $0.focus != .spine })
                }
            }
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func panel(_ title: String, _ exercises: [Exercise]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 13, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Palette.accent)
                .padding(.bottom, 4)
            ForEach(Array(stride(from: 0, to: exercises.count, by: 4)), id: \.self) { first in
                HStack(spacing: 10) {
                    ForEach(exercises[first..<min(first + 4, exercises.count)]) { cell($0) }
                }
            }
        }
    }

    private func cell(_ exercise: Exercise) -> some View {
        VStack(spacing: 2) {
            FigureCanvas(frame: FigureAnimations.keyFrame(for: exercise.id))
                .frame(width: 150, height: 150)
            Text(L(exercise.title))
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 140, height: 34, alignment: .top)
        }
        .padding(.bottom, 6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.035)))
        .outlined(14, opacity: 0.07, width: 1)
    }
}

/// Three spine exercises side by side, large.
struct SpineTrio: View {
    let exercises: [Exercise]
    var backdrop = true

    var body: some View {
        ZStack {
            if backdrop {
                LinearGradient(colors: [Palette.top, Palette.bottom], startPoint: .top, endPoint: .bottom)
            }
            HStack(spacing: 30) {
                ForEach(exercises) { exercise in
                    VStack(spacing: 0) {
                        FigureCanvas(frame: FigureAnimations.keyFrame(for: exercise.id))
                            .frame(width: 400, height: 400)
                        Text(L(exercise.title))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .frame(width: 380, height: 84, alignment: .top)
                    }
                    .padding(.vertical, 18)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.white.opacity(0.04)))
                    .outlined(26, opacity: 0.08, width: 1)
                }
            }
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// An App Store screenshot: a big caption above the scene.
struct Captioned<Content: View>: View {
    let caption: (lead: String, rest: String)
    var framed = true
    @ViewBuilder let content: Content

    private static var scale: CGFloat { 670 / MediaRenderer.canvas.height }

    var body: some View {
        let scale = Self.scale
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.11, blue: 0.16), Palette.bottom],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Palette.accent.opacity(0.18), .clear],
                center: UnitPoint(x: 0.5, y: 0.0), startRadius: 0, endRadius: 760
            )
            VStack(spacing: 0) {
                Text(headline)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(width: 1300, height: 196)
                if framed {
                    // A whole screen, scaled down into a window-like frame.
                    content
                        .frame(width: MediaRenderer.canvas.width, height: MediaRenderer.canvas.height)
                        .scaleEffect(scale)
                        .frame(width: MediaRenderer.canvas.width * scale, height: MediaRenderer.canvas.height * scale)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.55), radius: 40, y: 20)
                } else {
                    // Cards drawn for the screenshot fill the space under the caption at full size.
                    content
                        .frame(width: MediaRenderer.canvas.width, height: MediaRenderer.canvas.height - 220)
                }
            }
        }
        .frame(width: MediaRenderer.canvas.width, height: MediaRenderer.canvas.height)
    }

    private var headline: AttributedString {
        var text = AttributedString(caption.lead + " ")
        var rest = AttributedString(caption.rest)
        rest.swiftUI.foregroundColor = Palette.accent
        text.append(rest)
        return text
    }
}

private extension View {
    /// A thin light border along a rounded rectangle.
    func outlined(_ radius: CGFloat, opacity: Double, width: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(opacity), lineWidth: width)
        )
    }
}
