import AppKit
import QuartzCore
import SwiftUI

// MARK: - Settings

enum RemovalStyle: String, CaseIterable, Identifiable {
    case retract, genie, fall

    var id: Self { self }

    var title: String {
        switch self {
        case .retract: "Retract"
        case .genie: "Genie"
        case .fall: "Fall Off"
        }
    }
}

enum Settings {
    private static var defaults: UserDefaults { .standard }

    static var style: RemovalStyle { RemovalStyle(rawValue: defaults.string(forKey: "style") ?? "") ?? .fall }
    static var strength: Double { defaults.object(forKey: "strength") as? Double ?? 0.5 }
    static var revealIcons: Bool { defaults.object(forKey: "revealIcons") as? Bool ?? true }
    static var sounds: Bool { defaults.object(forKey: "sounds") as? Bool ?? true }
    static var dramatic: Bool { defaults.object(forKey: "dramatic") as? Bool ?? true }

    /// Time multiplier for every animation: stronger removal is faster and more violent.
    static var speed: Double { 0.7 + strength * 0.9 }
}

func play(_ name: String) {
    guard Settings.sounds else { return }
    (NSSound(named: name)?.copy() as? NSSound)?.play()
}

// MARK: - Math

func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
func smoothstep(_ t: Double) -> Double { t * t * (3 - 2 * t) }
func easeIn(_ t: Double) -> Double { t * t * t }

func rotate(_ p: CGPoint, by a: Double) -> CGPoint {
    CGPoint(x: p.x * cos(a) - p.y * sin(a), y: p.x * sin(a) + p.y * cos(a))
}

// MARK: - Overlay

/// A click-through, full-screen window above the menu bar that draws the fake notch.
/// Screen recordings of a notched MacBook don't include the physical notch, so this is the only one viewers see.
@MainActor
final class NotchOverlay {
    private let window: NSWindow
    private let notch = CAShapeLayer()
    private let genie = CAShapeLayer()
    private let icons = CALayer()
    private let screenSize: CGSize
    private let scale: CGFloat
    /// Notch body in view coordinates (y up, origin bottom-left of the screen), excluding the top flares.
    private let home: CGRect
    /// Height of a bottom Dock, or 0 when it's hidden or on the side.
    private let dockTop: CGFloat
    private let flare: CGFloat = 6
    private var timer: Timer?

    init() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main!
        let frame = screen.frame
        screenSize = frame.size
        scale = screen.backingScaleFactor
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let height = screen.safeAreaInsets.top
            home = CGRect(x: left.maxX - frame.minX, y: frame.height - height, width: right.minX - left.maxX, height: height)
        } else {
            home = CGRect(x: (frame.width - 185) / 2, y: frame.height - 32, width: 185, height: 32)
        }
        dockTop = max(0, screen.visibleFrame.minY - frame.minY)

        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.setFrame(frame, display: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        window.contentView = view
        let root = view.layer!

        icons.frame = root.bounds
        root.addSublayer(icons)

        notch.fillColor = NSColor.black.cgColor
        notch.frame = home.insetBy(dx: -flare, dy: 0)
        notch.path = notchPath(size: notch.bounds.size)
        notch.contentsScale = scale
        root.addSublayer(notch)

        genie.fillColor = NSColor.black.cgColor
        genie.frame = root.bounds
        genie.isHidden = true
        root.addSublayer(genie)

        window.orderFrontRegardless()
    }

    /// Notch outline in its own bounds: concave flares where it meets the top edge, rounded bottom corners.
    private func notchPath(size: CGSize) -> CGPath {
        let f = flare, r: CGFloat = 14, w = size.width, h = size.height
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: h))
        p.addQuadCurve(to: CGPoint(x: f, y: h - f), control: CGPoint(x: f, y: h))
        p.addLine(to: CGPoint(x: f, y: r))
        p.addQuadCurve(to: CGPoint(x: f + r, y: 0), control: CGPoint(x: f, y: 0))
        p.addLine(to: CGPoint(x: w - f - r, y: 0))
        p.addQuadCurve(to: CGPoint(x: w - f, y: r), control: CGPoint(x: w - f, y: 0))
        p.addLine(to: CGPoint(x: w - f, y: h - f))
        p.addQuadCurve(to: CGPoint(x: w, y: h), control: CGPoint(x: w - f, y: h))
        p.closeSubpath()
        return p
    }

    /// Plausible status items that were "hiding" behind the notch the whole time.
    private func layoutIcons(dark: Bool) {
        icons.sublayers = nil
        let names = ["cloud.fill", "shield.lefthalf.filled", "cup.and.saucer.fill", "music.note", "sparkles"]
        let color: NSColor = dark ? .white : .black
        let spacing: CGFloat = 30
        var x = home.midX - spacing * CGFloat(names.count - 1) / 2
        for name in names {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { continue }
            let tinted = NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect)
                color.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let layer = CALayer()
            layer.contents = tinted.layerContents(forContentsScale: scale)
            layer.contentsScale = scale
            layer.frame = CGRect(x: x - symbol.size.width / 2, y: home.midY - symbol.size.height / 2,
                                 width: symbol.size.width, height: symbol.size.height)
            icons.addSublayer(layer)
            x += spacing
        }
    }

    private func place(_ center: CGPoint, angle: Double = 0) {
        notch.position = center
        notch.setAffineTransform(CGAffineTransform(rotationAngle: angle))
    }

    /// Moves the notch up by `offset`. Negative offsets stretch it downward instead,
    /// so it never detaches from the top edge of the screen.
    private func slide(_ offset: Double) {
        let stretch = max(0, -offset)
        notch.position = CGPoint(x: home.midX, y: home.midY + max(0, offset) - stretch / 2)
        notch.setAffineTransform(CGAffineTransform(scaleX: 1, y: 1 + stretch / home.height))
    }

    /// Drives a frame-by-frame animation. `step` gets elapsed seconds and returns true when finished.
    private func animate(_ step: @escaping (Double) -> Bool, completion: @escaping () -> Void) {
        timer?.invalidate()
        let start = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { timer in
            MainActor.assumeIsolated {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                let done = step(CACurrentMediaTime() - start)
                CATransaction.commit()
                if done {
                    timer.invalidate()
                    completion()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func remove(style: RemovalStyle, speed: Double, revealIcons: Bool, darkMenuBar: Bool, completion: @escaping () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        icons.isHidden = !revealIcons
        if revealIcons { layoutIcons(dark: darkMenuBar) }
        CATransaction.commit()

        let finish = { [self] in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            notch.isHidden = true
            place(CGPoint(x: home.midX, y: home.midY))
            CATransaction.commit()
            completion()
        }
        switch style {
        case .retract: retract(speed: speed, completion: finish)
        case .genie: genieAway(speed: speed, completion: finish)
        case .fall: fallOff(speed: speed, completion: finish)
        }
    }

    /// Drops the notch back in from above the screen with a little bounce.
    func restore(completion: @escaping () -> Void) {
        let rise = home.height + 6
        play("Pop")
        animate({ [self] t in
            notch.isHidden = false
            slide(rise * exp(-7 * t) * cos(12 * t))
            return t > 0.9
        }, completion: { [self] in
            place(CGPoint(x: home.midX, y: home.midY))
            completion()
        })
    }

    /// Dips down slightly, then shoots up into the bezel.
    private func retract(speed: Double, completion: @escaping () -> Void) {
        let duration = 0.6 / speed
        let rise = home.height + 6
        play("Pop")
        animate({ [self] t in
            let p = clamp(t / duration)
            let offset = p < 0.25
                ? -3 * sin(p / 0.25 * .pi / 2)
                : -3 + (rise + 3) * pow((p - 0.25) / 0.75, 2.4)
            slide(offset)
            return p >= 1
        }, completion: completion)
    }

    /// Minimize-to-Dock: the notch stretches down a funnel and gets sucked into the bottom of the screen.
    private func genieAway(speed: Double, completion: @escaping () -> Void) {
        let duration = 0.85 / speed
        let targetX = home.midX
        let targetY = max(dockTop / 2, 16)
        let halfWidth: CGFloat = 14
        let top0 = home.maxY, bottom0 = home.minY
        let span = top0 - targetY
        let funnelStart = home.height / span

        func edges(atY y: CGFloat) -> (CGFloat, CGFloat) {
            let s = (top0 - y) / span
            let b = smoothstep(clamp((s - funnelStart) / (1 - funnelStart)))
            return (lerp(home.minX, targetX - halfWidth, b), lerp(home.maxX, targetX + halfWidth, b))
        }

        play("Blow")
        animate({ [self] t in
            let p = clamp(t / duration)
            let bottom = lerp(bottom0, targetY, smoothstep(clamp(p / 0.55)))
            let top = lerp(top0, targetY, easeIn(clamp((p - 0.15) / 0.85)))
            var left: [CGPoint] = [], right: [CGPoint] = []
            for i in 0...48 {
                let y = lerp(top, bottom, Double(i) / 48)
                let (l, r) = edges(atY: y)
                left.append(CGPoint(x: l, y: y))
                right.append(CGPoint(x: r, y: y))
            }
            let path = CGMutablePath()
            path.addLines(between: left + right.reversed())
            path.closeSubpath()
            genie.path = path
            genie.opacity = Float(p > 0.92 ? (1 - p) / 0.08 : 1)
            genie.isHidden = false
            notch.isHidden = true
            return p >= 1
        }, completion: { [self] in
            genie.isHidden = true
            completion()
        })
    }

    /// Wiggles loose, swings down from its right corner, then drops, bounces and tumbles off screen.
    private func fallOff(speed: Double, completion: @escaping () -> Void) {
        let w = home.width, h = home.height
        let hinge = CGPoint(x: home.maxX, y: home.maxY)
        let gravity = 2400 * speed * speed
        let wiggle = 0.6 / speed
        let floor = dockTop
        var stage = 0, last = 0.0
        var angle = 0.0, spin = 0.0
        var center = CGPoint(x: home.midX, y: home.midY)
        var velocity = CGVector.zero

        animate({ [self] t in
            let dt = min(t - last, 1.0 / 30)
            last = t
            switch stage {
            case 0:
                let k = t / wiggle
                angle = sin(t * 70) * 0.035 * k
                if k >= 1 {
                    stage = 1
                    angle = 0
                    play("Tink")
                }
            case 1:
                spin += 1.5 * gravity / w * cos(angle) * dt
                angle += spin * dt
                let arm = rotate(CGPoint(x: -w / 2, y: -h / 2), by: angle)
                center = CGPoint(x: hinge.x + arm.x, y: hinge.y + arm.y)
                if angle > 1.0 {
                    stage = 2
                    velocity = CGVector(dx: 300 * speed, dy: spin * arm.x)
                    spin *= 0.8
                }
            default:
                velocity.dy -= gravity * dt
                center.x += velocity.dx * dt
                center.y += velocity.dy * dt
                angle += spin * dt
                let extent = abs(w / 2 * sin(angle)) + abs(h / 2 * cos(angle))
                if center.y - extent < floor, velocity.dy < 0 {
                    center.y = floor + extent
                    if -velocity.dy > 200 { play("Bottle") }
                    velocity.dy *= -0.45
                    velocity.dx = max(velocity.dx * 0.9, 420 * speed)
                    spin = -velocity.dx / (h / 2) * 0.35
                }
            }
            place(center, angle: angle)
            return center.x - w > screenSize.width || center.y < -w
        }, completion: completion)
    }
}

// MARK: - Model

@MainActor
final class NotchModel: ObservableObject {
    enum Phase { case present, working, removed }

    @Published private(set) var phase = Phase.present
    @Published private(set) var status = "Notch detected"

    let overlay = NotchOverlay()
    var menuBarIsDark: () -> Bool = { true }

    func toggle() {
        switch phase {
        case .present: remove()
        case .removed: confirmRestore()
        case .working: break
        }
    }

    private func remove() {
        phase = .working
        Task {
            if Settings.dramatic {
                for (text, pause) in [("Scanning display…", 0.8), ("1 notch found", 0.6)] {
                    status = text
                    try? await Task.sleep(for: .seconds(pause))
                }
            }
            status = "Removing notch…"
            overlay.remove(style: Settings.style, speed: Settings.speed, revealIcons: Settings.revealIcons,
                           darkMenuBar: menuBarIsDark()) {
                self.phase = .removed
                self.status = "No notch detected"
            }
        }
    }

    private func confirmRestore() {
        let alert = NSAlert()
        alert.messageText = "Restore your notch?"
        alert.informativeText = "Notchless will put your notch back exactly where it was. Some people like it, apparently."
        alert.addButton(withTitle: "Keep It Gone")
        alert.addButton(withTitle: "Restore Notch")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        phase = .working
        status = "Reinstalling notch…"
        overlay.restore { [weak self] in
            self?.phase = .present
            self?.status = "Notch detected"
        }
    }
}

// MARK: - UI

struct ContentView: View {
    @ObservedObject var model: NotchModel
    @AppStorage("style") private var style = RemovalStyle.fall
    @AppStorage("strength") private var strength = 0.5
    @AppStorage("revealIcons") private var revealIcons = true
    @AppStorage("sounds") private var sounds = true
    @AppStorage("dramatic") private var dramatic = true
    @State private var showPro = false

    private var strengthLabel: String {
        switch strength {
        case ..<0.33: "Gentle"
        case ..<0.66: "Firm"
        case ..<0.95: "Aggressive"
        default: "Nuclear ☢️"
        }
    }

    private var statusColor: Color {
        switch model.phase {
        case .present: .red
        case .working: .orange
        case .removed: .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notchless").font(.system(size: 26, weight: .bold))
                    Text("Removes the notch. Finally.").foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Circle().fill(statusColor).frame(width: 10, height: 10)
                Text(model.status).font(.system(.body, design: .monospaced))
                Spacer()
                if model.phase == .working { ProgressView().controlSize(.small) }
            }
            .padding(12)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))

            Button { model.toggle() } label: {
                Text(model.phase == .removed ? "Restore Notch" : "Remove Notch")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(model.phase == .removed ? .gray : .red)
            .disabled(model.phase == .working)
            .keyboardShortcut("r")

            VStack(alignment: .leading, spacing: 12) {
                Picker("Method", selection: $style) {
                    ForEach(RemovalStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Strength")
                    Slider(value: $strength)
                    Text(strengthLabel).frame(width: 92, alignment: .trailing)
                }

                Toggle("Reveal menu bar items hidden by the notch", isOn: $revealIcons)
                Toggle("Sound effects", isOn: $sounds)
                Toggle("Dramatic pause", isOn: $dramatic)
            }
            .disabled(model.phase == .working)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Notchless Pro").font(.headline)
                    Spacer()
                    Text("$49.99/yr").foregroundStyle(.secondary)
                }
                ForEach(["Remove the webcam", "Remove the Dynamic Island (iPhone)", "Remove bezels",
                         "Remove the Touch Bar retroactively"], id: \.self) {
                    Label($0, systemImage: "checkmark.seal.fill").font(.callout)
                }
                Button("Upgrade to Pro") { showPro = true }
                    .padding(.top, 4)
            }
            .padding(14)
            .background(
                LinearGradient(colors: [.purple.opacity(0.18), .blue.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .padding(24)
        .frame(width: 400)
        .alert("Almost there", isPresented: $showPro) {
            Button("Never Mind", role: .cancel) {}
        } message: {
            Text("Webcam removal requires a Phillips #000 screwdriver and voids your warranty.")
        }
    }
}

func makeAppIcon() -> NSImage {
    NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { _ in
        let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
        NSGradient(colors: [NSColor(srgbRed: 0.43, green: 0.55, blue: 1, alpha: 1),
                            NSColor(srgbRed: 0.56, green: 0.29, blue: 0.96, alpha: 1)])!.draw(in: tile, angle: -90)

        NSColor(white: 0.86, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 180, y: 290, width: 664, height: 44), xRadius: 22, yRadius: 22).fill()

        NSColor(white: 0.07, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 232, y: 330, width: 560, height: 390), xRadius: 34, yRadius: 34).fill()

        let display = NSRect(x: 254, y: 352, width: 516, height: 346)
        NSGradient(colors: [NSColor(srgbRed: 0.2, green: 0.8, blue: 0.85, alpha: 1),
                            NSColor(srgbRed: 0.25, green: 0.4, blue: 0.95, alpha: 1)])!
            .draw(in: NSBezierPath(roundedRect: display, xRadius: 14, yRadius: 14), angle: -60)

        // The notch hangs from the bezel; its top corners sit inside the bezel so only the bottom ones show.
        NSColor(white: 0.07, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 447, y: 664, width: 130, height: 48), xRadius: 14, yRadius: 14).fill()
        return true
    }
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = NotchModel()
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = makeAppIcon()
        setUpMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "Notchless")
        let menu = NSMenu()
        menu.delegate = self
        toggleItem = menu.addItem(withTitle: "Remove Notch", action: #selector(toggleNotch), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(withTitle: "Show Notchless", action: #selector(showWindow), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Notchless", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        model.menuBarIsDark = { [weak self] in
            self?.statusItem.button?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }

        window = NSWindow(contentViewController: NSHostingController(rootView: ContentView(model: model)))
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        toggleItem.title = model.phase == .removed ? "Restore Notch" : "Remove Notch"
        toggleItem.isEnabled = model.phase != .working
    }

    @objc private func toggleNotch() { model.toggle() }

    /// Runs after the status menu closes, since activating during menu tracking is ignored.
    /// Plain `NSApp.activate()` is a request the frontmost app can refuse, which left the window behind it.
    @objc private func showWindow() {
        DispatchQueue.main.async { [self] in
            window.orderFrontRegardless()
            window.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func setUpMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide Notchless", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Notchless", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let main = NSMenu()
        main.addItem(appItem)
        NSApp.mainMenu = main
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--export-icon"), i + 1 < CommandLine.arguments.count {
    let image = makeAppIcon()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    exit(0)
}

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.run()
}
