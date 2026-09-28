import SwiftUI

struct MeditateView: View {
    var body: some View {
        GeometryReader { geometry in
            let diameter = max(160, min(304, geometry.size.width - 80, geometry.size.height - 220))
            VStack(spacing: 0) {
                Spacer(minLength: 12)
                Text("a calmer\nhappier you")
                    .font(.system(size: 27, weight: .regular, design: .serif))
                    .tracking(-0.7)
                    .lineSpacing(-2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 52)
                MeditationDial().frame(width: diameter, height: diameter)
                Color.clear.frame(height: 44).padding(.top, 28).accessibilityHidden(true)
                Spacer(minLength: 18)
                Spacer(minLength: 0).frame(height: geometry.size.height * 0.08)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
        }
    }
}

private struct MeditationDial: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var adjustment: DialAdjustment?
    @State private var rotation: Double = 0
    @State private var initialRotation: Double = 0
    @State private var ready = false
    @State private var pulse = false
    @State private var releaseTask: Task<Void, Never>?
    @State private var feedback = UISelectionFeedbackGenerator()
    private var selected: Int { adjustment?.selectedMinutes ?? model.preferences.durationMinutes }
    private var active: Bool { model.active != nil }
    private var paused: Bool { model.active?.isPaused == true }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.width
            let buttonDiameter = max(48, size * 0.19)
            ZStack {
                Circle()
                    .fill(Palette.paper)
                    .overlay(Circle().strokeBorder(.white.opacity(0.78), lineWidth: 1))
                    .shadow(color: Palette.secondary.opacity(0.09), radius: 18, x: 0, y: 8)
                    .anchorPreference(key: DialElementAnchorsPreferenceKey.self, value: .bounds) {
                        DialElementAnchors(dial: $0)
                    }
                Circle()
                    .fill(LinearGradient(colors: [Palette.paper, Color(red: 0.97, green: 0.96, blue: 0.93)], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().strokeBorder(Palette.line.opacity(0.40), lineWidth: 0.7))
                    .padding(size * 0.025)
                DialEngraving().stroke(Color(red: 0.48, green: 0.54, blue: 0.47), style: StrokeStyle(lineWidth: 0.65, lineCap: .round))
                    .rotationEffect(.degrees(rotation))
                    .opacity(active ? 0.20 : 0.48)
                    .accessibilityHidden(true)
                DialFiveMinuteMarks().stroke(Color(red: 0.46, green: 0.53, blue: 0.47), style: StrokeStyle(lineWidth: 0.85, lineCap: .round))
                    .rotationEffect(.degrees(rotation))
                    .opacity(active ? 0.20 : 0.59)
                    .accessibilityHidden(true)
                DialCardinalMarks().stroke(Color(red: 0.45, green: 0.52, blue: 0.46), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    .rotationEffect(.degrees(rotation))
                    .opacity(active ? 0.20 : 0.62)
                    .accessibilityHidden(true)
                // Gesture belongs to the annulus, so a drag never triggers the play button.
                DialAnnulus().fill(.clear).contentShape(DialAnnulus())
                    .gesture(turnGesture(size: size), including: active ? .none : .all)
                    .accessibilityElement()
                    .accessibilityLabel("Meditation duration")
                    .accessibilityValue("\(selected) minutes")
                    .accessibilityHint("Turn clockwise to add minutes. Swipe up or down to adjust with VoiceOver.")
                    .accessibilityAdjustableAction { direction in
                        guard !active else { return }
                        let delta = direction == .increment ? 1 : -1
                        let value = min(180, max(0, selected + delta))
                        rotation += Double(value - selected) * 6
                        model.updatePreferences { $0.durationMinutes = value }
                        highlightPlay()
                    }
                    .accessibilityIdentifier("durationDial")
                VStack(spacing: 8) {
                    Text(durationText(Double(selected * 60)))
                        .font(.system(size: size * 0.175, weight: .regular, design: .serif))
                        .tracking(-1.8).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                        .foregroundStyle(Color(red: 0.22, green: 0.29, blue: 0.27))
                        .accessibilityIdentifier("dialTime")
                        .anchorPreference(key: DialElementAnchorsPreferenceKey.self, value: .bounds) {
                            DialElementAnchors(time: $0)
                        }
                    Text("MINUTES")
                        .font(.system(size: 9, weight: .regular)).tracking(2.6)
                        .foregroundStyle(Palette.secondary)
                }.frame(width: size * 0.6).position(x: size / 2, y: size * 0.43)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .combine)
                Button(action: play) {
                    MeditationControlButtonLabel(isPlaying: active && !paused, diameter: buttonDiameter, pulse: pulse && !reduceMotion)
                        .opacity(adjustment != nil ? 0.5 : 1)
                }.buttonStyle(.plain)
                    .disabled(adjustment != nil || (!active && selected == 0))
                    .position(x: size / 2, y: size * 0.755)
                    .accessibilityLabel(active ? (paused ? "Resume meditation" : "Pause meditation") : "Begin meditation")
                    .accessibilityIdentifier(active ? (paused ? "resumeMeditation" : "pauseMeditation") : "beginMeditation")
                Capsule().fill(Palette.secondary).frame(width: 2, height: 8)
                    .position(x: size / 2, y: -10).accessibilityHidden(true)
            }
        }
        .onDisappear { commitDial(); releaseTask?.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { commitDial() } }
        .onChange(of: model.active?.id) { _, _ in ready = false; pulse = false }
        .onChange(of: model.preferences.durationMinutes) { _, minutes in
            if minutes == 0 && !active { resetDial() }
        }
    }
    private func turnGesture(size: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard !active else { return }
                func angle(_ location: CGPoint) -> Double { atan2(Double(location.x - size / 2), Double(size / 2 - location.y)) }
                if adjustment == nil {
                    initialRotation = rotation
                    var dial = DialAdjustment(minutes: model.preferences.durationMinutes)
                    dial.turn(to: angle(value.startLocation)); adjustment = dial
                    ready = false; pulse = false; feedback.prepare()
                }
                let previous = selected
                adjustment?.turn(to: angle(value.location))
                rotation = initialRotation + (adjustment?.rotation ?? 0)
                if previous != selected { feedback.selectionChanged() }
            }
            .onEnded { _ in
                commitDial()
            }
    }
    private func commitDial() {
        guard let adjustment else { return }
        model.updatePreferences { $0.durationMinutes = adjustment.selectedMinutes }
        self.adjustment = nil
        highlightPlay()
    }
    private func resetDial() {
        releaseTask?.cancel(); ready = false; pulse = false
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) {
            rotation = (rotation / 360).rounded() * 360
        }
    }
    private func highlightPlay() {
        guard selected > 0 else { resetDial(); return }
        releaseTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { ready = true; pulse = true }
        releaseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { pulse = false }
        }
    }
    private func play() {
        guard adjustment == nil else { return }
        releaseTask?.cancel(); ready = false; pulse = false
        if !active { model.start() }
        else if paused { model.resume() }
        else { model.pause() }
    }
}

struct MeditationControlButtonLabel: View {
    let isPlaying: Bool
    let diameter: CGFloat
    var pulse = false

    var body: some View {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .contentTransition(.symbolEffect(.replace))
            .font(.system(size: 16, weight: .regular))
            .offset(x: isPlaying ? 0 : 1)
            .frame(width: diameter, height: diameter)
            .foregroundStyle(Palette.paper)
            .background(Palette.dialSage, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.56), lineWidth: 0.8))
            .shadow(color: Palette.dialSage.opacity(0.16), radius: 8, y: 3)
            .overlay(Circle().stroke(Palette.pale.opacity(pulse ? 0.5 : 0), lineWidth: pulse ? 8 : 0).padding(-4))
            .scaleEffect(pulse ? 1.04 : 1)
    }
}

struct DialElementAnchors {
    var dial: Anchor<CGRect>?
    var time: Anchor<CGRect>?

    init(dial: Anchor<CGRect>? = nil, time: Anchor<CGRect>? = nil) {
        self.dial = dial
        self.time = time
    }
}

struct DialElementAnchorsPreferenceKey: PreferenceKey {
    static let defaultValue = DialElementAnchors()

    static func reduce(value: inout DialElementAnchors, nextValue: () -> DialElementAnchors) {
        let next = nextValue()
        if let dial = next.dial { value.dial = dial }
        if let time = next.time { value.time = time }
    }
}

private struct DialEngraving: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width / 2
        for tick in 0..<60 {
            guard !tick.isMultiple(of: 5) else { continue }
            let angle = Double(tick) * .pi / 30
            let inner = radius * 0.88
            let outer = radius * 0.93
            path.move(to: CGPoint(x: rect.midX + sin(angle) * inner, y: rect.midY - cos(angle) * inner))
            path.addLine(to: CGPoint(x: rect.midX + sin(angle) * outer, y: rect.midY - cos(angle) * outer))
        }
        return path
    }
}
private struct DialFiveMinuteMarks: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width / 2
        for tick in 0..<60 where tick.isMultiple(of: 5) && !tick.isMultiple(of: 15) {
            let angle = Double(tick) * .pi / 30
            let inner = radius * 0.815
            let outer = radius * 0.93
            path.move(to: CGPoint(x: rect.midX + sin(angle) * inner, y: rect.midY - cos(angle) * inner))
            path.addLine(to: CGPoint(x: rect.midX + sin(angle) * outer, y: rect.midY - cos(angle) * outer))
        }
        return path
    }
}
private struct DialCardinalMarks: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width / 2
        for tick in stride(from: 0, to: 60, by: 15) {
            let angle = Double(tick) * .pi / 30
            let inner = radius * 0.82
            let outer = radius * 0.93
            path.move(to: CGPoint(x: rect.midX + sin(angle) * inner, y: rect.midY - cos(angle) * inner))
            path.addLine(to: CGPoint(x: rect.midX + sin(angle) * outer, y: rect.midY - cos(angle) * outer))
        }
        return path
    }
}
private struct DialAnnulus: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        var path = Path()
        path.addArc(center: centre, radius: outer, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        path.addArc(center: centre, radius: outer * 0.70, startAngle: .degrees(360), endAngle: .degrees(0), clockwise: true)
        path.closeSubpath()
        return path
    }
}
