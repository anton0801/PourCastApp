import SwiftUI

/// First-launch walkthrough: four scenes that show the app doing its job,
/// built from the real components. Progress is the tick ruler (no dots),
/// transitions are the screed wipe (drag or Next, both directions), and
/// Skip is available on every scene. Completing scene 4 IS finishing
/// onboarding. Reduce Motion: crossfades, no sweeps.
struct OnboardingView: View {
    let done: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scene = 0
    @State private var incoming: Int?
    @State private var wipeForward = true
    @State private var wipeProgress: CGFloat = 0
    @State private var animatingWipe = false

    private let sceneCount = 4

    private var displayedScene: Int { incoming ?? scene }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, PCSpacing.l)
                .padding(.top, PCSpacing.m)
                .padding(.bottom, PCSpacing.s)

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    sceneView(scene)
                        .opacity(reduceMotion && incoming != nil ? 1 - wipeProgress : 1)

                    if let incoming {
                        if reduceMotion {
                            sceneView(incoming)
                                .opacity(wipeProgress)
                        } else {
                            sceneView(incoming)
                                .mask(alignment: wipeForward ? .leading : .trailing) {
                                    Rectangle()
                                        .frame(width: max(0, geo.size.width * wipeProgress))
                                }
                            if wipeProgress > 0.01, wipeProgress < 0.99 {
                                Rectangle()
                                    .fill(Color.accentTeal)
                                    .frame(width: 2, height: geo.size.height)
                                    .offset(x: wipeForward
                                            ? geo.size.width * wipeProgress
                                            : geo.size.width * (1 - wipeProgress))
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(pagerDrag(width: geo.size.width))
            }

            footer
                .padding(PCSpacing.l)
        }
        .background(FarmOnboardingBackdrop(scene: displayedScene))
        #if DEBUG
        // Screenshot/QA hook: SIMCTL_CHILD_PC_SCENE=2 opens a scene directly.
        .onAppear {
            if let raw = ProcessInfo.processInfo.environment["PC_SCENE"],
               let target = Int(raw), (0..<sceneCount).contains(target) {
                scene = target
            }
        }
        #endif
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(alignment: .center) {
            OnboardingProgressRuler(scene: displayedScene)
            Spacer()
            Button {
                done()
            } label: {
                Text("Skip")
                    .pcCapsLabel(.textSecondary)
                    .padding(.vertical, PCSpacing.xs)
                    .padding(.horizontal, PCSpacing.s)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Skip onboarding")
        }
    }

    private var footer: some View {
        HStack {
            if displayedScene > 0 {
                Button {
                    advance(-1)
                } label: {
                    HStack(spacing: PCSpacing.xs) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back")
                            .font(PCType.footnote.weight(.semibold))
                    }
                    .foregroundStyle(Color.textSecondary)
                    .padding(.vertical, PCSpacing.s)
                    .padding(.horizontal, PCSpacing.m)
                }
                .buttonStyle(.pressable)
            }
            Spacer()
            if displayedScene < sceneCount - 1 {
                Button {
                    advance(1)
                } label: {
                    HStack(spacing: PCSpacing.xs) {
                        Text("Next")
                            .font(PCType.body.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.surfaceElevated)
                    .padding(.vertical, PCSpacing.m)
                    .padding(.horizontal, PCSpacing.xl)
                    .background(Color.accentTeal, in: RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous))
                }
                .buttonStyle(.pressable)
            }
        }
        .animation(.pc, value: displayedScene)
    }

    // MARK: - Scenes

    @ViewBuilder
    private func sceneView(_ index: Int) -> some View {
        let active = index == displayedScene
        ScrollView {
            Group {
                switch index {
                case 0: SceneVerdictFlip(active: active)
                case 1: SceneChartProof(active: active)
                case 2: SceneCureGuard(active: active)
                default: SceneCrewSetup(active: active, done: done)
                }
            }
            .padding(.horizontal, PCSpacing.l)
            .padding(.vertical, PCSpacing.s)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Screed-wipe paging

    private func pagerDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 30)
            .onChanged { value in
                guard !animatingWipe, abs(value.translation.width) > abs(value.translation.height) else { return }
                let forward = value.translation.width < 0
                let target = forward ? scene + 1 : scene - 1
                guard (0..<sceneCount).contains(target) else {
                    incoming = nil
                    wipeProgress = 0
                    return
                }
                wipeForward = forward
                incoming = target
                wipeProgress = min(1, abs(value.translation.width) / width)
            }
            .onEnded { value in
                guard incoming != nil, !animatingWipe else { return }
                let flick = abs(value.predictedEndTranslation.width) > width * 0.5
                finishWipe(complete: wipeProgress > 0.33 || flick)
            }
    }

    private func advance(_ delta: Int) {
        let target = scene + delta
        guard (0..<sceneCount).contains(target), incoming == nil, !animatingWipe else { return }
        wipeForward = delta > 0
        incoming = target
        wipeProgress = 0
        finishWipe(complete: true)
    }

    private func finishWipe(complete: Bool) {
        guard let target = incoming else { return }
        animatingWipe = true
        if complete { Haptics.selection() }
        withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .easeInOut(duration: 0.4)) {
            wipeProgress = complete ? 1 : 0
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 440_000_000)
            if complete { scene = target }
            incoming = nil
            wipeProgress = 0
            animatingWipe = false
        }
    }
}

/// Progress as the formwork ruler: four major ticks fill as scenes pass.
struct OnboardingProgressRuler: View {
    let scene: Int

    var body: some View {
        Canvas { context, size in
            let majors = 4
            let minorsBetween = 3
            let slots = majors + (majors - 1) * minorsBetween
            let step = size.width / CGFloat(slots - 1)

            var index = 0
            for slot in 0..<slots {
                let x = CGFloat(slot) * step
                let isMajor = slot % (minorsBetween + 1) == 0
                let length: CGFloat = isMajor ? size.height : size.height * 0.45
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: size.height))
                tick.addLine(to: CGPoint(x: x, y: size.height - length))
                if isMajor {
                    let filled = index <= scene
                    context.stroke(
                        tick,
                        with: .color(filled ? .accentTeal : .textSecondary.opacity(0.3)),
                        lineWidth: filled ? 2.5 : 1.5
                    )
                    index += 1
                } else {
                    context.stroke(tick, with: .color(.textSecondary.opacity(0.2)), lineWidth: 1)
                }
            }
        }
        .frame(width: 130, height: 14)
        .accessibilityLabel("Step \(scene + 1) of 4")
    }
}
