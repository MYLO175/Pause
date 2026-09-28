import SwiftUI
import UIKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var journal = false
    @State private var settings = false
    @State private var sounds = false
    @State private var sessionTransitioning = false
    @State private var sessionTransitionTask: Task<Void, Never>?
    @State private var cardDismissalTask: Task<Void, Never>?
    @State private var savePresentationTask: Task<Void, Never>?
    @State private var exitPending = false
    @State private var savedSession: SessionRecord?
    @State private var screenCovered = false
    @State private var sessionOverlayVisible = false
    @State private var sessionControlVisible = false
    @State private var endingConfirmation = false
    private var sessionTransitionDuration: Double { reduceMotion ? 0.12 : 0.5 }
    private var sessionTransition: Animation { .easeInOut(duration: sessionTransitionDuration) }
    private var sessionTransitionDelay: Duration { .seconds(sessionTransitionDuration) }

    var body: some View {
        @Bindable var model = model
        let sessionIsActive = model.active != nil
        ZStack {
                NavigationStack {
                    ZStack {
                        Palette.cream.ignoresSafeArea()
                        MeditationLandscapeBackground()
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Text("pause")
                                    .font(.system(size: 23, weight: .regular, design: .serif))
                                    .tracking(-1.1)
                                    .foregroundStyle(Palette.ink)
                                    .accessibilityLabel("Pause")
                                Spacer(minLength: 0)
                                TopBarButton(symbol: "calendar", label: "Open journal") { journal = true }
                                TopBarButton(symbol: "slider.horizontal.3", label: "Settings") { settings = true }.disabled(model.active != nil)
                            }.padding(.horizontal, 24).padding(.top, 6)

                            MeditateView()

                            Button { sounds = true } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 16, weight: .light))
                                    Text(model.preferences.ambient == "none" ? "a little silence" : SoundOptions.ambientName(model.preferences.ambient).lowercased())
                                        .font(.system(.callout, design: .rounded))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .regular))
                                }
                                .foregroundStyle(Palette.secondary)
                                .padding(.horizontal, 19)
                                .frame(maxWidth: 360)
                                .frame(height: 56)
                                .background(Palette.paper.opacity(0.82), in: Capsule())
                                .overlay(Capsule().strokeBorder(.white.opacity(0.72), lineWidth: 1))
                                .shadow(color: Palette.ink.opacity(0.06), radius: 14, x: 0, y: 5)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Sounds & bells")
                            .disabled(model.active != nil)
                            .padding(.horizontal, 30)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(isPresented: $journal) { JournalView(openSettings: { settings = true }) }
                }
                .foregroundStyle(Palette.ink)
                .allowsHitTesting(!sessionOverlayVisible && !sessionTransitioning)
                .accessibilityHidden(sessionOverlayVisible || sessionTransitioning)

            Color.black
                .opacity(screenCovered ? 1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .overlayPreferenceValue(DialElementAnchorsPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                let dialFrame = anchors.dial.map { proxy[$0] } ?? CGRect(
                    x: (proxy.size.width - 304) / 2,
                    y: (proxy.size.height - 304) / 2,
                    width: 304,
                    height: 304
                )
                let controlDiameter = max(48, dialFrame.width * 0.19)
                let controlFrame = CGRect(
                    x: dialFrame.midX - controlDiameter / 2,
                    y: dialFrame.minY + dialFrame.height * 0.755 - controlDiameter / 2,
                    width: controlDiameter,
                    height: controlDiameter
                )
                let timerCenter = anchors.time.map {
                    let frame = proxy[$0]
                    return CGPoint(x: frame.midX, y: frame.midY)
                } ?? CGPoint(x: dialFrame.midX, y: dialFrame.minY + dialFrame.height * 0.43)

                ZStack {
                    if sessionOverlayVisible {
                        ImmersiveMeditationView(
                            screenCovered: screenCovered,
                            showSessionContent: sessionControlVisible,
                            timerCenter: timerCenter,
                            timerFontSize: dialFrame.width * 0.175,
                            controlFrame: controlFrame,
                            ending: $endingConfirmation,
                            savedSession: savedSession,
                            end: presentEndConfirmation,
                            save: saveSession,
                            discard: discardSession,
                            resume: continueMeditating,
                            discardSaved: discardSavedSession,
                            continueToHome: continueToHome
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .zIndex(2)
                    }

                    if sessionControlVisible && savedSession == nil {
                        Button(action: togglePause) {
                            MeditationControlButtonLabel(
                                isPlaying: model.active?.isPaused == false,
                                diameter: controlFrame.width
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(model.active?.isPaused == true ? "Resume meditation" : "Pause meditation")
                        .accessibilityHint(model.active?.isPaused == true ? "Resume the meditation." : "Pause the meditation.")
                        .accessibilityIdentifier(model.active?.isPaused == true ? "resumeMeditation" : "pauseMeditation")
                        .position(x: controlFrame.midX, y: controlFrame.midY)
                        .disabled(!sessionIsActive)
                        .transition(.opacity)
                        .zIndex(3)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .statusBarHidden(sessionOverlayVisible)
        .persistentSystemOverlays(sessionOverlayVisible ? .hidden : .visible)
        .sheet(isPresented: $settings) { SettingsView() }
        .sheet(isPresented: $sounds) {
            NavigationStack {
                SoundSettingsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sounds = false } } }
            }.tint(Palette.dialSage).presentationBackground(Palette.cream)
        }
        .sheet(item: $model.permissionPurpose) { purpose in PermissionView(purpose: purpose) }
        .alert("A small interruption", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .onChange(of: scenePhase) { _, phase in
            model.foreground = phase == .active
            if phase == .active { model.recover() }
            updateIdleTimer()
        }
        .onChange(of: model.active?.isPaused) { _, _ in updateIdleTimer() }
        .onChange(of: sessionIsActive) { _, active in
            if !exitPending && (active || savedSession == nil) { transitionSessionScreen(isActive: active) }
        }
        .onAppear {
            updateIdleTimer()
            if sessionIsActive {
                screenCovered = true
                sessionOverlayVisible = true
                sessionControlVisible = true
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-journal") { journal = true }
            #endif
        }
    }
    private var confirmationAnimation: Animation { .easeInOut(duration: reduceMotion ? 0.12 : 0.28) }
    private var savedResultAnimation: Animation { .easeInOut(duration: reduceMotion ? 0.12 : 0.58) }
    private func presentEndConfirmation() {
        withAnimation(confirmationAnimation) {
            sessionControlVisible = false
            endingConfirmation = true
        }
    }
    private func continueMeditating() {
        model.resume()
        withAnimation(confirmationAnimation) {
            endingConfirmation = false
            sessionControlVisible = true
        }
    }
    private func saveSession() {
        exitPending = true
        model.saveEarly()
        guard let completed = model.completed else {
            if model.active == nil { fadeCardThenReturnHome() }
            else { exitPending = false }
            return
        }
        savePresentationTask?.cancel()
        withAnimation(confirmationAnimation) { endingConfirmation = false }
        savePresentationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.12 : 0.28))
            guard !Task.isCancelled else { return }
            withAnimation(savedResultAnimation) { savedSession = completed }
            exitPending = false
        }
    }
    private func discardSession() {
        exitPending = true
        model.discard()
        fadeCardThenReturnHome()
    }
    private func discardSavedSession() {
        guard let savedSession, model.deleteSession(savedSession.id) else { return }
        model.completed = nil
        fadeCardThenReturnHome()
    }
    private func continueToHome() {
        model.completed = nil
        fadeCardThenReturnHome()
    }
    private func fadeCardThenReturnHome() {
        cardDismissalTask?.cancel()
        sessionTransitioning = true
        withAnimation(confirmationAnimation) {
            endingConfirmation = false
            savedSession = nil
        }
        cardDismissalTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.12 : 0.28))
            guard !Task.isCancelled else { return }
            exitPending = false
            transitionSessionScreen(isActive: false)
        }
    }
    private func transitionSessionScreen(isActive: Bool) {
        sessionTransitionTask?.cancel()
        sessionTransitioning = true

        if isActive {
            savedSession = nil
            sessionOverlayVisible = true
            sessionControlVisible = true
            withAnimation(sessionTransition) { screenCovered = true }

            sessionTransitionTask = Task { @MainActor in
                try? await Task.sleep(for: sessionTransitionDelay)
                guard !Task.isCancelled, model.active != nil else { return }
                sessionTransitioning = false
            }
        } else {
            withAnimation(sessionTransition) {
                screenCovered = false
                endingConfirmation = false
                savedSession = nil
            }

            sessionTransitionTask = Task { @MainActor in
                try? await Task.sleep(for: sessionTransitionDelay)
                guard !Task.isCancelled, model.active == nil else { return }
                sessionOverlayVisible = false
                sessionControlVisible = false
                endingConfirmation = false
                sessionTransitioning = false
            }
        }
    }
    private func togglePause() {
        guard model.active != nil else { return }
        if model.active?.isPaused == true { model.resume() } else { model.pause() }
    }
    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && model.active?.isPaused == false
    }
}

private struct ImmersiveMeditationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let screenCovered: Bool
    let showSessionContent: Bool
    let timerCenter: CGPoint
    let timerFontSize: CGFloat
    let controlFrame: CGRect
    @Binding var ending: Bool
    let savedSession: SessionRecord?
    let end: () -> Void
    let save: () -> Void
    let discard: () -> Void
    let resume: () -> Void
    let discardSaved: () -> Void
    let continueToHome: () -> Void
    @State private var displayedTimerText: String?
    @State private var lastPaused = false

    private var paused: Bool { model.active?.isPaused ?? lastPaused }
    private var timerText: String { displayedTimerText ?? liveTimerText }
    private var isOvertime: Bool {
        guard let active = model.active else { return false }
        return active.elapsed(at: model.now) > active.targetSeconds
    }
    private var liveTimerText: String {
        guard let active = model.active else { return durationText(model.remaining) }
        let elapsed = active.elapsed(at: model.now)
        if elapsed > active.targetSeconds { return "+\(durationText(elapsed - active.targetSeconds))" }
        return durationText(active.targetSeconds - elapsed)
    }
    private var controlAnimation: Animation { .easeInOut(duration: reduceMotion ? 0.18 : 0.32) }
    private var transitionAnimation: Animation { .easeInOut(duration: reduceMotion ? 0.12 : 0.5) }
    private var contentAnimation: Animation { .easeInOut(duration: reduceMotion ? 0.12 : 0.28) }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Text(timerText)
                    .font(.system(size: timerFontSize, weight: .regular, design: .serif))
                    .tracking(-1.8)
                    .monospacedDigit()
                    .foregroundStyle(Palette.paper)
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: !isOvertime))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: timerText)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(isOvertime ? "Time since planned end" : "Time remaining")
                    .accessibilityValue(timerText)
                    .accessibilityIdentifier("sessionCountdown")
                    .position(x: timerCenter.x, y: timerCenter.y)
                    .opacity(screenCovered && showSessionContent && savedSession == nil ? 1 : 0)

                ZStack(alignment: .top) {
                    Color.clear
                        .frame(height: 62)
                        .accessibilityHidden(true)

                    if paused {
                        Button("End session", action: end)
                            .font(.system(size: 15, weight: .medium, design: .serif))
                            .foregroundStyle(Palette.paper)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                            .accessibilityIdentifier("endMeditation")
                            .padding(.top, 18)
                            .transition(.opacity)
                    }
                }
                .frame(width: min(geometry.size.width - 48, 300), height: 62)
                .position(x: controlFrame.midX, y: controlFrame.maxY + 31)
                .opacity(screenCovered && showSessionContent && savedSession == nil ? 1 : 0)
                .animation(controlAnimation, value: paused)
                .allowsHitTesting(showSessionContent && !ending && savedSession == nil)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(transitionAnimation, value: screenCovered)
            .animation(contentAnimation, value: showSessionContent)
        }
        .overlay {
            if let savedSession {
                SavedSessionCard(session: savedSession, continueToHome: continueToHome, discardSession: discardSaved)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
                    .zIndex(3)
            } else if ending {
                EndSessionConfirmation(
                    elapsed: model.active?.elapsed(at: model.now) ?? 0,
                    save: save,
                    discard: discard,
                    continueMeditating: resume
                )
                .padding(.horizontal, 24)
                .transition(.opacity)
                .zIndex(3)
            }
        }
        .animation(controlAnimation, value: ending)
        .onAppear {
            displayedTimerText = liveTimerText
            lastPaused = model.active?.isPaused ?? false
        }
        .onChange(of: model.now) { _, _ in updateTimerText() }
        .onChange(of: model.active?.isPaused) { _, value in
            if let value { lastPaused = value }
        }
    }

    private func updateTimerText() {
        guard model.active != nil else { return }
        let next = liveTimerText
        if displayedTimerText != next { displayedTimerText = next }
    }
}

private struct EndSessionConfirmation: View {
    let elapsed: Double
    let save: () -> Void
    let discard: () -> Void
    let continueMeditating: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Keep this quiet moment?")
                .font(.system(size: 26, weight: .regular, design: .serif))
                .foregroundStyle(Palette.paper)
                .fixedSize(horizontal: false, vertical: true)

            Text("Only time spent meditating is saved. Pauses aren’t counted.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Palette.paper.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                Button(action: save) {
                    Text("Save \(minutesText(elapsed))")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Palette.pale, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("saveMeditationSession")

                Button(role: .destructive, action: discard) {
                    Text("Discard session")
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.52))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.white.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)

                Button("Keep meditating", action: continueMeditating)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(Palette.paper.opacity(0.94))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(Color(red: 0.11, green: 0.13, blue: 0.12), in: RoundedRectangle(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 28, y: 12)
        .accessibilityElement(children: .contain)
    }
}

private struct SavedSessionCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: SessionRecord
    let continueToHome: () -> Void
    let discardSession: () -> Void
    @State private var reflecting = false
    @State private var cardVisible = true
    @State private var cardSwapTask: Task<Void, Never>?
    @State private var reflection = ""
    @State private var reflectionLoaded = false
    @State private var error: String?
    @State private var confirmingDiscard = false
    @FocusState private var reflectionFocused: Bool

    private var duration: String {
        let seconds = max(1, Int(session.seconds))
        if seconds < 60 { return "\(seconds) sec" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }
    private var totalTime: String {
        let seconds = model.progress.totalSeconds
        if seconds < 60 { return "\(Int(seconds)) sec" }
        let total = PracticeTotal(seconds: seconds)
        let unit = seconds < 3600 ? "min" : seconds < 86400 ? "hr" : "days"
        return "\(total.value) \(unit)"
    }
    private var cardFadeDuration: Double { reduceMotion ? 0.12 : 0.3 }

    var body: some View {
        Group {
            if reflecting { reflectionCard }
            else { summaryCard }
        }
        .opacity(cardVisible ? 1 : 0)
        .allowsHitTesting(cardVisible)
        .onAppear {
            if !reflectionLoaded {
                reflection = session.reflection
                reflectionLoaded = true
            }
        }
        .confirmationDialog("Discard this session?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard session", role: .destructive, action: discardSession)
            Button("Keep session", role: .cancel) {}
        } message: {
            Text("This removes the meditation from your journal and updates your streak and total time.")
        }
    }

    private var summaryCard: some View {
        cardSurface {
        VStack(spacing: 22) {
            Text("\(duration)\nmeditated")
                .font(.system(size: 42, weight: .regular, design: .serif))
                .tracking(-1.4)
                .multilineTextAlignment(.center)
                .lineSpacing(-3)
                .foregroundStyle(Palette.paper)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.75)

            HStack(spacing: 0) {
                metric("\(model.progress.currentStreak(now: model.now))", caption: "day streak")
                Rectangle()
                    .fill(Palette.paper.opacity(0.22))
                    .frame(width: 1, height: 42)
                metric(totalTime, caption: "total meditated")
            }
            .padding(.vertical, 15)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))

            Button(action: continueToHome) {
                Text("Continue")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Palette.pale, in: Capsule())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button { showCard(reflectionEditor: true) } label: {
                    Text("Add a reflection")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.paper)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)

                Button { confirmingDiscard = true } label: {
                    Text("Discard")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 1, green: 0.68, blue: 0.64))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("discardCompletedSession")
            }
        }
        }
    }

    private var reflectionCard: some View {
        cardSurface {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your reflection")
                    .font(.system(size: 29, weight: .regular, design: .serif))
                    .foregroundStyle(Palette.paper)

                TextField("A thought to carry with you…", text: $reflection, axis: .vertical)
                    .lineLimit(5...8)
                    .padding(16)
                    .foregroundStyle(Palette.ink)
                    .background(Palette.paper, in: RoundedRectangle(cornerRadius: 16))
                    .focused($reflectionFocused)
                    .onChange(of: reflection) { _, text in
                        if text.count > 10_000 { reflection = String(text.prefix(10_000)) }
                    }

                if let error {
                    Text(error)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color(red: 1, green: 0.65, blue: 0.60))
                }

                Button(action: saveReflection) {
                    Text("Save")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Palette.pale, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("saveReflection")
            }
        }
    }

    private func cardSurface<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
        .padding(24)
        .frame(maxWidth: 360)
        .background(Color(red: 0.11, green: 0.13, blue: 0.12), in: RoundedRectangle(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 28, y: 12)
    }

    private func metric(_ value: String, caption: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 29, weight: .regular, design: .serif))
                .foregroundStyle(Palette.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.paper.opacity(0.75))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func showCard(reflectionEditor: Bool) {
        cardSwapTask?.cancel()
        withAnimation(.easeInOut(duration: cardFadeDuration)) { cardVisible = false }
        cardSwapTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(cardFadeDuration))
            guard !Task.isCancelled else { return }
            reflecting = reflectionEditor
            error = nil
            withAnimation(.easeInOut(duration: cardFadeDuration)) { cardVisible = true }
        }
    }

    private func saveReflection() {
        var updated = session
        updated.reflection = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.updatedAt = Date()
        guard model.saveSession(updated) else {
            error = model.errorMessage
            model.errorMessage = nil
            return
        }
        reflectionFocused = false
        showCard(reflectionEditor: false)
    }
}

struct TopBarButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 19, weight: .light)).frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}
struct PermissionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let purpose: AppModel.PermissionPurpose
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "bell.badge").font(.largeTitle).foregroundStyle(Palette.sage)
            Text(purpose == .completion ? "Your planned time." : "A moment to remember.").font(.system(.largeTitle, design: .serif))
            Text(purpose == .completion ? "Allow a notification when your planned time arrives, even with your screen locked. Your meditation keeps running until you end it. Sound follows your iPhone’s notification and Focus settings." : "Allow one gentle reminder at the time you choose. You can turn it off whenever you like.")
                .foregroundStyle(Palette.secondary)
            Button("Continue") { dismiss(); Task { await model.requestPermission(purpose) } }.buttonStyle(PrimaryButton())
            Button("Not now") { dismiss() }.frame(maxWidth: .infinity)
        }.padding(30).presentationDetents([.medium, .large]).presentationBackground(Palette.cream)
    }
}
